# Stack kubernetes

## Objectif
Parcours pédagogique sur Kubernetes.

## Prérequis
- kubectl installé en local
- Accès à un environnement d'évaluation local
- Python 3 et `requests` uniquement pour l'orchestrateur

## Structure
- `roadmap.yaml` : étapes du parcours
- `CONTEXT_STATE.yaml` : état courant
- `test_strategy.yaml` : stratégie de validation et de preuve
- `resources/` : matériel de lecture
- `infra/manifests/` : manifests/configs kubectl
- `infra/adrs/` : décisions d'architecture
- `tests/` : scripts de validation
- `retrospectives/` : rétrospectives par étape

## Démarrage
1. Consulter `roadmap.yaml`.
2. Suivre `CONTEXT_STATE.yaml` pour savoir où en est le parcours.
3. Lire l'étape en cours et créer `tests/step_XX_validation.sh`.
4. Rédiger l'ADR dans `infra/adrs/`.
5. Implémenter les manifests/configs.
6. Exécuter le script localement et remplir `tests/step_XX_result.txt`.

## Format attendu pour `tests/step_XX_result.txt`

```text
PASS
--- Validation output ---
<output brut de la commande kubectl>
--- Summary ---
<Votre synthèse de ce qui a été validé et les points de vigilance>
```

La section `--- Summary ---` est obligatoire : c'est l'attestation légère que l'IA et le reviewer utiliseront.
