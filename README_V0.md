# V0 — Simulateur d'apprentissage DevOps (CLI + Web UI)

## Fichiers ajoutés

- `scripts/learner_cli.py` : CLI d'apprentissage.
- `scripts/web_ui/app.py` : interface Streamlit.
- `docs/branching-guide.md` : guide des branches d'amélioration.

## Dépendances

```bash
pip install pyyaml requests streamlit
```

## CLI

### `init`

Génère le profil pour la stack courante.

```bash
python scripts/learner_cli.py init
python scripts/learner_cli.py init --stack kubernetes
```

### `start`

Génère le sprint et ses 3 étapes.

```bash
python scripts/learner_cli.py start --sprint 1
```

Crée :

- `sprints/sprint_01/brief.md`
- `sprints/sprint_01/step_01/step_01_validation.sh` + `step_01_result.txt`
- `sprints/sprint_01/step_02/...`
- `sprints/sprint_01/step_03/...`

### `test`

Exécute un script de validation et affiche `PASS`/`FAIL` en moins de 3 secondes.

```bash
python scripts/learner_cli.py test --step 1
```

Modifie le `EXPECTED="TODO"` dans le script pour passer à `PASS`.

### `chat`

Chat terminal avec `profile.yaml` et les ressources en contexte.

```bash
export GEMINI_API_KEY=<clé>
python scripts/learner_cli.py chat
```

L'historique est stocké dans `.chat_history.json` (gitignoré).

### `submit`

Vérifie que les 3 étapes passent, crée une branche `step/<stack>/<sprint>-sprint-<sprint>`, pousse et ouvre une PR.

```bash
python scripts/learner_cli.py submit
```

## Web UI

```bash
streamlit run scripts/web_ui/app.py
```

Affiche :

- le profil (`profile.yaml`) sous forme de JSON et graphiques,
- le `brief.md` du sprint sélectionné,
- les ressources de la stack,
- l'historique du chat.

## Test rapide de V0

```bash
python scripts/learner_cli.py init
python scripts/learner_cli.py start --sprint 1
python scripts/learner_cli.py test --step 1
```

Par défaut `test` retourne `FAIL` car les scripts contiennent des `TODO`. Remplace `EXPECTED="TODO"` par une valeur, par exemple `EXPECTED="ok"`, et relance `test --step 1` pour obtenir `PASS`.
