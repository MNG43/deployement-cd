# Déploiement continu de SamaFile

La documentation complète d'installation, des pipelines Jenkins, des credentials, des scans et du
déploiement local est dans le [Guide DevOps](../README_DEVOPS.md).

Ce dossier contient :

- `Jenkinsfile` : pipeline CD avec sélection des tags Docker Hub et option de rollback.
- `docker-compose.yml` : services de production, PostgreSQL persistant et proxy Nginx.
- `docker-compose.build.yml` : surcharge pour construire les images depuis les dossiers voisins.
- `jenkins/` : configuration du serveur Jenkins et modèle de création des credentials.
- `scripts/` : scripts de bascule blue-green pour Linux/macOS et Windows.

Avant un déploiement, consulter impérativement la section « Avertissement avant une vraie
production » du guide DevOps et remplacer les valeurs d'exemple.
