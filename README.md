# Cloudflare ZTNA Manager

**Toolkit complet pour la gestion des tunnels Cloudflare et l'implémentation Zero Trust Network Access (ZTNA)**

[![Version](https://img.shields.io/badge/version-2.0-blue.svg)](https://github.com)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux-lightgrey.svg)](https://github.com)

---

## Table des matières

- [Apercu](#apercu)
- [Fonctionnalites](#fonctionnalites)
- [Prerequis](#prerequis)
- [Installation rapide](#installation-rapide)
- [Structure du projet](#structure-du-projet)
- [Guide d'utilisation](#guide-dutilisation)
  - [Script principal (cloudflare-manager.sh)](#script-principal-cloudflare-managersh)
  - [Installation rapide (setup-cloudflared.sh)](#installation-rapide-setup-cloudflaredsh)
  - [Gestion quotidienne (cloudflared-manage.sh)](#gestion-quotidienne-cloudflared-managesh)
  - [Certificats SSL Origin (setup-origin-cert.sh)](#certificats-ssl-origin-setup-origin-certsh)
- [Architecture](#architecture)
- [Configuration Cloudflare](#configuration-cloudflare)
- [Exemples d'utilisation](#exemples-dutilisation)
- [Depannage](#depannage)
- [Securite](#securite)
- [Contribution](#contribution)

---

## Apercu

Ce toolkit permet de deployer et gerer des **Cloudflare Tunnels** pour exposer de maniere securisee des applications internes sur Internet, sans ouvrir de ports sur votre pare-feu.

### Qu'est-ce qu'un Cloudflare Tunnel ?

Un tunnel Cloudflare etablit une connexion **sortante chiffree** entre votre serveur et le reseau edge de Cloudflare. Cela permet :

- **Zero exposition** : Aucun port entrant a ouvrir sur le pare-feu
- **Chiffrement de bout en bout** : TLS entre vos utilisateurs et vos applications
- **Protection DDoS** : Beneficiez de la protection Cloudflare
- **Zero Trust** : Authentification et autorisation centralisees

```
Internet                    Cloudflare Edge                    Votre Serveur
   |                              |                                  |
   |  HTTPS (utilisateur)         |                                  |
   | ---------------------------> |                                  |
   |                              |    Tunnel chiffre (sortant)      |
   |                              | <------------------------------- |
   |                              |                                  |
   |                              |        app.domain.com            |
   |                              | -------> http://10.10.1.25:8080  |
```

---

## Fonctionnalites

### Gestion des tunnels
- Installation automatique de `cloudflared`
- Creation et configuration de tunnels
- Gestion multi-applications par tunnel
- Support des protocoles : HTTP, HTTPS, SSH, RDP, TCP

### Certificats SSL
- Generation de certificats Cloudflare Origin CA
- Validite jusqu'a 15 ans
- Configuration automatique pour Nginx

### Zero Trust Network Access (ZTNA)
- Restriction par IP via WAF
- Integration Cloudflare Access
- Authentification par email/SSO

### Outils d'administration
- Interface interactive avec menus
- Mode ligne de commande pour automatisation
- Diagnostics et validation de configuration
- Gestion du service systemd

---

## Prerequis

### Systeme
- Linux (Debian/Ubuntu recommande)
- Acces root/sudo
- Architecture : x86_64, arm64 ou armv7l

### Dependances
Les scripts installent automatiquement les dependances manquantes :
- `curl` - Requetes HTTP
- `jq` - Parsing JSON
- `openssl` - Operations certificats

### Compte Cloudflare
- Compte Cloudflare actif
- Domaine configure dans Cloudflare DNS
- API Token avec les permissions suivantes :
  - Zone > DNS > Edit
  - Zone > SSL and Certificates > Edit
  - Account > Cloudflare Tunnel > Edit
  - Account > Access: Apps and Policies > Edit (optionnel)

---

## Installation rapide

### Option 1 : Installation complete interactive

```bash
# Cloner le repository
git clone https://github.com/your-repo/cloudflare-ztna.git
cd cloudflare-ztna

# Lancer le manager interactif
sudo ./cloudflare-manager.sh
```

### Option 2 : Installation rapide d'un tunnel

```bash
cd cloudflare-toolkit

# Mode interactif
sudo ./setup-cloudflared.sh

# Ou avec parametres
sudo ./setup-cloudflared.sh \
  -n mon-tunnel \
  -d app.mondomaine.com \
  -i 10.10.1.25 \
  -p 8080 \
  --auto-start
```

---

## Structure du projet

```
cloudflare-ztna/
|
|-- cloudflare-manager.sh          # Script principal interactif
|
|-- cloudflare-toolkit/
|   |-- setup-cloudflared.sh       # Installation rapide d'un tunnel
|   |-- setup-origin-cert.sh       # Generation certificats Origin
|   |-- cloudflared-manage.sh      # Gestion quotidienne
|
|-- README.md                      # Ce fichier
|-- DOCUMENTATION.md               # Documentation complete
```

### Fichiers de configuration generes

| Chemin | Description |
|--------|-------------|
| `/etc/cloudflared/config.yml` | Configuration du tunnel |
| `/etc/cloudflared/<tunnel-id>.json` | Credentials du tunnel |
| `/etc/cloudflared/.cf_config` | Credentials API Cloudflare |
| `/etc/cloudflared/.service_name` | Nom du service systemd |
| `/etc/cloudflare-certs/` | Certificats Origin CA |
| `/etc/systemd/system/cloudflared-*.service` | Service systemd |
| `/root/.cloudflared/cert.pem` | Certificat d'authentification |

---

## Guide d'utilisation

### Script principal (cloudflare-manager.sh)

Interface interactive complete pour toutes les operations.

```bash
sudo ./cloudflare-manager.sh
```

#### Menu principal

```
  1) Installation & Configuration Initiale
  2) Gestion des Applications
  3) Configuration SSL (Certificats Origin)
  4) Configuration ZTNA (Zero Trust)
  5) Gestion du Service
  6) Informations & Diagnostics
  7) Desinstallation
  0) Quitter
```

#### Sous-menu Installation

1. **Installer cloudflared** - Telecharge et installe le binaire
2. **Configurer les credentials** - Configure API Token, Zone ID, Account ID
3. **Creer un nouveau tunnel** - Authentification + creation tunnel
4. **Installation complete** - Tout-en-un automatise
5. **Mettre a jour cloudflared** - Mise a jour du binaire

#### Sous-menu Applications

- Ajouter des applications WEB (HTTP/HTTPS)
- Ajouter des acces SSH
- Ajouter des acces RDP
- Ajouter des services TCP (MySQL, PostgreSQL, Redis...)
- Supprimer des applications
- Editer la configuration manuellement

---

### Installation rapide (setup-cloudflared.sh)

Script autonome pour deployer rapidement un tunnel avec une application.

#### Mode interactif

```bash
cd cloudflare-toolkit
sudo ./setup-cloudflared.sh
```

Le script vous guidera a travers :
1. Nom du tunnel
2. Domaine public
3. IP de l'application
4. Port
5. Protocole (http/https)

#### Mode parametres

```bash
sudo ./setup-cloudflared.sh [options]

Options:
  -n, --name <nom>         Nom du tunnel
  -d, --domain <domaine>   Domaine public
  -i, --ip <ip>            IP locale de l'application
  -p, --port <port>        Port de l'application
  -s, --protocol <proto>   http ou https (defaut: http)
  -y, --yes                Mode non-interactif
  --auto-start             Demarrer automatiquement
  -h, --help               Aide
```

#### Exemples

```bash
# Application web HTTP
sudo ./setup-cloudflared.sh -n hdl-prod -d app.hdl.tg -i 10.10.1.25 -p 8080

# Application HTTPS avec demarrage auto
sudo ./setup-cloudflared.sh -n hdl-secure -d secure.hdl.tg -i 10.10.1.25 -p 443 -s https --auto-start

# Mode completement automatise
sudo ./setup-cloudflared.sh -n hdl-test -d test.hdl.tg -i localhost -p 3000 -y --auto-start
```

---

### Gestion quotidienne (cloudflared-manage.sh)

Utilitaire en ligne de commande pour les operations courantes.

```bash
cd cloudflare-toolkit
sudo ./cloudflared-manage.sh <commande>
```

#### Commandes disponibles

**Gestion du service :**
```bash
./cloudflared-manage.sh start      # Demarrer
./cloudflared-manage.sh stop       # Arreter
./cloudflared-manage.sh restart    # Redemarrer
./cloudflared-manage.sh enable     # Activer au demarrage
./cloudflared-manage.sh disable    # Desactiver au demarrage
./cloudflared-manage.sh status     # Statut
./cloudflared-manage.sh logs       # Logs en temps reel
./cloudflared-manage.sh test       # Mode test (foreground)
```

**Gestion des tunnels :**
```bash
./cloudflared-manage.sh list       # Lister les tunnels
./cloudflared-manage.sh info       # Informations detaillees
./cloudflared-manage.sh config     # Afficher la configuration
./cloudflared-manage.sh validate   # Valider la configuration
```

**Gestion des applications :**
```bash
# Ajouter une application web
./cloudflared-manage.sh add-app api.hdl.tg 10.10.1.24 8080

# Ajouter avec protocole specifique
./cloudflared-manage.sh add-app secure.hdl.tg 10.10.1.24 443 https

# Ajouter un acces SSH
./cloudflared-manage.sh add-ssh dev-ssh.hdl.tg 10.10.1.25
./cloudflared-manage.sh add-ssh prod-ssh.hdl.tg 10.10.1.24 22

# Supprimer une application
./cloudflared-manage.sh remove-app api.hdl.tg

# Lister les applications
./cloudflared-manage.sh list-apps
```

#### Auto-detection du protocole

Le script detecte automatiquement le protocole selon le port :

| Port | Protocole |
|------|-----------|
| 22 | ssh |
| 443, 8443 | https |
| 3389 | rdp |
| 3306, 5432, 6379, 27017 | tcp |
| Autres | http |

---

### Certificats SSL Origin (setup-origin-cert.sh)

Genere des certificats Cloudflare Origin CA pour securiser les communications internes.

#### Mode interactif

```bash
cd cloudflare-toolkit
sudo ./setup-origin-cert.sh
```

#### Mode parametres

```bash
sudo ./setup-origin-cert.sh [options]

Options:
  -t, --token <token>      API Token Cloudflare
  -z, --zone <zone_id>     Zone ID du domaine
  -d, --domain <domain>    Domaine principal
  -h, --hostnames <hosts>  Hostnames couverts (ex: "*.hdl.tg,hdl.tg")
  -o, --output <dir>       Dossier de sortie
  -v, --validity <days>    Validite en jours (defaut: 5475 = 15 ans)
  -k, --key-type <type>    Type de cle: rsa ou ecdsa
```

#### Fichiers generes

```
/etc/cloudflare-certs/
|-- hdl.tg.pem                    # Certificat
|-- hdl.tg.key                    # Cle privee
|-- hdl.tg.fullchain.pem          # Certificat + CA
|-- cloudflare-origin-ca.pem      # CA Root Cloudflare
|-- nginx-example.conf            # Exemple Nginx
```

#### Utilisation avec Nginx

```nginx
server {
    listen 443 ssl http2;
    server_name app.hdl.tg;

    ssl_certificate     /etc/cloudflare-certs/hdl.tg.pem;
    ssl_certificate_key /etc/cloudflare-certs/hdl.tg.key;

    # Configuration SSL recommandee
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers off;

    location / {
        proxy_pass http://127.0.0.1:8069;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

---

## Architecture

### Schema de fonctionnement

```
                           INTERNET
                              |
                              v
                    +-------------------+
                    |   Cloudflare      |
                    |   Edge Network    |
                    |                   |
                    |  - DNS            |
                    |  - DDoS Protection|
                    |  - WAF            |
                    |  - Access (ZTNA)  |
                    +-------------------+
                              |
                    Tunnel chiffre (sortant uniquement)
                              |
                              v
              +-------------------------------+
              |       Votre Serveur Linux     |
              |                               |
              |   cloudflared (systemd)       |
              |         |                     |
              |    config.yml                 |
              |         |                     |
              |   +-----+-----+-----+         |
              |   |     |     |     |         |
              |   v     v     v     v         |
              | App1  App2  SSH   MySQL       |
              | :8080 :443  :22   :3306       |
              +-------------------------------+
```

### Flux de trafic

1. **Utilisateur** accede a `https://app.hdl.tg`
2. **Cloudflare DNS** resout vers le tunnel
3. **Cloudflare Edge** applique les regles de securite (WAF, Access)
4. **Tunnel** achemine le trafic vers `cloudflared` sur votre serveur
5. **cloudflared** route vers le service local selon `config.yml`
6. **Reponse** remonte par le meme chemin

### Format du fichier config.yml

```yaml
tunnel: <tunnel-uuid>
credentials-file: /etc/cloudflared/<tunnel-uuid>.json

ingress:
  # Application web
  - hostname: app.hdl.tg
    service: http://10.10.1.25:8080
    originRequest:
      connectTimeout: 30s

  # Application HTTPS (backend SSL)
  - hostname: secure.hdl.tg
    service: https://10.10.1.25:443
    originRequest:
      connectTimeout: 30s
      noTLSVerify: true

  # Acces SSH
  - hostname: ssh.hdl.tg
    service: ssh://10.10.1.25:22

  # Service TCP
  - hostname: mysql.hdl.tg
    service: tcp://10.10.1.25:3306

  # Catch-all obligatoire
  - service: http_status:404
```

---

## Configuration Cloudflare

### Obtenir un API Token

1. Connectez-vous au [Dashboard Cloudflare](https://dash.cloudflare.com)
2. Allez dans **My Profile** > **API Tokens**
3. Cliquez **Create Token**
4. Selectionnez **Create Custom Token**
5. Configurez les permissions :

| Permission | Acces |
|------------|-------|
| Zone > DNS | Edit |
| Zone > SSL and Certificates | Edit |
| Account > Cloudflare Tunnel | Edit |
| Account > Access: Apps and Policies | Edit |

6. Zone Resources : **Include > Specific Zone > votre-domaine.com**
7. Creez et copiez le token

### Obtenir Zone ID et Account ID

1. Dashboard Cloudflare > votre domaine
2. Dans la colonne de droite, section **API** :
   - **Zone ID** : Identifiant de la zone
   - **Account ID** : Identifiant du compte

---

## Exemples d'utilisation

### Cas 1 : Exposer une application web interne

```bash
# Installation complete
sudo ./cloudflare-manager.sh
# Menu 1 > Option 4 (Installation complete)

# Ajouter l'application
# Menu 2 > Option 2 (Ajouter une application WEB)
# Domaine: app.mondomaine.com
# IP: 10.10.1.25
# Port: 8080
# Protocole: HTTP
```

### Cas 2 : Acces SSH securise

```bash
sudo ./cloudflare-toolkit/cloudflared-manage.sh add-ssh serveur-ssh.hdl.tg 10.10.1.25

# Configuration client (~/.ssh/config)
Host serveur
    HostName serveur-ssh.hdl.tg
    User admin
    ProxyCommand cloudflared access ssh --hostname %h
```

### Cas 3 : Base de donnees avec restriction IP

```bash
# Ajouter le service MySQL
sudo ./cloudflare-toolkit/cloudflared-manage.sh add-app mysql.hdl.tg 10.10.1.25 3306 tcp

# Configurer la restriction IP via le manager
sudo ./cloudflare-manager.sh
# Menu 4 > Option 1 (Configurer une restriction par IP)
```

### Cas 4 : Multi-applications sur un seul tunnel

```bash
# Ajouter plusieurs applications
sudo ./cloudflared-manage.sh add-app app1.hdl.tg 10.10.1.25 8080
sudo ./cloudflared-manage.sh add-app app2.hdl.tg 10.10.1.26 3000
sudo ./cloudflared-manage.sh add-app api.hdl.tg 10.10.1.27 9000 https

# Redemarrer pour appliquer
sudo ./cloudflared-manage.sh restart
```

---

## Depannage

### Le tunnel ne demarre pas

```bash
# Verifier les logs
sudo journalctl -u cloudflared-<nom> -n 50

# Valider la configuration
sudo cloudflared tunnel --config /etc/cloudflared/config.yml ingress validate

# Tester en mode foreground
sudo cloudflared tunnel --config /etc/cloudflared/config.yml run
```

### Erreur d'authentification API

```bash
# Tester la connexion API
curl -s -X GET "https://api.cloudflare.com/client/v4/zones/<ZONE_ID>" \
  -H "Authorization: Bearer <API_TOKEN>" \
  -H "Content-Type: application/json"
```

### Application inaccessible

1. **Verifier que l'application est accessible localement** :
   ```bash
   curl http://10.10.1.25:8080
   ```

2. **Verifier le statut du tunnel** :
   ```bash
   sudo ./cloudflared-manage.sh status
   ```

3. **Verifier la configuration DNS** :
   ```bash
   dig app.hdl.tg
   # Doit pointer vers <tunnel-id>.cfargotunnel.com
   ```

### Reinitialiser completement

```bash
sudo ./cloudflare-manager.sh
# Menu 7 > Option 2 (Desinstallation complete)
```

---

## Securite

### Bonnes pratiques

1. **Protegez votre API Token** - Ne le commitez jamais dans git
2. **Utilisez des certificats Origin** - Pour chiffrer le trafic interne
3. **Activez Cloudflare Access** - Pour authentifier les utilisateurs
4. **Configurez des restrictions IP** - Via les regles WAF
5. **Surveillez les logs** - `journalctl -u cloudflared-* -f`

### Permissions des fichiers

```bash
# Verifier les permissions
ls -la /etc/cloudflared/
# config.yml        : 644 (lecture pour tous)
# *.json            : 600 (lecture root uniquement)
# .cf_config        : 600 (contient l'API token)

ls -la /etc/cloudflare-certs/
# *.pem             : 644
# *.key             : 600 (cle privee)
```

---

## Contribution

Les contributions sont les bienvenues ! Pour contribuer :

1. Forkez le repository
2. Creez une branche (`git checkout -b feature/amelioration`)
3. Commitez vos changements (`git commit -am 'Ajout fonctionnalite'`)
4. Poussez la branche (`git push origin feature/amelioration`)
5. Ouvrez une Pull Request

---

## Licence

Ce projet est sous licence MIT. Voir le fichier [LICENSE](LICENSE) pour plus de details.

---

## Auteurs

**CNSS/HDL - Togo**

---

## Liens utiles

- [Documentation Cloudflare Tunnels](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Cloudflare Zero Trust](https://developers.cloudflare.com/cloudflare-one/)
- [API Cloudflare](https://api.cloudflare.com/)
- [Releases cloudflared](https://github.com/cloudflare/cloudflared/releases)
