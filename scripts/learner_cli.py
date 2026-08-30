#!/usr/bin/env python3
"""CLI d'apprentissage DevOps — V0."""

import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import textwrap
from typing import Any, Dict, Optional

import yaml

# Rendre gemini_client importable depuis scripts/
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

try:
    from gemini_client import LLMClient
except Exception:
    LLMClient = None  # type: ignore

DEFAULT_SKILLS: Dict[str, list] = {
    "kubernetes": ["pods", "deployments", "services", "configmaps", "secrets"],
    "terraform": ["state_management", "modules", "workspaces"],
    "python": ["scripting", "data_structures", "testing"],
    "network": ["osi_model", "tcp_ip", "dns"],
    "linux": ["filesystem", "permissions", "processes"],
    "softskills": ["communication", "troubleshooting", "documentation"],
}


def load_yaml(path: str) -> Any:
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


def write_yaml(path: str, data: Any) -> None:
    os.makedirs(os.path.dirname(path) if os.path.dirname(path) else ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        yaml.safe_dump(data, f, sort_keys=False, allow_unicode=True)


def find_stack() -> str:
    for name in sorted(os.listdir("stacks")):
        if name.startswith(".") or not os.path.isdir(os.path.join("stacks", name)):
            continue
        return name
    raise RuntimeError("Aucune stack trouvée dans stacks/")


def profile_path(stack: str) -> str:
    return f"stacks/{stack}/profile.yaml"


def sprint_dir(stack: str, sprint: int) -> str:
    return f"sprints/sprint_{sprint:02d}"


def step_dir(stack: str, sprint: int, step: int) -> str:
    return os.path.join(sprint_dir(stack, sprint), f"step_{step:02d}")


def default_skill(level: float) -> Dict:
    return {
        "level": round(level, 2),
        "confidence": round(level * 0.9, 2),
        "last_used": None,
        "error_patterns": [],
    }


def init_profile(stack: str) -> None:
    now = datetime.datetime.now(datetime.timezone.utc).isoformat() + "Z"
    skills: Dict[str, Dict] = {}
    for skill, topics in DEFAULT_SKILLS.items():
        skills[skill] = {topic: default_skill(round(0.1 + i * 0.05, 2)) for i, topic in enumerate(topics)}
    data = {
        "version": 1,
        "last_updated": now,
        "global": {"overall_level": 0.2, "current_sprint": 0},
        "skills": skills,
    }
    os.makedirs(os.path.dirname(profile_path(stack)), exist_ok=True)
    write_yaml(profile_path(stack), data)


def load_profile(stack: str) -> Dict:
    path = profile_path(stack)
    if not os.path.exists(path):
        raise RuntimeError(f"Profile manquant : {path}. Lance 'init' d'abord.")
    return load_yaml(path)


def save_profile(stack: str, data: Dict) -> None:
    data["last_updated"] = datetime.datetime.now(datetime.timezone.utc).isoformat() + "Z"
    write_yaml(profile_path(stack), data)


def find_llm() -> Optional[Any]:
    if LLMClient is None:
        return None
    try:
        return LLMClient()
    except RuntimeError:
        return None


def read_resource(path: str) -> str:
    if not os.path.exists(path):
        return ""
    with open(path, encoding="utf-8") as f:
        return f.read()


def generate_brief(stack: str, sprint: int, profile: Dict) -> str:
    book = read_resource(f"stacks/{stack}/resources/book_toc.md")
    modules = read_resource(f"stacks/{stack}/resources/kodekloud_modules.md")
    system = "Tu es un Product Owner pédagogique. Tu rédiges un brief d'objectifs concret pour un sprint DevOps."
    user = (
        f"Stack : {stack}\n"
        f"Sprint : {sprint}\n"
        f"Profil : {json.dumps(profile, ensure_ascii=False, indent=2)}\n"
        f"Ressources book : {book[:2000]}\n"
        f"Ressources modules : {modules[:2000]}\n"
        "Rédige un brief.md court avec : contexte métier, objectif du sprint, livrables attendus."
    )
    llm = find_llm()
    if llm:
        try:
            return llm.chat(system, user)
        except Exception as exc:
            print(f"LLM indisponible, fallback local : {exc}", file=sys.stderr)
    return textwrap.dedent(f"""\
        # Brief sprint {sprint:02d} — {stack}

        ## Contexte
        Objectif d'apprentissage pour le sprint {sprint} sur {stack}.

        ## Livrables
        - Comprendre les concepts du sprint {sprint}.
        - Compléter les TODO des 3 étapes.
        - Valider chaque étape avec `learner_cli.py test --step <n>`.

        ## Ressources
        Voir `stacks/{stack}/resources/`.
        """)


def create_validation_script(path: str, step: int, stack: str) -> None:
    content = textwrap.dedent(f"""\
        #!/bin/bash
        set -euo pipefail

        # Step {step:02d} — sprint {stack}
        # TODO: remplacer cette valeur par le résultat attendu de ta vérification
        EXPECTED="TODO"

        echo "Vérification step {step:02d}..."

        if [ "$EXPECTED" == "TODO" ]; then
            echo "FAIL — Step {step:02d} non complétée (TODO)."
            exit 1
        fi

        echo "PASS — Step {step:02d} validée."
        """)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    os.chmod(path, 0o755)


def cmd_init(args: argparse.Namespace) -> None:
    stack = args.stack or find_stack()
    init_profile(stack)
    print(f"Profile créé : {profile_path(stack)}")


def cmd_start(args: argparse.Namespace) -> None:
    stack = args.stack or find_stack()
    sprint = args.sprint
    profile = load_profile(stack)
    profile["global"]["current_sprint"] = sprint
    save_profile(stack, profile)

    sdir = sprint_dir(stack, sprint)
    os.makedirs(sdir, exist_ok=True)

    brief = generate_brief(stack, sprint, profile)
    with open(os.path.join(sdir, "brief.md"), "w", encoding="utf-8") as f:
        f.write(brief)

    for step in range(1, 4):
        sdir_step = step_dir(stack, sprint, step)
        os.makedirs(sdir_step, exist_ok=True)
        vpath = os.path.join(sdir_step, f"step_{step:02d}_validation.sh")
        create_validation_script(vpath, step, stack)
        with open(os.path.join(sdir_step, f"step_{step:02d}_result.txt"), "w", encoding="utf-8") as f:
            f.write("")

    print(f"Sprint {sprint:02d} généré dans {sdir}")


def cmd_test(args: argparse.Namespace) -> None:
    stack = args.stack or find_stack()
    step = args.step
    profile = load_profile(stack)
    sprint = profile["global"].get("current_sprint", 1)
    vpath = os.path.join(step_dir(stack, sprint, step), f"step_{step:02d}_validation.sh")
    rpath = os.path.join(step_dir(stack, sprint, step), f"step_{step:02d}_result.txt")

    if not os.path.exists(vpath):
        raise RuntimeError(f"Script manquant : {vpath}. Lance 'start' d'abord.")

    start = datetime.datetime.now(datetime.timezone.utc)
    result = subprocess.run([vpath], capture_output=True, text=True, timeout=10)
    elapsed = (datetime.datetime.now(datetime.timezone.utc) - start).total_seconds()

    has_pass = result.returncode == 0 and any(
        line.startswith("PASS") for line in result.stdout.splitlines()
    )
    status = "PASS" if has_pass else "FAIL"

    content = (
        f"{status} {elapsed:.2f}s\n"
        "---\n"
        f"STDOUT:\n{result.stdout}\n"
        f"STDERR:\n{result.stderr}\n"
        "--- Summary ---\n"
        f"{status} pour step {step:02d}"
    )
    with open(rpath, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"{status} ({elapsed:.2f}s)")


def cmd_chat(args: argparse.Namespace) -> None:
    stack = args.stack or find_stack()
    profile = load_profile(stack)
    book = read_resource(f"stacks/{stack}/resources/book_toc.md")
    modules = read_resource(f"stacks/{stack}/resources/kodekloud_modules.md")
    system = (
        "Tu es un mentor DevOps. Réponds de manière concise. "
        f"Contexte : profil {json.dumps(profile['global'], ensure_ascii=False)}, "
        f"compétences {list(profile['skills'].keys())}."
    )
    llm = find_llm()
    if not llm:
        print(
            "Aucune clé LLM configurée. Définis GEMINI_API_KEY ou DEEPSEEK_API_KEY.",
            file=sys.stderr,
        )
        return

    history_path = os.path.join(os.getcwd(), ".chat_history.json")
    history = []
    if os.path.exists(history_path):
        with open(history_path, encoding="utf-8") as f:
            history = json.load(f)

    print("Chat DevOps (tape /quit)")
    while True:
        try:
            user_input = input("> ")
        except EOFError:
            break
        if user_input.strip().lower() in ("/quit", "/exit"):
            break
        context = (
            f"Profil : {json.dumps(profile, ensure_ascii=False)}\n"
            f"Ressources : {book[:1500]}\n{modules[:1500]}\n"
            f"Question : {user_input}"
        )
        try:
            response = llm.chat(system, context)
        except Exception as exc:
            print(f"Erreur LLM : {exc}")
            continue
        print(response)
        history.append({"role": "user", "content": user_input})
        history.append({"role": "assistant", "content": response})
        with open(history_path, "w", encoding="utf-8") as f:
            json.dump(history, f, indent=2, ensure_ascii=False)


def git_current_branch() -> str:
    return subprocess.run(
        ["git", "branch", "--show-current"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()


def cmd_submit(args: argparse.Namespace) -> None:
    stack = args.stack or find_stack()
    profile = load_profile(stack)
    sprint = profile["global"].get("current_sprint", 1)

    for step in range(1, 4):
        rpath = os.path.join(step_dir(stack, sprint, step), f"step_{step:02d}_result.txt")
        if not os.path.exists(rpath):
            raise RuntimeError(f"Step {step:02d} non testée. Lance 'test --step {step}' d'abord.")
        content = open(rpath, encoding="utf-8").read()
        if not re.search(r"^PASS", content, re.MULTILINE):
            raise RuntimeError(f"Step {step:02d} non PASS. Corrige et relance.")

    global_result_path = os.path.join(sprint_dir(stack, sprint), "sprint_result.txt")
    with open(global_result_path, "w", encoding="utf-8") as f:
        f.write(f"PASS — Sprint {sprint:02d} complété pour {stack}.\n--- Summary ---\nGlobal PASS")

    branch = f"step/{stack}/{sprint:02d}-sprint-{sprint:02d}"
    previous = git_current_branch()

    subprocess.run(["git", "checkout", "main"], check=True)
    subprocess.run(["git", "checkout", "-b", branch], check=True)

    files_to_add = [
        profile_path(stack),
        sprint_dir(stack, sprint),
        global_result_path,
    ]
    for p in files_to_add:
        if os.path.exists(p):
            subprocess.run(["git", "add", "-f", p], check=True)

    subprocess.run(
        ["git", "commit", "-m", f"chore: sprint {sprint:02d} learner artifacts"],
        check=True,
    )
    subprocess.run(["git", "push", "origin", branch], check=True)

    subprocess.run(
        [
            "gh", "pr", "create",
            "--base", "main",
            "--head", branch,
            "--title", f"Sprint {sprint:02d} — {stack}",
            "--body", "Livrables générés par learner_cli.py submit.",
        ],
        check=True,
    )

    print(f"PR ouverte depuis {branch} vers main.")
    print(f"Pour revenir à ta branche de travail : git checkout {previous}")


def main() -> None:
    parser = argparse.ArgumentParser(description="CLI d'apprentissage DevOps")
    sub = parser.add_subparsers(dest="command", required=True)

    init_p = sub.add_parser("init")
    init_p.add_argument("--stack", default=None)

    start_p = sub.add_parser("start")
    start_p.add_argument("--sprint", type=int, default=1)
    start_p.add_argument("--stack", default=None)

    test_p = sub.add_parser("test")
    test_p.add_argument("--step", type=int, required=True)
    test_p.add_argument("--stack", default=None)

    chat_p = sub.add_parser("chat")
    chat_p.add_argument("--stack", default=None)

    submit_p = sub.add_parser("submit")
    submit_p.add_argument("--stack", default=None)

    args = parser.parse_args()
    if args.command == "init":
        cmd_init(args)
    elif args.command == "start":
        cmd_start(args)
    elif args.command == "test":
        cmd_test(args)
    elif args.command == "chat":
        cmd_chat(args)
    elif args.command == "submit":
        cmd_submit(args)


if __name__ == "__main__":
    main()
