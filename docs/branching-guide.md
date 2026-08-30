# Utiliser les branches d'amélioration sans interférer avec le workflow de missions

## Conventions de nommage

Utiliser un préfixe explicite. Les branches `step/<stack>/...` sont réservées aux missions générées par le pipeline.

| Préfixe | Usage |
|---|---|
| `improve/<sujet>` | Amélioration du programme |
| `draft/<sujet>` | Brouillon |
| `experiment/<sujet>` | Test / preuve de concept |
| `refactor/<sujet>` | Nettoyage / factorisation |
| `chore/<sujet>` | Tâche technique mineure |
| `dev/<sujet>` | Documentation et guides internes |

Les branches `step/<stack>/...` sont gérées par `scripts/pipeline_orchestrator.py` (fonction `parse_branch_ref`) et doivent rester dédiées aux étapes pédagogiques.

## Branches déjà créées

- `improve/pipeline`
- `draft/workflow`
- `experiment/dashboard`
- `dev/branching-guide`

## Créer une nouvelle branche d'amélioration

```bash
git checkout main
git pull origin main
git branch <type>/<sujet>
git push origin <type>/<sujet>
```

## Cycle de travail

```bash
git checkout <type>/<sujet>
# Modifications dans scripts/, .github/ ou dashboard/
# Éviter de toucher à stacks/<stack>/**
git add ...
git commit -m "<message>"
git push origin <type>/<sujet>
```

## Déclenchements des GitHub Actions

| Action | Workflow(s) concerné(s) | Résultat |
|---|---|---|
| PR `improve/...` vers `main` modifiant `stacks/**` | `.github/workflows/reviews.yml` + `.github/workflows/ci.yml` | Review IA + validation CI |
| PR `improve/...` vers `main` en dehors de `stacks/**` | Aucun | Pas de review |
| Merge ou close d'une PR sur `main` | `.github/workflows/mission-generator.yml` | Génère la mission suivante ; échoue si la branche source ne respecte pas `step/<stack>/...` |
| Push sur `main` modifiant `stacks/**` | `.github/workflows/init.yml` + `.github/workflows/deploy-dashboard.yml` | Bootstrap / déploiement dashboard |
| Push sur `main` modifiant `dashboard/**` | `.github/workflows/deploy-dashboard.yml` | Redéploiement dashboard |
| Push sur `main` modifiant `scripts/` ou `.github/` | Aucun | Aucun workflow |

## Merger proprement une amélioration

La branche `main` n'est pas protégée. Pour intégrer une amélioration sans déclencher `mission-generator.yml`, il faut merger en local et pousser `main` :

```bash
git checkout main
git pull origin main
git merge --no-ff <type>/<sujet>
git push origin main
```

Si une PR a été ouverte sur GitHub, la fermer **sans merge** puis merger en local permet d'éviter le déclenchement de `mission-generator.yml`.

## Commandes utiles

```bash
# Lister les branches d'amélioration
git branch --list "improve/*" "draft/*" "experiment/*" "refactor/*" "dev/*"

# Supprimer une branche locale et distante
git branch -d <type>/<sujet>
git push origin --delete <type>/<sujet>

# Ouvrir une PR de relecture humaine (ne pas merger via l'UI GitHub)
gh pr create --base main --head <type>/<sujet>
```

## Règles de base

- Modifier `stacks/<stack>/**` uniquement sur une branche `step/<stack>/...`.
- Ne pas merger une branche `improve/...`, `draft/...` ou `experiment/...` via l'UI GitHub : cela déclencherait `mission-generator.yml`.
- Conserver les améliorations du programme (`scripts/`, `.github/`, `dashboard/`) séparées des contenus pédagogiques (`stacks/`).
