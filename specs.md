## 1. Workflow Complet (Diagramme Textuel)

```
[INIT] Fork du repo template → init_stack.sh <stack> <outil> <tooling> <nb_etapes>
        → Remplir book_toc.md, kodekloud_modules.md et roadmap.yaml → Push → GH Action génère la première mission

[BOUCLE POUR CHAQUE ÉTAPE]
│
├── 1. [AUTO] GH Action détecte le merge sur main → Lit CONTEXT_STATE.yaml + test_strategy.yaml
│       → Génère la rétrospective de l'étape terminée
│       → Met à jour CONTEXT_STATE.yaml (step+1)
│       → Déclenche la génération de la mission (appel API Gemini - rôle PO)
│       → Crée une branche step/<stack>/XX-nom
│       → Ouvre une PR avec la mission (chapitres à lire + commande de validation locale)
│
├── 2. [UTILISATEUR] Lit les chapitres indiqués + ressources
│       → Crée le script de validation tests/step_XX_validation.sh
│       → Rédige l'ADR (stacks/<stack>/infra/adrs/adr_step_XX_v1.md)
│       → Push sur la branche step/<stack>/XX-nom → La PR se met à jour
│
├── 3. [UTILISATEUR] Itération avec l'Architecte IA (via commentaire sur la PR) :
│       │   → L'utilisateur poste son ADR en commentaire
│       │   → Un script appelle Gemini (rôle Architecte) qui répond avec des questions sur les trade-offs
│       │   → Itérations jusqu'à validation (l'IA répond "ADR APPROVED")
│       └── L'ADR final est commité en tant que stacks/<stack>/infra/adrs/adr_step_XX_final.md
│
├── 4. [UTILISATEUR] Implémentation des artefacts → Lancement du script de test LOCAL :
│       │   → ./tests/step_XX_validation.sh
│       │   → Le script génère tests/step_XX_result.txt au format : PASS + output + --- Summary ---
│       └── Push du résultat sur la branche
│
├── 5. [AUTO] GH Action déclenchée sur la PR → Vérifie les artefacts via test_strategy.yaml :
│       │   ├── Fichiers requis présents (ADR final, validation.sh, result.txt)
│       │   ├── tests/step_XX_result.txt commence par PASS, FAIL ou PENDING
│       │   └── Présence de la section --- Summary --- (attestation légère)
│       └── Si échec → La PR est bloquée (statut "Checks failed")
│
├── 6. [UTILISATEUR] Appel à Gemini (rôle Lead SRE Review) sur les artefacts finaux :
│       │   → L'IA lit le result.txt et les artefacts, puis commente avec des niveaux Critique / Amelioration / Recommandation
│       │   → L'utilisateur corrige si nécessaire (retour à l'étape 4)
│       └── L'IA répond "LGTM" → La PR est prête (le merge reste humain)
│
├── 7. [UTILISATEUR] Merge manuel de la PR sur main
│
├── 8. [AUTO] GH Action déclenchée par le merge (retour à l'étape 1) :
│       │   ├── Génère retrospectives/retro_step_XX.md
│       │   ├── Met à jour CONTEXT_STATE.yaml (step+1)
│       │   ├── Rebuild du dashboard (GH Pages)
│       │   └── Création de la branche step/<stack>/XX+1-nom avec la nouvelle mission
│
└── [FIN] Toutes les étapes validées → Dashboard affiche 100% + badge "ready"
```

---

## 2. Structure Complète du Monorepo

