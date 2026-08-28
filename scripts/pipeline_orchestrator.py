#!/usr/bin/env python3
import argparse
import base64
import datetime
import json
import os
import re
import subprocess
import sys
from typing import Any, Dict, List, Optional, Tuple

import requests
import yaml

from gemini_client import LLMClient

REPO = os.environ.get("GITHUB_REPOSITORY", "")
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "")
GITHUB_API = "https://api.github.com"

HEADERS = {
    "Accept": "application/vnd.github+json",
    "Authorization": f"Bearer {GITHUB_TOKEN}",
    "X-GitHub-Api-Version": "2022-11-28",
}


def _gh(method: str, path: str, json_data: Optional[Dict] = None, params: Optional[Dict] = None) -> Any:
    url = f"{GITHUB_API}/{path}"
    response = requests.request(method, url, headers=HEADERS, json=json_data, params=params, timeout=30)
    response.raise_for_status()
    if response.status_code == 204:
        return None
    return response.json()


def gh_get(path: str, params: Optional[Dict] = None) -> Any:
    return _gh("GET", path, params=params)


def gh_post(path: str, json_data: Dict) -> Any:
    return _gh("POST", path, json_data)


def gh_put(path: str, json_data: Dict) -> Any:
    return _gh("PUT", path, json_data)


def gh_delete(path: str) -> Any:
    return _gh("DELETE", path)


def find_stack() -> str:
    for name in sorted(os.listdir("stacks")):
        full = os.path.join("stacks", name)
        if os.path.isdir(full) and not name.startswith("."):
            return name
    raise RuntimeError("Aucune stack trouvée dans stacks/")


def load_yaml(path: str) -> Any:
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


def write_yaml(path: str, data: Any) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        yaml.safe_dump(data, f, sort_keys=False, allow_unicode=True)


def load_text(path: str) -> str:
    if not os.path.exists(path):
        return ""
    with open(path, encoding="utf-8") as f:
        return f.read()


def _first_meaningful_line(content: str) -> str:
    """Retourne la première ligne non vide qui ne commence pas par # ou =."""
    for line in content.splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith(("#", "=")):
            return stripped
    return ""


def format_template(text: str, step: int) -> str:
    step_padded = f"{step:02d}"
    return text.format(step=step, step_padded=step_padded)


def load_stack(stack: str) -> Dict:
    return load_yaml(f"stacks/{stack}/roadmap.yaml")


def load_state(stack: str) -> Dict:
    return load_yaml(f"stacks/{stack}/CONTEXT_STATE.yaml")


def save_state(stack: str, state: Dict) -> None:
    state["last_updated"] = datetime.datetime.utcnow().isoformat() + "Z"
    write_yaml(f"stacks/{stack}/CONTEXT_STATE.yaml", state)


def load_test_strategy(stack: str) -> Dict:
    path = f"stacks/{stack}/test_strategy.yaml"
    if os.path.exists(path):
        return load_yaml(path)
    return {
        "tool": "l'outil de la stack",
        "tooling_name": stack,
        "required_files": [
            "infra/adrs/adr_step_{step:02d}_final.md",
            "tests/step_{step:02d}_validation.sh",
            "tests/step_{step:02d}_result.txt",
        ],
        "pass_markers": ["PASS"],
        "suggested_command": "tests/step_{step:02d}_validation.sh",
        "validation_output": "tests/step_{step:02d}_result.txt",
        "static_checks": [],
    }


def render_template(template: str, context: Dict[str, Any]) -> str:
    return template.format(**context)


def load_prompt(stack: str, name: str, context: Dict[str, Any]) -> str:
    path = f"stacks/{stack}/prompts/{name}"
    raw = load_text(path)
    if not raw:
        raise RuntimeError(f"Prompt {path} introuvable")
    return render_template(raw, context)


def get_main_sha() -> str:
    ref = gh_get(f"repos/{REPO}/git/ref/heads/main")
    return ref["object"]["sha"]


