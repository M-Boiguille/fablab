# Mission : Implémenter la V0 du simulateur d'apprentissage DevOps

## Contexte
Tu travailles sur un monorepo existant (voir `specs.md` en pièce jointe). Ce repo contient déjà :
- Un workflow GitHub Actions (PR, CI, génération de missions).
- Un orchestrateur Python (`pipeline_orchestrator.py`).
- Un client LLM avec fallback (`gemini_client.py`).
- Une structure de dossiers pour les stacks.

**Tu ne dois PAS toucher aux workflows GitHub Actions existants** (sauf ajout mineur documenté). Le but est d'ajouter une couche *locale* (CLI + Web UI) qui se superpose à l'existant sans le casser.

## Scope : UNIQUEMENT V0
La V0 a pour objectif : **"Patch & Feedback immédiat"**.
Tu dois implémenter les livrables suivants UNIQUEMENT :

### 1. Fichier `profile.yaml`
- Créer ce fichier à la racine de chaque stack (ex: `stacks/kubernetes/profile.yaml`).
- Structure minimale :
  ```yaml
  version: 1
  last_updated: <date>
  global:
    overall_level: 0.2
    current_sprint: 1
  skills:
    kubernetes:
      pods: { level: 0.5, confidence: 0.5, last_used: null, error_patterns: [] }
      deployments: { level: 0.3, confidence: 0.3, last_used: null, error_patterns: [] }
    terraform:
      state_management: { level: 0.1, confidence: 0.2, last_used: null, error_patterns: [] }
    python:
      scripting: { level: 0.2, confidence: 0.3, last_used: null, error_patterns: [] }
  ```
- **Règle** : Ne pas inventer 50 compétences. Seulement celles de la "Golden Stack" (K8s, Terraform, Python, Réseau, Linux, SoftSkills).

### 2. CLI `scripts/learner_cli.py`
Ce script doit exposer ces commandes :

- `learner_cli.py init` → Génère `profile.yaml` avec les valeurs par défaut.
- `learner_cli.py start --sprint 1` → Lit `profile.yaml` et génère le dossier `sprints/sprint_01/` avec les fichiers suivants :
  - `brief.md` (le contexte métier généré par l'IA via `gemini_client.py`).
  - `step_01/`, `step_02/`, `step_03/` (pour les 3 étapes du sprint).
  - Dans chaque dossier : un script `step_XX_validation.sh` **pré-rempli** à 80 %, avec des `# TODO: <action>` aux endroits clés.
- `learner_cli.py test --step X` → Exécute `sprints/sprint_XX/step_XX/step_XX_validation.sh` et affiche le résultat en < 2 secondes.
- `learner_cli.py chat` → Ouvre un chat terminal avec l'IA (utilise `gemini_client.py`), charge en contexte `profile.yaml` et les ressources (`book_toc.md`, `kodekloud_modules.md`). **Ne stocke pas l'historique dans le repo** (un fichier `.chat_history.json` local à la racine du projet est autorisé).
- `learner_cli.py submit` → Vérifie que tous les scripts du sprint passent, génère un `result.txt` global, commit et push sur une nouvelle branche, et ouvre une PR.

### 3. Interface Web `scripts/web_ui/app.py`
- Utiliser **Streamlit** (pas Flask, pas Django). Une seule page.
- Fonctions :
  - Lecture et affichage de `profile.yaml` sous forme de tableau/radar.
  - Affichage formaté des fichiers `brief.md` et des ressources `book_toc.md`.
  - Affichage de l'historique du chat (lecture du `.chat_history.json` local).
- **Contrainte** : L'UI doit se lancer via `streamlit run scripts/web_ui/app.py`. Pas de Docker, pas de conteneur.

## Règles strictes (NO-GO)
- **Interdiction d'ajouter une base de données** (SQLite, Postgres, etc.). Tout est en YAML/JSON.
- **Interdiction d'ajouter Docker** pour l'UI ou le CLI. On reste en Python 3.11 natif.
- **Interdiction de toucher aux workflows `.github/`** sauf si c'est absolument nécessaire pour `submit` ; dans ce cas, documente-le.
- **Interdiction de réécrire `pipeline_orchestrator.py`**. Tu peux l'*importer* et l'utiliser, mais pas le refactoriser en profondeur.
- **Interdiction d'implémenter le Chaos Engineering, l'interleaving, le simulateur de recrutement, ou le blog.** Ce sont des versions futures.

## Critères d'acceptation (DO-DONE)
- [ ] Après `init`, je vois `profile.yaml` dans ma stack.
- [ ] Après `start --sprint 1`, je vois un dossier `sprints/` avec 3 sous-dossiers contenant chacun un script `.sh` avec des `# TODO`.
- [ ] Je peux modifier le script, lancer `test --step 1`, et voir un résultat `PASS` ou `FAIL` en < 3 secondes.
- [ ] Je peux lancer `chat`, poser une question sur un concept, et obtenir une réponse contextualisée par mon profil.
- [ ] Je peux lancer `streamlit run app.py` et voir un tableau de bord qui lit mon `profile.yaml`.
- [ ] La PR générée par `submit` ne contient que les fichiers nécessaires (scripts, ADR, result.txt) et déclenche bien la CI existante.

## Livraison
- Fournis le code modifié/ajouté.
- Fournis un `README_V0.md` résumant les nouvelles commandes et comment les tester.
- **Avant d'écrire le code, décris-moi en 5 points comment tu comptes t'y prendre.** J'attends ce plan d'attaque pour valider l'approche.

## Dernière consigne
*"Si tu as un doute entre deux implémentations, choisis la plus simple, la plus courte, la plus rapide à exécuter. Je préfère 80 % de valeur avec 20 % de code plutôt que 100 % de sophistication avec 500 % de maintenance."*
```
