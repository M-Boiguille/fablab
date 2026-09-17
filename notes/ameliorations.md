# Améliorations identifiées

## Mémoire et historique

- Mettre à jour les commentaires de review existants au lieu d’en créer un nouveau à chaque run.
- Utiliser la clé `review-key` pour retrouver et remplacer le commentaire correspondant.
- Sauvegarder chaque review dans les fichiers du dépôt, par exemple :
  - `stacks/<stack>/reviews/review_adr_step_XX.md`
  - `stacks/<stack>/reviews/review_sre_step_XX.md`
- Inclure les reviews archivées dans les prompts de rétrospective et de state updater.
- Ajouter un `memory.yaml` par stack pour stocker les décisions, risques et retours importants.

## Fiabilité des reviews

- Valider le format de sortie des reviews avant publication.
- Vérifier la présence des cinq sections obligatoires :
  1. Résumé
  2. Points forts
  3. Points bloquants
  4. Suggestions d’amélioration
  5. Conclusion
- Vérifier que la review se termine par `---`.
- En cas de format invalide, relancer le LLM ou signaler un échec.
- Éviter les doublons de commentaires sur une même PR.

## Workflows GitHub Actions

- Factoriser les étapes communes dans une action composite ou un workflow réutilisable.
- Ajouter un job `merge-readiness` qui analyse la section « Points bloquants » :
  - Si elle ne contient pas « Aucun », le job échoue et bloque la fusion.
- Déclencher les reviews aussi sur étiquette, par exemple `ready-for-review`.
- Passer `PR_NUMBER` au workflow de génération de mission pour récupérer les commentaires de la PR fermée.
- Récupérer les reviews depuis l’API GitHub avant de générer la rétrospective et la mission suivante.

## Traçabilité

- Versionner les reviews dans le dépôt.
- Ajouter un résumé des reviews dans `CONTEXT_STATE.yaml`.
- Conserver l’historique des valeurs de quotas/limites et des justifications associées.
