# SamaFile - déploiement continu

Ce dépôt déploie les images publiées du frontend et du backend avec Docker Compose. Nginx sert de proxy d’entrée ; deux services backend (`blue` et `green`) permettent une bascule contrôlée. PostgreSQL conserve les données dans un volume Docker.

| Élément               | Valeur                                                                         |
| ----------------------- | ------------------------------------------------------------------------------ |
| Dépôt                   | [MNG43/deployment-cd](https://github.com/MNG43/deployment-cd)                   |
| Port local              | `8888` (configurable avec `APP_PORT`)                                      |
| Interface               | `http://localhost:8888`                                                      |
| Santé API via le proxy | `http://localhost:8888/health`                                               |
| Documentation OpenAPI   | `http://localhost:8888/docs`                                                 |
| Image backend           | [mng2021/samafile-backend](https://hub.docker.com/r/mng2021/samafile-backend)   |
| Image frontend          | [mng2021/samafile-frontend](https://hub.docker.com/r/mng2021/samafile-frontend) |

## Prérequis

- Docker avec Docker Compose v2.
- Jenkins avec un agent Linux capable d’exécuter Docker et Docker Compose.
- Pour le déploiement distant, un accès Docker Hub et des tags d’images déjà publiés.
- Pour la compilation locale, les dépôts `backend-ci` et `frontend-ci` placés à côté de `deployment-cd`.

## Configuration

Copiez le modèle et renseignez des valeurs propres à votre environnement :

```powershell
Copy-Item .env.example .env
```

Les variables principales sont :

- `DOCKERHUB_USER`, `BACKEND_TAG`, `FRONTEND_TAG` : compte et tags à déployer.
- `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` : accès PostgreSQL.
- `SECRET_KEY`, `ADMIN_EMAIL`, `ADMIN_PASSWORD` : configuration applicative.
- `APP_PORT` : port HTTP publié par le proxy.
- `CORS_ORIGINS`, `SEED_DEMO_ACCOUNTS`, `DEMO_PASSWORD` : configuration API et données de démonstration.

Ne commitez jamais `.env`. Remplacez tous les mots de passe et secrets d’exemple avant tout usage partagé ou de production. Le `.env.example` est uniquement un modèle local.

## Lancer en local depuis les sources

Depuis ce dossier, la surcharge `docker-compose.build.yml` construit les images à partir des dossiers voisins. Le profil `blue` active le backend bleu :

```powershell
docker compose --env-file .env -f docker-compose.yml -f docker-compose.build.yml --profile blue up -d --build
docker compose --env-file .env -f docker-compose.yml -f docker-compose.build.yml --profile blue ps
```

Ouvrez `http://localhost:8888`, puis vérifiez `http://localhost:8888/health`. Pour suivre les journaux :

```powershell
docker compose --env-file .env -f docker-compose.yml -f docker-compose.build.yml --profile blue logs -f
```

La stack comprend PostgreSQL, le backend actif, le frontend et le proxy Nginx. Le point d’entrée public est le proxy ; le backend n’expose pas directement son port sur l’hôte.

## Déploiement par Jenkins

Créez le job `samafile-cd` de type **Pipeline**, avec **Pipeline script from SCM**. Configurez
le dépôt Git du déploiement, la branche `main` et le chemin de script `Jenkinsfile`.

Le pipeline comporte deux étapes principales :

1. **Connexion et environnement** : connexion à Docker Hub, validation des tags et création
   temporaire du fichier `.env` à partir des credentials Jenkins.
2. **Déploiement blue-green** : exécution du script `deploy` ou `rollback`.

Après l’exécution, le pipeline supprime `.env` et ferme la session Docker Hub.

Paramètres du job :

- `BACKEND_TAG` : tag publié du backend (valeur utilisée dans les exécutions : `16`).
- `FRONTEND_TAG` : tag publié du frontend (valeur utilisée dans les exécutions : `10`).
- `ROLLBACK` : cocher pour revenir à la couleur précédente au lieu de déployer une nouvelle version.

Credentials Jenkins attendus (IDs seulement) :

- `dockerhub-credentials` : nom d’utilisateur et jeton Docker Hub.
- `samafile-postgres-password` : mot de passe PostgreSQL.
- `samafile-secret-key` : clé de signature JWT.
- `samafile-admin-password` : mot de passe administrateur initial.

Vérifiez sur Docker Hub que les tags choisis existent avant de lancer le job. Les dépôts d’images sont [`samafile-backend`](https://hub.docker.com/r/mng2021/samafile-backend) et [`samafile-frontend`](https://hub.docker.com/r/mng2021/samafile-frontend).

### Démonstrations Jenkins

Le polling SCM du job CD surveille les commits du dépôt de déploiement sur `main`; il ne se
déclenche pas simplement parce qu’un job CI a publié une nouvelle image. Pour l’activer,
configurez **Configurer > Triggers > Scrutation de l’outil de gestion de version** avec
`H/2 * * * *`. Un commit surveillé peut lancer un vrai déploiement : gardez les tags par défaut
valides ou lancez le job manuellement avec les tags voulus.

Dans le job `samafile-cd`, utilisez **Build with Parameters** et choisissez des tags présents
sur Docker Hub. Les valeurs par défaut actuelles sont backend `16` et frontend `10`. Le pipeline
vérifie l'existence des tags avant le déploiement; si `latest` est demandé mais absent, il revient
aux tags `16` et `10`.

- **Déploiement normal** : laissez `ROLLBACK` décoché, lancez le build et attendez **SUCCESS**.
- **Rollback** : gardez des tags valides renseignés, cochez `ROLLBACK` et lancez le build. Le
  script réactive l'ancien conteneur de l'autre couleur; il ne télécharge pas une nouvelle image.
  Le rollback nécessite que ce conteneur existe déjà. Après le test, relancez un déploiement
  normal avec `ROLLBACK` décoché pour laisser l'application sur la version souhaitée.

Dans la console Jenkins, vérifiez le retour vers `backend-blue` ou `backend-green`, l'état
`healthy` et le message `Contrôle proxy et API OK : /health`. Le test HTTP attendu est :

```powershell
Invoke-WebRequest -UseBasicParsing http://localhost:8888/health
```

Enregistrez la capture du rollback sous `15-rollback.png`.

Pour démontrer la persistance des tickets :

1. Sur `http://localhost:8888/usager`, créez un ticket et notez son numéro.
2. Capturez le ticket avant déploiement sous `12-ticket-avant.png`.
3. Relancez `samafile-cd` avec les mêmes tags, `ROLLBACK` décoché, et attendez **SUCCESS**.
4. Recherchez le même numéro dans **Suivre mon ticket**, puis capturez-le sous
   `13-ticket-apres.png`.

Compose conserve les données dans le volume PostgreSQL monté sur
`/var/lib/postgresql/data`. Pour voir son nom Docker effectif, inspectez le conteneur et listez
les volumes correspondants :

```powershell
docker inspect samafile-db --format '{{json .Mounts}}'
docker volume ls --filter name=pgdata
```

Ne lancez pas `docker compose down -v` et ne supprimez pas le volume pendant ces démonstrations.

## Bascule blue-green et rollback

Le script choisit la couleur inactive, démarre ou recrée le backend correspondant, attend son état `healthy`, bascule l’upstream Nginx, vérifie le proxy et `/health`, puis arrête l’ancienne couleur. Dans Jenkins, `ROLLBACK` réactive la couleur précédente, vérifie sa santé, rebascule le proxy et exécute le contrôle de fumée.

Scripts disponibles :

```powershell
.\scriptslue-green-deploy.ps1 -Action deploy
.\scriptslue-green-deploy.ps1 -Action rollback
```

Les scripts locaux nécessitent un `.env` valide, Docker Compose et les conteneurs de la stack. N’effectuez pas une deuxième opération CD simultanément ; Jenkins désactive les builds concurrents.

## PostgreSQL et persistance

Compose monte le volume `samafile_pgdata` dans `/var/lib/postgresql/data`. Une mise à jour ou un rollback garde ce volume. Pour vérifier le volume :

```powershell
docker inspect samafile-db --format '{{json .Mounts}}'
docker volume ls --filter name=pgdata
```

Ne lancez pas `docker compose down -v` : l’option `-v` supprime le volume et les données PostgreSQL. Une preuve de persistance nécessite de retrouver le même ticket après un déploiement ; la présence du volume seule ne démontre pas ce scénario.

## Vérifications utiles

```powershell
docker compose --env-file .env -f docker-compose.yml --profile blue --profile green config --quiet
docker compose --env-file .env -f docker-compose.yml --profile blue --profile green ps
Invoke-RestMethod http://localhost:8888/health
Invoke-WebRequest -UseBasicParsing http://localhost:8888/docs
```

Le contrôle `/health` doit retourner un état `ok`. Pendant une démonstration de continuité, lancez la boucle de vérification dans une autre fenêtre pendant le déploiement ; ne concluez à l’absence d’interruption que si elle ne renvoie aucune erreur.

## Fichiers principaux

- `docker-compose.yml` : PostgreSQL, backends blue/green, frontend et proxy.
- `docker-compose.build.yml` : surcharge de compilation locale depuis les dépôts voisins.
- `Jenkinsfile` : sélection des tags, credentials, déploiement ou rollback.
- `scripts/blue-green-deploy.ps1` et `scripts/blue-green-deploy.sh` : scripts Windows et Linux/macOS.
- `nginx/` : proxy HTTP et configuration de la couleur backend active.
- `jenkins/` : image et configuration de l’instance Jenkins locale.