def create_branch(stack: str, step: int, title: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")[:40]
    branch = f"step/{stack}/{step:02d}-{slug}"
    try:
        gh_delete(f"repos/{REPO}/git/refs/heads/{branch}")
    except requests.HTTPError:
        pass
    sha = get_main_sha()
    gh_post(f"repos/{REPO}/git/refs", {"ref": f"refs/heads/{branch}", "sha": sha})
    return branch


def create_or_update_file(stack: str, branch: str, rel_path: str, content: str, message: str) -> None:
    api_path = f"repos/{REPO}/contents/stacks/{stack}/{rel_path}"
    encoded = base64.b64encode(content.encode("utf-8")).decode("utf-8")
    data = {"message": message, "content": encoded, "branch": branch}
    try:
        existing = gh_get(f"{api_path}?ref={branch}")
        if existing.get("sha"):
            data["sha"] = existing["sha"]
    except requests.HTTPError as exc:
        if exc.response.status_code != 404:
            raise
    gh_put(api_path, data)


def create_pr(stack: str, branch: str, title: str, body: str) -> Tuple[int, str]:
    pr = gh_post(
        f"repos/{REPO}/pulls",
        {
            "title": title,
            "body": body,
            "head": branch,
            "base": "main",
        },
    )
    return pr["number"], pr["html_url"]


def commit_to_main(paths: List[str], message: str) -> None:
    for p in paths:
        if os.path.exists(p):
            subprocess.run(["git", "add", p], check=True)

    diff = subprocess.run(["git", "diff", "--cached", "--quiet"], check=False)
    if diff.returncode == 0:
        return

    subprocess.run(["git", "config", "user.email", "devin-ai[bot]@users.noreply.github.com"], check=False)
    subprocess.run(["git", "config", "user.name", "Devin AI"], check=False)
    subprocess.run(["git", "commit", "-m", message], check=True)
    subprocess.run(["git", "push", "origin", "main"], check=True)


def build_context(
    stack: str,
    step: int,
    step_info: Dict,
    state: Dict,
    roadmap: Dict,
    test_strategy: Dict,
) -> Dict[str, Any]:
    step_padded = f"{step:02d}"
    suggested_command = format_template(test_strategy.get("suggested_command", "tests/step_{step:02d}_validation.sh"), step)
    validation_output = format_template(test_strategy.get("validation_output", "tests/step_{step:02d}_result.txt"), step)
    required_files = "\n".join(
        [format_template(f, step) for f in test_strategy.get("required_files", [])]
    )
    return {
        "stack": stack,
        "step": step,
        "step_padded": step_padded,
        "title": step_info.get("title", ""),
        "description": step_info.get("description", ""),
        "tool": test_strategy.get("tool", "l'outil de la stack"),
        "tooling_name": test_strategy.get("tooling_name", stack),
        "suggested_command": suggested_command,
        "validation_output": validation_output,
        "required_files": required_files,
        "book_toc": load_text(f"stacks/{stack}/resources/book_toc.md"),
        "kodekloud_modules": load_text(f"stacks/{stack}/resources/kodekloud_modules.md"),
        "state": yaml.safe_dump(state),
        "roadmap": yaml.safe_dump(roadmap),
    }


def update_state_from_step(llm: LLMClient, stack: str, step: int, step_info: Dict, state: Dict, test_strategy: Dict) -> None:
    ctx = build_context(stack, step, step_info, state, load_stack(stack), test_strategy)
    prompt = load_prompt(stack, "system_state_updater.txt", ctx)
    adr = load_text(f"stacks/{stack}/infra/adrs/adr_step_{step:02d}_final.md")
    result = load_text(f"stacks/{stack}/{format_template(test_strategy['validation_output'], step)}")
    retro = load_text(f"stacks/{stack}/retrospectives/retro_step_{step:02d}.md")
    user_prompt = (
        f"Étape : {step} - {step_info['title']}\n\n"
        f"ADR final :\n{adr}\n\n"
        f"Résultat de validation :\n{result}\n\n"
        f"Rétrospective :\n{retro}"
    )
    output = llm.chat(prompt, user_prompt)
    parsed = parse_state_update(output)
    if parsed.get("context_capsule"):
        state["context_capsule"] = parsed["context_capsule"]
    for key in ("key_decisions", "pending_risks"):
        values = parsed.get(key)
        if values:
            state.setdefault(key, []).extend(values if isinstance(values, list) else [values])


def parse_state_update(output: str) -> Dict:
    text = output.strip()
    match = re.search(r"```(?:yaml|json)?\n(.*?)```", text, re.DOTALL)
    if match:
        text = match.group(1).strip()
    try:
        data = yaml.safe_load(text)
    except Exception:
        return {}
    if not isinstance(data, dict):
        return {}
    return {
        "context_capsule": data.get("context_capsule", ""),
        "key_decisions": data.get("key_decisions", []),
        "pending_risks": data.get("pending_risks", []),
    }


def generate_retrospective(llm: LLMClient, stack: str, step: int, step_info: Dict, state: Dict, test_strategy: Dict) -> str:
    ctx = build_context(stack, step, step_info, state, load_stack(stack), test_strategy)
    prompt = load_prompt(stack, "system_retrospective.txt", ctx)
    adr = load_text(f"stacks/{stack}/infra/adrs/adr_step_{step:02d}_final.md")
    result = load_text(f"stacks/{stack}/{format_template(test_strategy['validation_output'], step)}")
    review = ""
    user_prompt = (
        f"Étape : {step} - {step_info['title']}\n\n"
        f"ADR final :\n{adr}\n\n"
        f"Review SRE :\n{review}\n\n"
        f"Résultats :\n{result}"
    )
    return llm.chat(prompt, user_prompt)


def build_dashboard_data(args: argparse.Namespace) -> None:
    stacks_data: Dict[str, Dict] = {}
    for name in _list_stacks():
        try:
            stacks_data[name] = {
                "roadmap": load_stack(name),
                "state": load_state(name),
                "pull_requests": [],
            }
        except Exception:
            stacks_data[name] = {"roadmap": {}, "state": {}, "pull_requests": []}

    if REPO and GITHUB_TOKEN:
        try:
            prs = gh_get(f"repos/{REPO}/pulls", {"state": "open", "per_page": "100", "base": "main"})
            for pr in prs:
                ref = pr.get("head", {}).get("ref", "")
                match = re.search(r"step/([^/]+)/(\d+)", ref)
                if match:
                    stack = match.group(1)
                    step = int(match.group(2))
                    if stack in stacks_data:
                        stacks_data[stack]["pull_requests"].append({
                            "step": step,
                            "number": pr["number"],
                            "html_url": pr["html_url"],
                            "title": pr["title"],
                        })
        except Exception as e:
            print(f"Avertissement : impossible de charger les PRs ouvertes : {e}")

    data = {
        "stacks": stacks_data,
        "generated_at": datetime.datetime.utcnow().isoformat() + "Z",
    }
    output = args.output or "data.json"
    os.makedirs(os.path.dirname(output) if os.path.dirname(output) else ".", exist_ok=True)
    with open(output, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print(f"Données dashboard écrites dans {output}")


def _list_stacks() -> List[str]:
    return [d for d in sorted(os.listdir("stacks")) if os.path.isdir(os.path.join("stacks", d)) and not d.startswith(".")]


def generate_mission(args: argparse.Namespace) -> None:
    if not REPO or not GITHUB_TOKEN:
        raise RuntimeError("GITHUB_REPOSITORY et GITHUB_TOKEN doivent être définis")

    llm = LLMClient()
    if args.pr_head_ref:
        stack, _ = parse_branch_ref(args.pr_head_ref)
        generate_mission_for_stack(llm, stack)
    elif args.stack:
        generate_mission_for_stack(llm, args.stack)
    else:
        for stack in _list_stacks():
            if load_state(stack).get("current_step", 0) == 0:
                generate_mission_for_stack(llm, stack)


def generate_mission_for_stack(llm: LLMClient, stack: str) -> None:
    roadmap = load_stack(stack)
    state = load_state(stack)
    test_strategy = load_test_strategy(stack)
    current = state.get("current_step", 0)

    # Rétrospective + State Updater de l'étape terminée
    retro_path: Optional[str] = None
    if current > 0:
        prev_step = next((s for s in roadmap["steps"] if s["step"] == current), None)
        if prev_step:
            retro = generate_retrospective(llm, stack, current, prev_step, state, test_strategy)
            retro_path = f"stacks/{stack}/retrospectives/retro_step_{current:02d}.md"
            os.makedirs(os.path.dirname(retro_path), exist_ok=True)
            with open(retro_path, "w", encoding="utf-8") as f:
                f.write(retro)
            update_state_from_step(llm, stack, current, prev_step, state, test_strategy)

    # Prépare la prochaine étape
    next_step = current + 1
    if next_step > roadmap["total_steps"]:
        state["status"] = "completed"
        save_state(stack, state)
        commit_to_main([f"stacks/{stack}/CONTEXT_STATE.yaml"] + ([retro_path] if retro_path else []),
                       f"chore: parcours terminé, rétro étape {current:02d}")
        print("Toutes les étapes sont terminées. Aucune nouvelle mission.")
        return

    step_info = next((s for s in roadmap["steps"] if s["step"] == next_step), None)
    if step_info is None:
        raise RuntimeError(f"Étape {next_step} introuvable dans la roadmap")

    state["current_step"] = next_step
    state["status"] = "in_progress"
    save_state(stack, state)

    # Commit rétro + nouvel état sur main
    paths_to_commit = [f"stacks/{stack}/CONTEXT_STATE.yaml"]
    if retro_path:
        paths_to_commit.append(retro_path)
    commit_to_main(paths_to_commit, f"chore: state update step {next_step:02d} + rétro step {current:02d}")

    # Génère la mission
    ctx = build_context(stack, next_step, step_info, state, roadmap, test_strategy)
    prompt = load_prompt(stack, "system_po.txt", ctx)
    user_prompt = (
        f"Roadmap :\n{ctx['roadmap']}\n\n"
        f"Étape actuelle : {next_step} - {step_info['title']}\n\n"
        f"Book TOC :\n{ctx['book_toc']}\n\n"
        f"Modules KodeKloud :\n{ctx['kodekloud_modules']}\n\n"
        f"Stratégie de test :\n{yaml.safe_dump(test_strategy)}\n\n"
        f"Contexte :\n{ctx['state']}"
    )
    mission = llm.chat(prompt, user_prompt)

    # Crée la branche et pousse la mission pour avoir un diff
    branch = create_branch(stack, next_step, step_info["title"])
    create_or_update_file(
        stack,
        branch,
        f"missions/mission_step_{next_step:02d}.md",
        mission,
        f"mission: step {next_step:02d}",
    )
    pr_number, pr_url = create_pr(stack, branch, f"Step {next_step:02d}: {step_info['title']}", mission)
    print(f"PR #{pr_number} créée : {pr_url}")


def parse_branch_ref(head_ref: str) -> Tuple[str, int]:
    match = re.search(r"step/([^/]+)/(\d+)", head_ref)
    if not match:
        raise RuntimeError(f"Nom de branche invalide : {head_ref} (attendu step/<stack>/XX-nom)")
    return match.group(1), int(match.group(2))


def check_pr(args: argparse.Namespace) -> None:
    head_ref = args.pr_head_ref or os.environ.get("GITHUB_HEAD_REF", "")
    if not head_ref:
        raise RuntimeError("--pr-head-ref ou GITHUB_HEAD_REF requis")

    branch_stack, step = parse_branch_ref(head_ref)
    stack = args.stack or branch_stack
    test_strategy = load_test_strategy(stack)
    required = [format_template(f, step) for f in test_strategy.get("required_files", [])]

    missing: List[str] = []
    for f in required:
        path = f"stacks/{stack}/{f}"
        if not os.path.exists(path) or os.path.getsize(path) == 0:
            missing.append(path)
    if missing:
        raise RuntimeError(f"Fichiers manquants ou vides : {', '.join(missing)}")

    validation_output = format_template(test_strategy.get("validation_output", "tests/step_{step:02d}_result.txt"), step)
    result_path = f"stacks/{stack}/{validation_output}"
    if not os.path.exists(result_path):
        raise RuntimeError(f"Fichier de résultat manquant : {result_path}")

    content = load_text(result_path).strip()
    if not content:
        raise RuntimeError(f"Fichier de résultat vide : {result_path}")

    pass_markers = test_strategy.get("pass_markers", ["PASS"])
    first_line = _first_meaningful_line(content)
    if first_line.startswith("FAIL"):
        raise RuntimeError(f"Tests en echec. Voir {result_path}")
    if first_line.startswith("PENDING"):
        raise RuntimeError(f"Tests non executes. Mettez a jour {result_path}")
    if not first_line.startswith(tuple(pass_markers)):
        raise RuntimeError(f"Premiere ligne utile doit commencer par {pass_markers} dans {result_path}")

    # Attestation légère : exige une section --- Summary ---
    if "--- Summary ---" not in content:
        raise RuntimeError(f"Section '--- Summary ---' manquante dans {result_path}")

    # Vérifications statiques optionnelles définies dans test_strategy.yaml
    for check in test_strategy.get("static_checks", []):
        check = format_template(check, step)
        print(f"Verification statique : {check}")
        subprocess.run(check, shell=True, check=True, cwd=f"stacks/{stack}")

    print(f"Etape {step:02d} OK — artifacts presents, attestation et verifications statiques conformes")


def post_pr_comment(pr_number: int, body: str, key: str = "") -> None:
    marker = f"<!-- review-key:{key} -->"
    full_body = f"{marker}\n{body}"
    if key:
        comments = gh_get(f"repos/{REPO}/issues/{pr_number}/comments")
        for c in comments:
            if marker in c.get("body", ""):
                _gh("PATCH", f"repos/{REPO}/issues/comments/{c['id']}", {"body": full_body})
                return
    gh_post(f"repos/{REPO}/issues/{pr_number}/comments", {"body": full_body})


def review_adr(args: argparse.Namespace) -> None:
    if not REPO or not GITHUB_TOKEN:
        raise RuntimeError("GITHUB_REPOSITORY et GITHUB_TOKEN doivent être définis")

    llm = LLMClient()
    stack = args.stack or find_stack()
    head_ref = args.pr_head_ref or os.environ.get("GITHUB_HEAD_REF", "")
    pr_number = int(os.environ.get("PR_NUMBER", "0"))
    if not pr_number:
        raise RuntimeError("PR_NUMBER requis")

    branch_stack, step = parse_branch_ref(head_ref)
    test_strategy = load_test_strategy(stack)
    roadmap = load_stack(stack)
    state = load_state(stack)
    step_info = next((s for s in roadmap["steps"] if s["step"] == step), None)
    if step_info is None:
        raise RuntimeError(f"Étape {step} introuvable")

    v1_path = f"stacks/{stack}/infra/adrs/adr_step_{step:02d}_v1.md"
    final_path = f"stacks/{stack}/infra/adrs/adr_step_{step:02d}_final.md"
    adr_path = v1_path if os.path.exists(v1_path) else final_path
    if not os.path.exists(adr_path):
        print(f"Pas d'ADR à reviewer pour l'étape {step:02d}")
        return

    ctx = build_context(stack, step, step_info, state, roadmap, test_strategy)
    prompt = load_prompt(stack, "system_architect.txt", ctx)
    adr = load_text(adr_path)
    user_prompt = f"ADR à reviewer :\n\n{adr}"
    review = llm.chat(prompt, user_prompt)
    post_pr_comment(pr_number, f"## Review Architecte — Étape {step:02d}\n\n{review}", f"review-adr-{pr_number}")
    print(f"Review ADR postée sur PR #{pr_number}")


def sre_review(args: argparse.Namespace) -> None:
    if not REPO or not GITHUB_TOKEN:
        raise RuntimeError("GITHUB_REPOSITORY et GITHUB_TOKEN doivent être définis")

    llm = LLMClient()
    stack = args.stack or find_stack()
    head_ref = args.pr_head_ref or os.environ.get("GITHUB_HEAD_REF", "")
    pr_number = int(os.environ.get("PR_NUMBER", "0"))
    if not pr_number:
        raise RuntimeError("PR_NUMBER requis")

    branch_stack, step = parse_branch_ref(head_ref)
    test_strategy = load_test_strategy(stack)
    roadmap = load_stack(stack)
    state = load_state(stack)
    step_info = next((s for s in roadmap["steps"] if s["step"] == step), None)
    if step_info is None:
        raise RuntimeError(f"Étape {step} introuvable")

    result_path = f"stacks/{stack}/{format_template(test_strategy['validation_output'], step)}"
    final_adr = f"stacks/{stack}/infra/adrs/adr_step_{step:02d}_final.md"
    if not os.path.exists(result_path) or not os.path.exists(final_adr):
        print(f"Artefacts incomplets pour l'étape {step:02d}, SRE review ignorée")
        return

    result = load_text(result_path).strip()
    pass_markers = test_strategy.get("pass_markers", ["PASS"])
    if not _first_meaningful_line(result).startswith(tuple(pass_markers)):
        print(f"Tests non PASS pour l'etape {step:02d}, SRE review ignoree")
        return

    manifests_dir = f"stacks/{stack}/infra/manifests"
    manifests = ""
    if os.path.isdir(manifests_dir):
        for name in sorted(os.listdir(manifests_dir)):
            path = os.path.join(manifests_dir, name)
            if os.path.isfile(path):
                manifests += f"\n--- {name} ---\n" + load_text(path)

    adr = load_text(final_adr)
    ctx = build_context(stack, step, step_info, state, roadmap, test_strategy)
    prompt = load_prompt(stack, "system_lead_sre_review.txt", ctx)
    user_prompt = (
        f"ADR final :\n{adr}\n\n"
        f"Résultat de validation :\n{result}\n\n"
        f"Artefacts d'infra :\n{manifests}"
    )
    review = llm.chat(prompt, user_prompt)
    post_pr_comment(pr_number, f"## Review SRE — Étape {step:02d}\n\n{review}", f"review-sre-{pr_number}")
    print(f"Review SRE postée sur PR #{pr_number}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Orchestrateur agnostique du learning platform")
    parser.add_argument("--action", required=True,
                        choices=["generate-mission", "build-dashboard-data", "check-pr", "review-adr", "sre-review"])
    parser.add_argument("--output", help="Chemin du fichier de sortie (build-dashboard-data)")
    parser.add_argument("--stack", help="Nom de la stack (détection auto si omis)")
    parser.add_argument("--pr-head-ref", help="Nom de la branche PR (check-pr, review-adr, sre-review)")
    args = parser.parse_args()

    if args.action == "generate-mission":
        generate_mission(args)
    elif args.action == "build-dashboard-data":
        build_dashboard_data(args)
    elif args.action == "check-pr":
        check_pr(args)
    elif args.action == "review-adr":
        review_adr(args)
    elif args.action == "sre-review":
        sre_review(args)


if __name__ == "__main__":
    main()
