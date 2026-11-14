// À coller une seule fois dans Jenkins : Manage Jenkins > Script Console.
// Remplacer chaque REMPLACER, exécuter, puis effacer ce script de la console.
// Préférer l'écran Credentials si l'équipe n'utilise pas la console.

import com.cloudbees.plugins.credentials.CredentialsScope
import com.cloudbees.plugins.credentials.SystemCredentialsProvider
import com.cloudbees.plugins.credentials.domains.Domain
import com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl
import hudson.util.Secret
import jenkins.model.Jenkins
import org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl

def dockerUser = 'REMPLACER_UTILISATEUR_DOCKERHUB'
def dockerToken = 'REMPLACER_JETON_DOCKERHUB'
def dbPassword = 'REMPLACER_MOT_DE_PASSE_POSTGRES'
def secretKey = 'REMPLACER_SECRET_KEY_32_CARACTERES_MIN'
def adminPassword = 'REMPLACER_MOT_DE_PASSE_ADMIN'

def valeurs = [dockerUser, dockerToken, dbPassword, secretKey, adminPassword]
if (valeurs.any { it.startsWith('REMPLACER') }) {
    error('Remplacez toutes les valeurs REMPLACER avant d exécuter ce script.')
}

def store = SystemCredentialsProvider.instance.store
def deja = com.cloudbees.plugins.credentials.CredentialsProvider.lookupCredentials(
    com.cloudbees.plugins.credentials.common.IdCredentials.class,
    Jenkins.instance,
    null,
    null
)*.id as Set

def ajouter(credential) {
    if (deja.contains(credential.id)) {
        println("Déjà présent : ${credential.id}")
        return
    }
    store.addCredentials(Domain.global(), credential)
    println("Créé : ${credential.id}")
}

ajouter(new UsernamePasswordCredentialsImpl(
    CredentialsScope.GLOBAL,
    'dockerhub-credentials',
    'Docker Hub - publication des images SamaFile',
    dockerUser,
    dockerToken
))

ajouter(new StringCredentialsImpl(
    CredentialsScope.GLOBAL,
    'samafile-postgres-password',
    'Mot de passe PostgreSQL SamaFile',
    Secret.fromString(dbPassword)
))

ajouter(new StringCredentialsImpl(
    CredentialsScope.GLOBAL,
    'samafile-secret-key',
    'SECRET_KEY JWT SamaFile',
    Secret.fromString(secretKey)
))

ajouter(new StringCredentialsImpl(
    CredentialsScope.GLOBAL,
    'samafile-admin-password',
    'Mot de passe du premier administrateur SamaFile',
    Secret.fromString(adminPassword)
))