```text
/learning-platform/
├── .github/
│   └── workflows/
│       ├── ci.yml                 # Validation des PRs (tests statiques, lecture result.txt)
│       ├── deploy-dashboard.yml   # Build + déploiement sur GH Pages
│       └── mission-generator.yml  # Déclenché sur merge → génère la prochaine mission
│
├── stacks/
│   └── kubernetes/                # <-- Exemple de stack
│       ├── README.md              # Prérequis et commandes spécifiques à l'outil
│       ├── roadmap.yaml           # Les étapes (titres explicites)
│       ├── CONTEXT_STATE.yaml     # État courant (step, capsule, décisions, risques)
│       ├── test_strategy.yaml     # Stratégie de validation (fichiers requis, commande, attestation)
│       ├── resources/
│       │   ├── book_toc.md        # Table des matières du livre
│       │   └── kodekloud_modules.md # Liste des modules de cours
│       ├── prompts/
│       │   ├── system_po.txt
│       │   ├── system_architect.txt
│       │   ├── system_lead_sre_review.txt
│       │   ├── system_lead_sre_debug.txt
│       │   ├── system_retrospective.txt
│       │   └── system_state_updater.txt
│       ├── infra/
│       │   ├── manifests/         # YAMLs organisés par étape
│       │   └── adrs/              # ADR v1, v2, ... final
│       ├── tests/
│       │   ├── step_XX_validation.sh
│       │   └── step_XX_result.txt # Généré localement (PASS/FAIL + logs)
│       ├── retrospectives/
│       │   └── retro_step_XX.md
│       └── README.md              # Spécifique à la stack
│
├── dashboard/                     # Code source du dashboard Jira-like
│   ├── index.html
│   ├── style.css
│   └── script.js                  # Lit les fichiers roadmap.yaml + CONTEXT_STATE.yaml
│
├── scripts/
│   ├── pipeline_orchestrator.py   # Orchestrateur principal (appels Gemini, gestion des branches)
│   ├── gemini_client.py           # Wrapper pour l'API Gemini (avec fallback DeepSeek)
│   └── init_stack.sh              # Générateur de nouvelle stack (copie template + édition roadmap)
│
├── templates/                     # Templates pour les nouvelles stacks
│   └── stack_template/
│       ├── README.md
│       ├── roadmap.yaml
│       ├── CONTEXT_STATE.yaml
│       ├── resources/
│       │   ├── book_toc.md
│       │   └── kodekloud_modules.md
│       ├── prompts/
│       │   └── *.txt
│       ├── infra/
│       │   ├── manifests/
│       │   └── adrs/
│       │       └── adr_template.md
│       └── tests/
│
├── README.md                      # Guide global du projet
└── LICENSE
```

---

## 3. Contenu des Fichiers Clés

### 3.1. `stacks/kubernetes/roadmap.yaml`

```yaml
name: "Kubernetes - Parcours Architecte"
stack: "kubernetes"
total_steps: 15
steps:
  - step: 1
    title: "Isolation des environnements (Namespaces, RBAC de base)"
    description: "Créer 3 namespaces (dev, staging, prod) avec des rôles différenciés pour les équipes."
  - step: 2
    title: "Déploiement d'une app stateful (Pods, Services, PVC pour PostgreSQL)"
    description: "Déployer PostgreSQL avec un volume persistant, et une API qui s'y connecte."
  - step: 3
    title: "Cycle de vie et mises à jour (RollingUpdate, Rollback, Probes)"
    description: "Mettre en place des rolling updates avec readiness/liveness probes, et tester un rollback."
  - step: 4
    title: "Exposition sécurisée (Ingress Controller, TLS/HTTPS)"
    description: "Installer un contrôleur Ingress (NGINX) et exposer l'API avec TLS."
  - step: 5
    title: "Gouvernance des ressources (Requests, Limits, ResourceQuotas)"
    description: "Définir des requests/limits par conteneur et des ResourceQuotas par namespace."
  - step: 6
    title: "Ordonnancement avancé (Taints, Tolerations, Node Affinity)"
    description: "Utiliser taints/tolerations et node affinity pour contrôler le placement des pods."
  - step: 7
    title: "Observabilité - Métriques (Prometheus, Grafana, AlertManager)"
    description: "Installer la stack Prometheus/Grafana et configurer des alertes."
  - step: 8
    title: "Observabilité - Logs (EFK Stack)"
    description: "Déployer Elasticsearch, Fluentd, Kibana pour la centralisation des logs."
  - step: 9
    title: "Sécurité des pods (SecurityContext, PodSecurityStandards)"
    description: "Appliquer des SecurityContext et les Pod Security Standards (restricted)."
  - step: 10
    title: "Sécurité réseau (NetworkPolicies - Zero Trust)"
    description: "Mettre en place des NetworkPolicies pour isoler le trafic entre pods."
  - step: 11
    title: "Stockage avancé et StatefulSets (pour les bases de données)"
    description: "Migrer PostgreSQL vers un StatefulSet avec des volumes persistants nommés."
  - step: 12
    title: "Gestion des secrets (External Secrets Operator / Vault intégration)"
    description: "Intégrer External Secrets Operator avec un gestionnaire de secrets (Vault ou AWS Secrets Manager)."
  - step: 13
    title: "Sauvegarde et reprise après sinistre (Velero, snapshots etcd)"
    description: "Installer Velero, configurer des sauvegardes planifiées et tester une restauration."
  - step: 14
    title: "GitOps et déploiement continu (ArgoCD / Flux)"
    description: "Mettre en place ArgoCD avec un dépôt Git comme source de vérité."
  - step: 15
    title: "Trafic avancé et résilience (Service Mesh / Gateway API)"
    description: "Explorer Service Mesh (Istio/Linkerd) ou Gateway API pour le trafic avancé."
```

