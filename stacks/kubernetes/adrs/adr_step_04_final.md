# ADR 004 : Probes et observabilité applicative

## Statut
Accepté

## Contexte
Le déploiement Nginx existant ne disposait d'aucune sonde de santé. En cas de blocage du processus Nginx (processus vivant mais incapable de servir), Kubernetes continuait d'envoyer du trafic vers un pod mort, provoquant des erreurs 502 pour les utilisateurs. De plus, aucune métrique n'était collectée pour détecter une dégradation avant qu'elle n'impacte les utilisateurs.

## Décision
Nous avons ajouté deux sondes HTTP au conteneur Nginx :
- **readinessProbe** sur `/hello` : vérifie que Nginx est capable de servir des requêtes.
- **livenessProbe** sur `/health` : détecte un état de blocage irrécupérable.

Les deux endpoints sont configurés dans la ConfigMap Nginx pour dépendre de la présence du fichier `index.html`. Si ce fichier est supprimé, les deux endpoints retournent une erreur, ce qui permet de simuler une panne.

Les valeurs temporelles des sondes sont définies comme suit :
- `initialDelaySeconds: 5`
- `periodSeconds: 10`
- `timeoutSeconds: 2`
- `failureThreshold: 3`
- `successThreshold: 1`

Ces réglages sont volontairement conservateurs pour éviter des redémarrages intempestifs.

Nous avons également déployé Prometheus et Grafana dans le namespace `tools` pour collecter et visualiser les métriques des pods Nginx.

## Conséquences
- Les pods incapables de servir sont automatiquement retirés du Service grâce à la readinessProbe.
- Les pods bloqués sont redémarrés automatiquement grâce à la livenessProbe.
- Les métriques sont disponibles dans Prometheus et visualisables dans Grafana.

## Alternatives envisagées
- **Utiliser des commandes exec** : plus complexes à maintenir et moins fiables que des sondes HTTP.
- **Utiliser Datadog ou New Relic** : nécessiterait des licences supplémentaires et une configuration plus lourde.
- **Ne pas ajouter de sondes** : risquerait de reproduire le scénario d'incident décrit dans la mission.

## Risques résiduels
- Le dashboard Grafana n'est pas encore provisionné automatiquement (à faire dans une étape ultérieure).
