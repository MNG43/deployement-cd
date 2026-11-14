// CD SamaFile : tire les images Docker Hub et bascule le backend en blue-green.
// Job : Pipeline script from SCM sur le dépôt deployment-cd.
// Credentials :
//   dockerhub-credentials, samafile-postgres-password,
//   samafile-secret-key, samafile-admin-password

pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    parameters {
        string(name: 'BACKEND_TAG', defaultValue: 'latest', description: 'Tag Docker Hub du backend')
        string(name: 'FRONTEND_TAG', defaultValue: 'latest', description: 'Tag Docker Hub du frontend')
        booleanParam(name: 'ROLLBACK', defaultValue: false, description: 'Revenir à la couleur précédente')
    }

    environment {
        REQUIRE_PULL = '1'
    }

    stages {
        stage('Connexion et environnement') {
            steps {
                withCredentials([
                    usernamePassword(credentialsId: 'dockerhub-credentials', usernameVariable: 'DOCKERHUB_USER', passwordVariable: 'DOCKERHUB_TOKEN'),
                    string(credentialsId: 'samafile-postgres-password', variable: 'POSTGRES_PASSWORD'),
                    string(credentialsId: 'samafile-secret-key', variable: 'SECRET_KEY'),
                    string(credentialsId: 'samafile-admin-password', variable: 'ADMIN_PASSWORD')
                ]) {
                    sh '''
                        set -eu
                        umask 077
                        echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USER" --password-stdin
                        cat > .env <<EOF
DOCKERHUB_USER=${DOCKERHUB_USER}
BACKEND_TAG=${BACKEND_TAG}
FRONTEND_TAG=${FRONTEND_TAG}
APP_PORT=8888
POSTGRES_USER=samafile
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=samafile
APP_ENV=development
SECRET_KEY=${SECRET_KEY}
CORS_ORIGINS=http://localhost:8888,http://127.0.0.1:8888
ADMIN_EMAIL=admin@samafile.local
ADMIN_PASSWORD=${ADMIN_PASSWORD}
ADMIN_NAME=Administrateur SamaFile
SEED_DEMO_ACCOUNTS=true
DEMO_PASSWORD=Demo12345
ACCESS_TOKEN_MINUTES=480
EOF
                    '''
                }
            }
        }

        stage('Déploiement blue-green') {
            steps {
                script {
                    if (isUnix()) {
                        sh '''
                            set -eu
                            if [ "$ROLLBACK" = "true" ]; then
                                bash scripts/blue-green-deploy.sh rollback
                            else
                                bash scripts/blue-green-deploy.sh deploy
                            fi
                        '''
                    } else {
                        powershell """
                            if ("${params.ROLLBACK}" == "true") {
                                .\\scripts\\blue-green-deploy.ps1 -Action rollback
                            } else {
                                .\\scripts\\blue-green-deploy.ps1 -Action deploy
                            }
                        """
                    }
                }
            }
        }
    }

    post {
        always {
            sh '''
                rm -f .env || true
                docker logout || true
            '''
        }
    }
}