### 3.2. `stacks/kubernetes/resources/book_toc.md`

(Contenu exact du fichier `Kubernetes.txt` fourni par l'utilisateur, structuré en markdown)

### 3.3. `stacks/kubernetes/resources/kodekloud_modules.md`

(Contenu extrait du fichier `Learn.txt` fourni par l'utilisateur, avec les noms de modules et sections pertinentes)

**Exemple d'extrait formaté** :

```markdown
# KodeKloud - Modules pour le parcours CKA

## Core Concepts (42 leçons)
- Cluster Architecture
- etcd pour débutants
- Kube API Server, Controller Manager, Scheduler
- Pods, ReplicaSets, Deployments
- Services (ClusterIP, LoadBalancer)
- Namespaces
- Imperative vs Declarative

## Scheduling (38 leçons)
- Manual Scheduling
- Labels and Selectors
- Taints and Tolerations
- Node Affinity
- Resource Requirements
- DaemonSets
- Static Pods
- Priority Classes
- Admission Controllers

## Application Lifecycle Management (34 leçons)
- Rolling Updates and Rollbacks
- Commands and Arguments
- ConfigMaps, Secrets
- Multi-Container Pods
- Autoscaling (HPA, VPA)

## Cluster Maintenance (15 leçons)
- OS Upgrades
- Cluster Upgrade
- Backup and Restore (etcd)

## Security (44 leçons)
- Authentication, TLS, KubeConfig
- RBAC (Roles, ClusterRoles, ServiceAccounts)
- Security Contexts
- Network Policies
- Image Security

## Storage (14 leçons)
- Volumes, Persistent Volumes, PVC
- Storage Classes
- CSI

## Networking (35 leçons)
- CNI, Pod Networking, Service Networking
- CoreDNS
- Ingress
- Gateway API

## Design and Install (5 leçons)
- Designing a Kubernetes Cluster
- High Availability
- etcd in HA

## Install with kubeadm (6 leçons)
- Deployment with kubeadm

## Troubleshooting (12 leçons)
- Application, Control Plane, Worker Node failures
- Network Troubleshooting

## Mock Exams (11 leçons)
- 3 Mock Exams avec solutions détaillées
```

### 3.4. `stacks/kubernetes/CONTEXT_STATE.yaml` (exemple initial)

```yaml
current_step: 0
total_steps: 15
stack: "kubernetes"
status: "not_started"  # not_started | in_progress | completed
context_capsule: "Aucune étape réalisée pour l'instant."
key_decisions: []
pending_risks: []
last_updated: "2026-08-28T10:00:00Z"
```

### 3.5. `templates/stack_template/infra/adrs/adr_template.md`

```markdown
# ADR - Étape {XX} : {titre de l'étape}

## Contexte
Décris le problème ou le besoin que cette étape doit résoudre.

## Décision
Décision prise (quoi et pourquoi).

## Alternatives considérées
- Alternative A : pour et contre.
- Alternative B : pour et contre.

## Trade-offs
Quels compromis acceptés ? Quels risques pris ?

## Références
- Chapitres / modules étudiés.
- Manifests associés.
```

### 3.6. `templates/stack_template/README.md`

```markdown
# Stack {STACK_NAME}

## Objectif
Parcours pédagogique sur {TOOLING_NAME}.

## Prérequis
- {TOOL} installé en local
- Accès à un environnement d'évaluation local
- Python 3 et `requests` uniquement pour l'orchestrateur

## Structure
- `roadmap.yaml` : étapes du parcours
- `CONTEXT_STATE.yaml` : état courant
- `test_strategy.yaml` : stratégie de validation et de preuve
- `resources/` : matériel de lecture
- `infra/manifests/` : manifests/configs {TOOL}
- `infra/adrs/` : décisions d'architecture
- `tests/` : scripts de validation
- `retrospectives/` : rétrospectives par étape

## Démarrage
1. Consulter `roadmap.yaml`.
2. Suivre `CONTEXT_STATE.yaml` pour savoir où en est le parcours.
3. Lire l'étape en cours et créer `tests/step_XX_validation.sh`.
4. Rédiger l'ADR dans `infra/adrs/`.
5. Implémenter les artefacts.
6. Exécuter le script localement et remplir `tests/step_XX_result.txt`.

## Format attendu pour `tests/step_XX_result.txt`

```text
PASS
--- Validation output ---
<output brut de la commande {TOOL}>
--- Summary ---
<Votre synthèse de ce qui a été validé et les points de vigilance>
```

La section `--- Summary ---` est obligatoire : c'est l'attestation légère que l'IA et le reviewer utiliseront.
```

### 3.7. `templates/stack_template/test_strategy.yaml`

```yaml
tool: "{TOOL}"
tooling_name: "{TOOLING_NAME}"
required_files:
  - "infra/adrs/adr_step_{step:02d}_final.md"
  - "tests/step_{step:02d}_validation.sh"
  - "tests/step_{step:02d}_result.txt"
pass_markers:
  - "PASS"
suggested_command: "tests/step_{step:02d}_validation.sh"
validation_output: "tests/step_{step:02d}_result.txt"
# Vérifications statiques optionnelles exécutées en CI
static_checks: []
```

---

## 4. Prompts Système pour les Rôles IA (Gemini / DeepSeek)

Chaque prompt est conçu pour être injecté dans le `system` de l'appel API. Les templates agnostiques, avec des placeholders `{tool}`, `{step}`, `{title}`, `{tooling_name}`, etc., sont dans `templates/stack_template/prompts/`. Ils sont copiés dans `stacks/<stack>/prompts/` lors de l'initialisation d'une stack.

| Fichier | Rôle | Quand est-il appelé |
| :--- | :--- | :--- |
| `system_po.txt` | Product Owner | Génération de la prochaine mission (`--action generate-mission`) |
| `system_architect.txt` | Architecte Solution | Review de l'ADR (`--action review-adr`) |
| `system_lead_sre_review.txt` | Lead SRE | Review finale de l'étape (`--action sre-review`) |
| `system_lead_sre_debug.txt` | Lead SRE Debug | Aide au débogage (appel manuel possible) |
| `system_retrospective.txt` | Facilitateur agile | Génération de la rétrospective (`generate-mission`) |
| `system_state_updater.txt` | State Updater | Mise à jour de `CONTEXT_STATE.yaml` (`generate-mission`) |

Les placeholders sont remplacés au moment de l'exécution par `pipeline_orchestrator.py::load_prompt()` en fonction de la stack, de l'étape et de l'outil.

---

## 5. Templates GitHub Actions

### 5.1. `.github/workflows/ci.yml` (Validation des PRs)

```yaml
name: CI - Validation des PRs

on:
  pull_request:
    branches: [main]
    paths:
      - 'stacks/**'

permissions:
  contents: read
  pull-requests: read

jobs:
  validate-static:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          pip install pyyaml requests

      - name: Check PR artifacts and attestation
        env:
          GITHUB_HEAD_REF: ${{ github.head_ref }}
        run: |
          python scripts/pipeline_orchestrator.py --action check-pr
```

### 5.2. `.github/workflows/mission-generator.yml` (Génération de mission)

```yaml
name: Generate Next Mission

on:
  pull_request:
    types: [closed]
    branches: [main]

permissions:
  contents: write
  pull-requests: write

jobs:
  generate-mission:
    if: github.event.pull_request.merged == true
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: main
          token: ${{ secrets.GITHUB_TOKEN }}
          fetch-depth: 0

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          pip install pyyaml requests

      - name: Generate next mission
        env:
          GEMINI_API_KEY: ${{ secrets.GEMINI_API_KEY }}
          DEEPSEEK_API_KEY: ${{ secrets.DEEPSEEK_API_KEY }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GITHUB_REPOSITORY: ${{ github.repository }}
          GITHUB_HEAD_REF: ${{ github.event.pull_request.head.ref }}
        run: |
          python scripts/pipeline_orchestrator.py --action generate-mission
```

### 5.3. `.github/workflows/deploy-dashboard.yml`

```yaml
name: Deploy Dashboard

on:
  push:
    branches: [main]
    paths:
      - 'dashboard/**'
      - 'stacks/**/roadmap.yaml'
      - 'stacks/**/CONTEXT_STATE.yaml'
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write
  pull-requests: read

concurrency:
  group: "pages"
  cancel-in-progress: false

jobs:
  build-and-deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          pip install pyyaml requests

      - name: Setup Pages
        uses: actions/configure-pages@v4

      - name: Build dashboard
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GITHUB_REPOSITORY: ${{ github.repository }}
        run: |
          # Copie des fichiers statiques
          mkdir -p _site
          cp -r dashboard/* _site/
          # Génération des données JSON pour le dashboard (inclut les PRs ouvertes)
          python scripts/pipeline_orchestrator.py --action build-dashboard-data --output _site/data.json

      - name: Upload Pages artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: _site

      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

### 5.4. `.github/workflows/init.yml` (Bootstrap)

```yaml
name: Bootstrap First Mission

on:
  push:
    branches: [main]
    paths:
      - 'stacks/**'
  workflow_dispatch:

permissions:
  contents: write
  pull-requests: write

jobs:
  bootstrap:
    if: github.event_name == 'workflow_dispatch' || github.event.before == '0000000000000000000000000000000000000000'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          fetch-depth: 0

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          pip install pyyaml requests

      - name: Generate first missions
        env:
          GEMINI_API_KEY: ${{ secrets.GEMINI_API_KEY }}
          DEEPSEEK_API_KEY: ${{ secrets.DEEPSEEK_API_KEY }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GITHUB_REPOSITORY: ${{ github.repository }}
        run: |
          python scripts/pipeline_orchestrator.py --action generate-mission
```

### 5.5. `.github/workflows/reviews.yml` (Reviews IA)

```yaml
name: AI Reviews

on:
  pull_request:
    types: [opened, synchronize]
    branches: [main]
    paths:
      - 'stacks/**'

permissions:
  contents: read
  pull-requests: write

jobs:
  review-adr:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          pip install pyyaml requests

      - name: ADR review
        env:
          GEMINI_API_KEY: ${{ secrets.GEMINI_API_KEY }}
          DEEPSEEK_API_KEY: ${{ secrets.DEEPSEEK_API_KEY }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GITHUB_REPOSITORY: ${{ github.repository }}
          GITHUB_HEAD_REF: ${{ github.head_ref }}
          PR_NUMBER: ${{ github.event.number }}
        run: |
          python scripts/pipeline_orchestrator.py --action review-adr

  sre-review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          pip install pyyaml requests

      - name: SRE review
        env:
          GEMINI_API_KEY: ${{ secrets.GEMINI_API_KEY }}
          DEEPSEEK_API_KEY: ${{ secrets.DEEPSEEK_API_KEY }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GITHUB_REPOSITORY: ${{ github.repository }}
          GITHUB_HEAD_REF: ${{ github.head_ref }}
          PR_NUMBER: ${{ github.event.number }}
        run: |
          python scripts/pipeline_orchestrator.py --action sre-review
```

---

## 6. Dashboard Jira-like (HTML/CSS/JS)

### 6.1. `dashboard/index.html`

```html
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Learning Platform</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <header>
        <h1>Learning Platform</h1>
        <nav>
            <select id="stack-selector">
                <option value="" disabled selected>Choisir une stack</option>
            </select>
            <span id="progress-badge">0%</span>
        </nav>
    </header>

    <main>
        <div class="board">
            <div class="column" id="todo">
                <h2>A faire</h2>
                <div class="card-list" id="todo-list"></div>
            </div>
            <div class="column" id="in-progress">
                <h2>En cours</h2>
                <div class="card-list" id="inprogress-list"></div>
            </div>
            <div class="column" id="review">
                <h2>En review</h2>
                <div class="card-list" id="review-list"></div>
            </div>
            <div class="column" id="done">
                <h2>Valide</h2>
                <div class="card-list" id="done-list"></div>
            </div>
        </div>
    </main>

    <div id="modal" class="modal">
        <div class="modal-content">
            <span class="close">&times;</span>
            <div id="modal-body"></div>
        </div>
    </div>

    <script src="script.js"></script>
</body>
</html>
```

### 6.2. `dashboard/style.css`

```css
/* Reset & Base */
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f4f5f7; color: #172b4d; }

/* Header */
header { background: #fff; padding: 16px 24px; display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #dfe1e6; }
header h1 { font-size: 20px; font-weight: 600; }
nav { display: flex; align-items: center; gap: 16px; }
#stack-selector { padding: 8px 12px; border-radius: 4px; border: 1px solid #dfe1e6; background: #fff; font-size: 14px; }
#progress-badge { background: #0052cc; color: #fff; padding: 4px 12px; border-radius: 12px; font-size: 14px; font-weight: 500; }

/* Board */
.board { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; padding: 24px; max-width: 1400px; margin: 0 auto; }
.column { background: #ebecf0; border-radius: 8px; padding: 12px; min-height: 400px; }
.column h2 { font-size: 14px; font-weight: 600; text-transform: uppercase; color: #5e6c84; margin-bottom: 12px; letter-spacing: 0.5px; }

/* Cards */
.card { background: #fff; border-radius: 4px; padding: 12px; margin-bottom: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.12); cursor: pointer; transition: box-shadow 0.2s; border-left: 4px solid #0052cc; }
.card:hover { box-shadow: 0 2px 6px rgba(0,0,0,0.16); }
.card .step-number { font-size: 12px; font-weight: 600; color: #5e6c84; }
.card .step-title { font-size: 14px; font-weight: 500; margin: 4px 0; }
.card .step-status { font-size: 12px; color: #5e6c84; }
.card.done { border-left-color: #36b37e; }
.card.in-progress { border-left-color: #ffab00; }
.card.review { border-left-color: #6554c0; }

/* Modal */
.modal { display: none; position: fixed; z-index: 1000; left: 0; top: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.5); overflow: auto; }
.modal-content { background: #fff; margin: 5% auto; padding: 24px; width: 80%; max-width: 900px; border-radius: 8px; max-height: 80vh; overflow-y: auto; }
.close { float: right; font-size: 28px; font-weight: bold; cursor: pointer; color: #5e6c84; }
.close:hover { color: #172b4d; }

/* Responsive */
@media (max-width: 768px) {
    .board { grid-template-columns: 1fr; }
}
```

### 6.3. `dashboard/script.js`

```javascript
let data = {};
let currentStack = '';

async function loadData() {
    try {
        const response = await fetch('data.json');
        data = await response.json();
        populateStackSelector();
    } catch (e) {
        console.error('Erreur de chargement des donnees', e);
    }
}

function populateStackSelector() {
    const selector = document.getElementById('stack-selector');
    selector.innerHTML = '<option value="" disabled selected>Choisir une stack</option>';
    const stacks = Object.keys(data.stacks || {});
    stacks.forEach(name => {
        const option = document.createElement('option');
        option.value = name;
        option.textContent = name;
        selector.appendChild(option);
    });

    if (stacks.length > 0) {
        currentStack = stacks[0];
        selector.value = currentStack;
        document.title = `Learning Platform - ${currentStack}`;
        renderBoard();
        updateProgress();
    }
}

function renderBoard() {
    const stackData = data.stacks?.[currentStack];
    if (!stackData) return;

    const steps = stackData.roadmap?.steps || [];
    const state = stackData.state || {};
    const currentStep = state.current_step || 0;
    const status = state.status || 'not_started';

    ['todo', 'inprogress', 'review', 'done'].forEach(id => {
        document.getElementById(id + '-list').innerHTML = '';
    });

    steps.forEach((step) => {
        const stepNum = step.step;
        const card = document.createElement('div');
        card.className = 'card';
        card.dataset.step = stepNum;

        let column = 'todo';
        if (status === 'completed' || stepNum < currentStep) {
            column = 'done';
        } else if (stepNum === currentStep) {
            column = 'in-progress';
        }

        card.classList.add(column === 'done' ? 'done' : column === 'in-progress' ? 'in-progress' : column === 'review' ? 'review' : '');

        card.innerHTML = `
            <div class="step-number">Etape ${stepNum}</div>
            <div class="step-title">${step.title}</div>
            <div class="step-status">${step.description?.substring(0, 60) || ''}...</div>
        `;

        card.addEventListener('click', () => openModal(stepNum));
        document.getElementById(column + '-list').appendChild(card);
    });
}

function updateProgress() {
    const stackData = data.stacks?.[currentStack];
    if (!stackData) return;

    const total = stackData.roadmap?.total_steps || 1;
    const current = stackData.state?.current_step || 0;
    const status = stackData.state?.status || 'not_started';

    let pct = 0;
    if (status === 'completed') {
        pct = 100;
    } else {
        pct = Math.round((current / total) * 100);
    }
    document.getElementById('progress-badge').textContent = pct + '%';
}

function openModal(stepNum) {
    const stackData = data.stacks?.[currentStack];
    if (!stackData) return;

    const step = stackData.roadmap?.steps?.find(s => s.step === stepNum);
    if (!step) return;

    const state = stackData.state || {};
    const modal = document.getElementById('modal');
    const body = document.getElementById('modal-body');

    body.innerHTML = `
        <h2>Etape ${stepNum} : ${step.title}</h2>
        <p><strong>Description :</strong> ${step.description || ''}</p>
        <hr>
        <h3>Contexte</h3>
        <p>${state.context_capsule || 'Aucune capsule de contexte disponible.'}</p>
        <h3>Decisions cles</h3>
        <ul>${(state.key_decisions || []).map(d => `<li>${d}</li>`).join('') || '<li>Aucune</li>'}</ul>
        <h3>Risques en attente</h3>
        <ul>${(state.pending_risks || []).map(r => `<li>${r}</li>`).join('') || '<li>Aucun</li>'}</ul>
    `;

    modal.style.display = 'block';
}

document.querySelector('.close').addEventListener('click', () => {
    document.getElementById('modal').style.display = 'none';
});
window.addEventListener('click', (e) => {
    if (e.target === document.getElementById('modal')) {
        document.getElementById('modal').style.display = 'none';
    }
});

document.getElementById('stack-selector').addEventListener('change', (e) => {
    currentStack = e.target.value;
    document.title = `Learning Platform - ${currentStack}`;
    renderBoard();
    updateProgress();
});

loadData();
```

---

## 7. Script d'Initialisation d'une Nouvelle Stack

### `scripts/init_stack.sh`

```bash
#!/bin/bash
# Usage: ./init_stack.sh <stack_name> [tool] [tooling_name] [total_steps]
# Exemples :
#   ./init_stack.sh kubernetes kubectl "Kubernetes" 15
#   ./init_stack.sh terraform terraform "Terraform" 10

set -e

STACK_NAME=$1
TOOL=${2:-kubernetes}
TOOLING_NAME=${3:-Kubernetes}
TOTAL_STEPS=${4:-15}

if [ -z "$STACK_NAME" ]; then
    echo "Usage: $0 <stack_name> [tool] [tooling_name] [total_steps]"
    exit 1
fi

if [ -d "stacks/$STACK_NAME" ]; then
    echo "La stack $STACK_NAME existe déjà."
    exit 1
fi

if [ ! -d "templates/stack_template" ]; then
    echo "Le template templates/stack_template est manquant."
    exit 1
fi

mkdir -p stacks
cp -r templates/stack_template "stacks/$STACK_NAME"

LAST_UPDATED=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

python3 << PY
from pathlib import Path

stack = "$STACK_NAME"
tool = "$TOOL"
tooling = "$TOOLING_NAME"
total_steps = "$TOTAL_STEPS"
last_updated = "$LAST_UPDATED"

root = Path("stacks") / stack
for p in root.rglob("*"):
    if p.is_file():
        text = p.read_text(encoding="utf-8")
        text = text.replace("{STACK_NAME}", stack)
        text = text.replace("{TOOL}", tool)
        text = text.replace("{TOOLING_NAME}", tooling)
        text = text.replace("{TOTAL_STEPS}", total_steps)
        text = text.replace("{LAST_UPDATED}", last_updated)
        p.write_text(text, encoding="utf-8")
PY

echo "Stack $STACK_NAME créée dans stacks/$STACK_NAME"
echo "Prochaines étapes :"
echo "   1. Remplir resources/book_toc.md et resources/kodekloud_modules.md"
echo "   2. Adapter roadmap.yaml et test_strategy.yaml"
echo "   3. Vérifier que prompts/ correspondent à ton outil"
```

---

## 8. Intégration de l'API Gemini avec Fallback DeepSeek

### `scripts/gemini_client.py`

```python
#!/usr/bin/env python3
import logging
import os
import time
from typing import List, Optional

import requests

logger = logging.getLogger(__name__)


class LLMClient:
    DEFAULT_GEMINI_URL = (
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent"
    )
    DEFAULT_DEEPSEEK_URL = "https://api.deepseek.com/v1/chat/completions"

    def __init__(
        self,
        gemini_key: Optional[str] = None,
        deepseek_key: Optional[str] = None,
        gemini_url: Optional[str] = None,
        deepseek_url: Optional[str] = None,
        max_retries: int = 3,
        backoff: int = 2,
    ):
        self.gemini_key = gemini_key or os.environ.get("GEMINI_API_KEY")
        self.deepseek_key = deepseek_key or os.environ.get("DEEPSEEK_API_KEY")
        self.gemini_url = gemini_url or self.DEFAULT_GEMINI_URL
        self.deepseek_url = deepseek_url or self.DEFAULT_DEEPSEEK_URL
        self.max_retries = max_retries
        self.backoff = backoff

        self.providers: List[str] = []
        if self.gemini_key:
            self.providers.append("gemini")
        if self.deepseek_key:
            self.providers.append("deepseek")
        if not self.providers:
            raise RuntimeError("Aucune clé LLM configurée. Définissez GEMINI_API_KEY ou DEEPSEEK_API_KEY.")

        self._provider_index = 0

    @property
    def _current_provider(self) -> str:
        return self.providers[self._provider_index]

    def _call_gemini(self, system_prompt: str, user_prompt: str) -> str:
        if not self.gemini_key:
            raise RuntimeError("Clé Gemini manquante")

        payload = {
            "systemInstruction": {"parts": [{"text": system_prompt}]},
            "contents": [{"role": "user", "parts": [{"text": user_prompt}]}],
            "generationConfig": {
                "temperature": 0.2,
                "maxOutputTokens": 2500,
            },
        }
        response = requests.post(
            f"{self.gemini_url}?key={self.gemini_key}",
            headers={"Content-Type": "application/json"},
            json=payload,
            timeout=60,
        )
        response.raise_for_status()

        data = response.json()
        candidates = data.get("candidates", [])
        if not candidates:
            raise RuntimeError("Réponse Gemini vide (aucun candidate)")

        parts = candidates[0].get("content", {}).get("parts", [{}])
        if not parts or "text" not in parts[0]:
            raise RuntimeError("Réponse Gemini mal formée")
        return parts[0]["text"]

    def _call_deepseek(self, system_prompt: str, user_prompt: str) -> str:
        if not self.deepseek_key:
            raise RuntimeError("Clé DeepSeek manquante")

        payload = {
            "model": "deepseek-chat",
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            "temperature": 0.2,
            "max_tokens": 2500,
        }
        response = requests.post(
            self.deepseek_url,
            json=payload,
            headers={
                "Authorization": f"Bearer {self.deepseek_key}",
                "Content-Type": "application/json",
            },
            timeout=60,
        )
        response.raise_for_status()

        choices = response.json().get("choices", [])
        if not choices:
            raise RuntimeError("Réponse DeepSeek vide")
        return choices[0]["message"]["content"]

    def chat(self, system_prompt: str, user_prompt: str) -> str:
        last_exception: Optional[Exception] = None

        for attempt in range(self.max_retries):
            try:
                if self._current_provider == "gemini":
                    return self._call_gemini(system_prompt, user_prompt)
                return self._call_deepseek(system_prompt, user_prompt)
            except (requests.RequestException, RuntimeError) as exc:
                last_exception = exc
                logger.warning(
                    "Tentative %s/%s échouée pour %s : %s",
                    attempt + 1,
                    self.max_retries,
                    self._current_provider,
                    exc,
                )

                # Bascule sur le fournisseur suivant s'il y en a plusieurs
                if len(self.providers) > 1:
                    self._provider_index = (self._provider_index + 1) % len(self.providers)

                if attempt < self.max_retries - 1:
                    time.sleep(self.backoff * (attempt + 1))

        raise last_exception or RuntimeError("Tous les fournisseurs LLM ont échoué")
```

---

## 9. Checklist pour Devin.ai (Synthèse des Tâches)

| Tâche | Fichier / Action |
| :--- | :--- |
| **1. Créer le repo** | Fork du template `learning-platform-template` → renommer |
| **2. Initialiser une stack** | Lancer `./scripts/init_stack.sh <stack> <outil> <tooling> <nb_etapes>` <br> Exemple : `./scripts/init_stack.sh kubernetes kubectl Kubernetes 15` |
| **3. Remplir les ressources** | `stacks/<stack>/resources/book_toc.md` <br> `stacks/<stack>/resources/kodekloud_modules.md` |
| **4. Adapter la stratégie** | Vérifier `stacks/<stack>/test_strategy.yaml` et `roadmap.yaml` |
| **5. Configurer les secrets GitHub** | `GEMINI_API_KEY`, `DEEPSEEK_API_KEY`, `GITHUB_TOKEN` |
| **6. Activer GitHub Pages** | Settings → Pages → Source : `gh-pages` branch |
| **7. Pousser le premier commit** | `git add . && git commit -m "feat: init learning platform" && git push` |
| **8. Vérifier la première mission** | GH Action `init.yml` doit créer une PR `step/<stack>/01-...` |
| **9. Lancer la boucle** | Suivre le workflow décrit en section 1 |

---

