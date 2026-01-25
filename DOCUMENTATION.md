# Documentation Technique Complete

## Cloudflare ZTNA Manager - Version 2.0

**Repository GitHub** : [https://github.com/liksoft/cloudflare-ztna](https://github.com/liksoft/cloudflare-ztna)

---

## Table des matieres

1. [Introduction](#1-introduction)
2. [Architecture technique](#2-architecture-technique)
3. [Reference des scripts](#3-reference-des-scripts)
4. [Configuration detaillee](#4-configuration-detaillee)
5. [API Cloudflare](#5-api-cloudflare)
6. [Gestion des services](#6-gestion-des-services)
7. [Certificats SSL Origin](#7-certificats-ssl-origin)
8. [Zero Trust Network Access](#8-zero-trust-network-access)
9. [Split DNS et Intranet](#9-split-dns-et-intranet)
10. [Maintenance et operations](#10-maintenance-et-operations)
11. [Reference des erreurs](#11-reference-des-erreurs)
12. [Annexes](#12-annexes)

---

## 1. Introduction

### 1.1 Objectif du projet

Ce toolkit fournit une solution complete pour :
- Deployer des tunnels Cloudflare de maniere automatisee
- Gerer plusieurs applications via un seul tunnel
- Implementer Zero Trust Network Access (ZTNA)
- Generer et gerer des certificats SSL Origin
- Administrer le cycle de vie des tunnels

### 1.2 Public cible

- Administrateurs systeme Linux
- Equipes DevOps
- Ingenieurs securite
- Equipes infrastructure

### 1.3 Concepts cles

| Terme | Definition |
|-------|------------|
| **Cloudflare Tunnel** | Connexion sortante chiffree entre votre serveur et Cloudflare |
| **cloudflared** | Agent/daemon qui maintient le tunnel |
| **Ingress** | Regles de routage du trafic entrant vers les services locaux |
| **Origin Certificate** | Certificat SSL emis par Cloudflare pour securiser le backend |
| **ZTNA** | Zero Trust Network Access - Modele de securite sans confiance implicite |
| **WAF** | Web Application Firewall - Filtrage des requetes HTTP |

---

## 2. Architecture technique

### 2.1 Vue d'ensemble

```
+------------------------------------------------------------------+
|                         INTERNET                                  |
+------------------------------------------------------------------+
                              |
                              v
+------------------------------------------------------------------+
|                    CLOUDFLARE EDGE NETWORK                        |
|                                                                   |
|  +------------------+  +------------------+  +------------------+ |
|  |   Anycast DNS    |  |   DDoS Shield    |  |       WAF        | |
|  +------------------+  +------------------+  +------------------+ |
|                              |                                    |
|  +------------------+  +------------------+  +------------------+ |
|  |  Access (ZTNA)   |  | Tunnel Gateway   |  | SSL Termination  | |
|  +------------------+  +------------------+  +------------------+ |
|                              |                                    |
+------------------------------------------------------------------+
                              |
               Connexion sortante (HTTPS/QUIC)
               Ports 443, 7844 (aucun port entrant)
                              |
                              v
+------------------------------------------------------------------+
|                      SERVEUR LINUX                                |
|                                                                   |
|  +------------------------------------------------------------+  |
|  |                    cloudflared daemon                       |  |
|  |  - Maintient le tunnel actif                               |  |
|  |  - Route le trafic selon config.yml                        |  |
|  |  - Gere les reconnexions automatiques                      |  |
|  +------------------------------------------------------------+  |
|                              |                                    |
|         +--------------------+--------------------+               |
|         |                    |                    |               |
|         v                    v                    v               |
|  +------------+       +------------+       +------------+         |
|  |  App Web   |       |    SSH     |       |   MySQL    |         |
|  |  :8080     |       |    :22     |       |   :3306    |         |
|  +------------+       +------------+       +------------+         |
+------------------------------------------------------------------+
```

### 2.2 Flux de donnees

```
1. Requete utilisateur
   Client --> HTTPS --> Cloudflare Edge (app.domain.com)

2. Traitement Cloudflare
   Edge --> DNS Resolution --> Tunnel Lookup --> Access Check --> WAF

3. Acheminement tunnel
   Edge --> Tunnel Gateway --> cloudflared (votre serveur)

4. Routage local
   cloudflared --> config.yml lookup --> service local (http://10.10.1.25:8080)

5. Reponse
   Service local --> cloudflared --> Tunnel --> Edge --> Client
```

### 2.3 Composants du systeme

| Composant | Emplacement | Role |
|-----------|-------------|------|
| `cloudflared` | `/usr/local/bin/cloudflared` | Binaire du daemon |
| `config.yml` | `/etc/cloudflared/config.yml` | Configuration du tunnel |
| `<tunnel-id>.json` | `/etc/cloudflared/` | Credentials du tunnel |
| `cert.pem` | `/root/.cloudflared/` | Certificat d'authentification |
| Service systemd | `/etc/systemd/system/cloudflared-*.service` | Gestion du daemon |

### 2.4 Protocoles supportes

| Protocole | Port typique | Utilisation |
|-----------|--------------|-------------|
| HTTP | 80, 8080, 3000... | Applications web |
| HTTPS | 443, 8443 | Applications web securisees |
| SSH | 22 | Acces terminal distant |
| RDP | 3389 | Remote Desktop Windows |
| TCP | Tout port | Services TCP generiques (MySQL, PostgreSQL, Redis) |

---

## 3. Reference des scripts

### 3.1 cloudflare-manager.sh

**Description** : Script principal avec interface interactive.

**Emplacement** : `/cloudflare-manager.sh`

**Execution** :
```bash
sudo ./cloudflare-manager.sh
```

#### Structure des menus

```
MENU PRINCIPAL
|
|-- 1. Installation & Configuration
|   |-- 1. Installer cloudflared
|   |-- 2. Configurer les credentials API
|   |-- 3. Creer un nouveau tunnel
|   |-- 4. Installation complete (tout-en-un)
|   |-- 5. Mettre a jour cloudflared
|
|-- 2. Gestion des Applications
|   |-- 1. Lister les applications configurees
|   |-- 2. Ajouter une application WEB
|   |-- 3. Ajouter un acces SSH
|   |-- 4. Ajouter un acces RDP
|   |-- 5. Ajouter un service TCP
|   |-- 6. Supprimer une application
|   |-- 7. Editer la configuration
|
|-- 3. Configuration SSL
|   |-- 1. Generer un certificat Origin
|   |-- 2. Lister les certificats
|   |-- 3. Afficher les chemins
|   |-- 4. Generer config Nginx
|   |-- 5. Configurer Split DNS
|
|-- 4. Configuration ZTNA
|   |-- 1. Restriction par IP (WAF)
|   |-- 2. Creer une application Access
|   |-- 3. Gerer les politiques
|   |-- 4. Lister les regles WAF
|   |-- 5. Ajouter une IP autorisee
|   |-- 6. Supprimer une regle WAF
|
|-- 5. Gestion du Service
|   |-- 1. Demarrer
|   |-- 2. Arreter
|   |-- 3. Redemarrer
|   |-- 4. Activer au demarrage
|   |-- 5. Desactiver
|   |-- 6. Voir les logs
|   |-- 7. Status detaille
|
|-- 6. Diagnostics
|   |-- 1. Informations tunnel
|   |-- 2. Lister les tunnels
|   |-- 3. Afficher la configuration
|   |-- 4. Valider la configuration
|   |-- 5. Tester la connectivite
|   |-- 6. Informations systeme
|
|-- 7. Desinstallation
    |-- 1. Supprimer le tunnel
    |-- 2. Desinstallation complete
```

#### Fonctions principales

| Fonction | Description |
|----------|-------------|
| `install_cloudflared()` | Telecharge et installe le binaire cloudflared |
| `configure_credentials()` | Configure API Token, Zone ID, Account ID |
| `create_tunnel()` | Authentifie et cree un nouveau tunnel |
| `add_web_application()` | Ajoute une application HTTP/HTTPS |
| `add_ssh_application()` | Ajoute un acces SSH |
| `add_rdp_application()` | Ajoute un acces RDP |
| `add_tcp_application()` | Ajoute un service TCP |
| `generate_origin_cert()` | Genere un certificat Origin via API |
| `configure_ip_restriction()` | Configure une regle WAF de restriction IP |
| `full_uninstall()` | Supprime completement le toolkit |

---

### 3.2 setup-cloudflared.sh

**Description** : Script d'installation rapide pour deployer un tunnel avec une application.

**Emplacement** : `/cloudflare-toolkit/setup-cloudflared.sh`

#### Options de ligne de commande

| Option | Court | Description | Exemple |
|--------|-------|-------------|---------|
| `--name` | `-n` | Nom du tunnel | `-n hdl-prod` |
| `--domain` | `-d` | Domaine public | `-d app.hdl.tg` |
| `--ip` | `-i` | IP locale | `-i 10.10.1.25` |
| `--port` | `-p` | Port local | `-p 8080` |
| `--protocol` | `-s` | Protocole (http/https) | `-s https` |
| `--yes` | `-y` | Mode non-interactif | `-y` |
| `--auto-start` | | Demarrer apres installation | `--auto-start` |
| `--help` | `-h` | Afficher l'aide | `-h` |

#### Etapes d'installation

1. **Verification root** - S'assure des privileges administrateur
2. **Configuration interactive/parametres** - Collecte les informations
3. **Validation** - Verifie le format des parametres
4. **Test de connectivite** - Teste l'acces a l'application locale
5. **Installation cloudflared** - Telecharge le binaire
6. **Authentification** - Login Cloudflare via navigateur
7. **Creation tunnel** - Cree le tunnel dans Cloudflare
8. **Configuration DNS** - Ajoute l'enregistrement CNAME
9. **Creation config.yml** - Genere la configuration
10. **Creation service systemd** - Configure le service
11. **Demarrage** - Lance le tunnel

#### Fichier config.yml genere

```yaml
#===============================================================================
# Configuration Cloudflare Tunnel
# Genere le: <date>
# Script: setup-cloudflared.sh
#===============================================================================

tunnel: <tunnel-uuid>
credentials-file: /etc/cloudflared/<tunnel-uuid>.json

# Logging (debug, info, warn, error, fatal)
# loglevel: info

# Metriques Prometheus (decommenter pour activer)
# metrics: 0.0.0.0:2000

ingress:
  #-----------------------------------------------------------------------------
  # app.hdl.tg -> http://10.10.1.25:8080
  #-----------------------------------------------------------------------------
  - hostname: app.hdl.tg
    service: http://10.10.1.25:8080
    originRequest:
      connectTimeout: 30s
      noTLSVerify: false

  #-----------------------------------------------------------------------------
  # Catch-all (requis)
  #-----------------------------------------------------------------------------
  - service: http_status:404
```

---

### 3.3 cloudflared-manage.sh

**Description** : Utilitaire CLI pour les operations quotidiennes.

**Emplacement** : `/cloudflare-toolkit/cloudflared-manage.sh`

#### Commandes

**Gestion du service :**

```bash
# Demarrer le service
sudo ./cloudflared-manage.sh start

# Arreter le service
sudo ./cloudflared-manage.sh stop

# Redemarrer le service
sudo ./cloudflared-manage.sh restart

# Activer au demarrage systeme
sudo ./cloudflared-manage.sh enable

# Desactiver au demarrage
sudo ./cloudflared-manage.sh disable

# Afficher le statut
./cloudflared-manage.sh status

# Voir les logs en temps reel
./cloudflared-manage.sh logs

# Lancer en mode test (foreground)
sudo ./cloudflared-manage.sh test
```

**Gestion des tunnels :**

```bash
# Lister tous les tunnels
./cloudflared-manage.sh list

# Afficher les informations detaillees
./cloudflared-manage.sh info

# Afficher la configuration actuelle
./cloudflared-manage.sh config

# Valider la syntaxe de la configuration
./cloudflared-manage.sh validate
```

**Gestion des applications :**

```bash
# Ajouter une application (mode interactif)
sudo ./cloudflared-manage.sh add-app

# Ajouter une application (parametres)
sudo ./cloudflared-manage.sh add-app <domain> <ip> <port> [protocol]

# Exemples
sudo ./cloudflared-manage.sh add-app api.hdl.tg 10.10.1.24 8080
sudo ./cloudflared-manage.sh add-app secure.hdl.tg 10.10.1.24 443 https
sudo ./cloudflared-manage.sh add-app mysql.hdl.tg 10.10.1.24 3306 tcp

# Ajouter un acces SSH (raccourci)
sudo ./cloudflared-manage.sh add-ssh <domain> <ip> [port]
sudo ./cloudflared-manage.sh add-ssh dev-ssh.hdl.tg 10.10.1.25
sudo ./cloudflared-manage.sh add-ssh prod-ssh.hdl.tg 10.10.1.24 22

# Supprimer une application
sudo ./cloudflared-manage.sh remove-app <domain>

# Lister les applications configurees
./cloudflared-manage.sh list-apps
```

#### Detection automatique du protocole

Le script detecte automatiquement le protocole optimal selon le port :

```bash
Port 22        -> ssh://
Port 443, 8443 -> https:// (avec noTLSVerify)
Port 3389      -> rdp://
Port 3306      -> tcp:// (MySQL)
Port 5432      -> tcp:// (PostgreSQL)
Port 6379      -> tcp:// (Redis)
Port 27017     -> tcp:// (MongoDB)
Autres         -> http://
```

---

### 3.4 setup-origin-cert.sh

**Description** : Genere des certificats SSL Cloudflare Origin CA.

**Emplacement** : `/cloudflare-toolkit/setup-origin-cert.sh`

#### Options

| Option | Court | Description |
|--------|-------|-------------|
| `--token` | `-t` | API Token Cloudflare |
| `--zone` | `-z` | Zone ID |
| `--domain` | `-d` | Domaine principal |
| `--hostnames` | `-h` | Liste des hostnames (virgule) |
| `--output` | `-o` | Dossier de sortie |
| `--validity` | `-v` | Validite en jours |
| `--key-type` | `-k` | Type de cle (rsa/ecdsa) |

#### Durees de validite disponibles

| Jours | Duree |
|-------|-------|
| 7 | 1 semaine |
| 30 | 1 mois |
| 90 | 3 mois |
| 365 | 1 an |
| 730 | 2 ans |
| 1095 | 3 ans |
| 1825 | 5 ans |
| 3650 | 10 ans |
| 5475 | 15 ans (defaut) |

#### Fichiers generes

```
/etc/cloudflare-certs/
|-- <domain>.pem           # Certificat
|-- <domain>.key           # Cle privee (chmod 600)
|-- <domain>.csr           # Certificate Signing Request
|-- <domain>.fullchain.pem # Certificat + CA Root
|-- <domain>.id            # ID du certificat (pour revocation)
|-- cloudflare-origin-ca.pem # CA Root Cloudflare
|-- nginx-example.conf     # Exemple de configuration Nginx
```

---

## 4. Configuration detaillee

### 4.1 Structure du fichier config.yml

```yaml
# Identifiant du tunnel (UUID)
tunnel: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

# Chemin vers le fichier credentials
credentials-file: /etc/cloudflared/<tunnel-id>.json

# Niveau de log (optionnel)
# Options: debug, info, warn, error, fatal
# loglevel: info

# Endpoint metriques Prometheus (optionnel)
# metrics: 0.0.0.0:2000

# Regles de routage (ingress)
ingress:
  # Regle 1: Application web
  - hostname: app.domain.com
    service: http://10.10.1.25:8080
    originRequest:
      connectTimeout: 30s
      tlsTimeout: 10s
      tcpKeepAlive: 30s
      noHappyEyeballs: false
      keepAliveConnections: 100
      keepAliveTimeout: 90s
      httpHostHeader: ""
      originServerName: ""
      noTLSVerify: false
      disableChunkedEncoding: false
      proxyAddress: ""
      proxyPort: 0
      proxyType: ""

  # Regle 2: Application HTTPS avec certificat auto-signe
  - hostname: secure.domain.com
    service: https://10.10.1.25:443
    originRequest:
      noTLSVerify: true  # Ignorer la verification du certificat

  # Regle 3: Acces SSH
  - hostname: ssh.domain.com
    service: ssh://10.10.1.25:22

  # Regle 4: Acces RDP
  - hostname: rdp.domain.com
    service: rdp://10.10.1.25:3389

  # Regle 5: Service TCP (MySQL)
  - hostname: mysql.domain.com
    service: tcp://10.10.1.25:3306

  # Catch-all (OBLIGATOIRE - toujours en dernier)
  - service: http_status:404
```

### 4.2 Options originRequest

| Option | Type | Defaut | Description |
|--------|------|--------|-------------|
| `connectTimeout` | duration | 30s | Timeout de connexion au backend |
| `tlsTimeout` | duration | 10s | Timeout handshake TLS |
| `tcpKeepAlive` | duration | 30s | Intervalle TCP keep-alive |
| `noHappyEyeballs` | bool | false | Desactiver Happy Eyeballs |
| `keepAliveConnections` | int | 100 | Nombre max connexions persistantes |
| `keepAliveTimeout` | duration | 90s | Timeout connexions persistantes |
| `httpHostHeader` | string | "" | Header Host personnalise |
| `originServerName` | string | "" | SNI pour TLS |
| `noTLSVerify` | bool | false | Ignorer verification certificat |
| `disableChunkedEncoding` | bool | false | Desactiver chunked encoding |
| `proxyAddress` | string | "" | Adresse proxy amont |
| `proxyPort` | int | 0 | Port proxy amont |
| `proxyType` | string | "" | Type proxy (socks) |

### 4.3 Fichier credentials JSON

Structure du fichier `<tunnel-id>.json` :

```json
{
  "AccountTag": "<account-id>",
  "TunnelSecret": "<base64-encoded-secret>",
  "TunnelID": "<tunnel-uuid>"
}
```

### 4.4 Configuration API (.cf_config)

```bash
CF_API_TOKEN="<votre-api-token>"
CF_ZONE_ID="<zone-id>"
CF_ACCOUNT_ID="<account-id>"
CF_DOMAIN="hdl.tg"
```

---

## 5. API Cloudflare

### 5.1 Endpoints utilises

| Endpoint | Methode | Description |
|----------|---------|-------------|
| `/zones/{zone_id}` | GET | Informations de la zone |
| `/certificates` | POST | Creer un certificat Origin |
| `/certificates` | GET | Lister les certificats |
| `/zones/{zone_id}/filters` | POST | Creer un filtre WAF |
| `/zones/{zone_id}/firewall/rules` | POST | Creer une regle firewall |
| `/zones/{zone_id}/firewall/rules` | GET | Lister les regles |
| `/zones/{zone_id}/firewall/rules/{id}` | DELETE | Supprimer une regle |
| `/accounts/{account_id}/access/apps` | POST | Creer une application Access |

### 5.2 Permissions API Token requises

Pour une utilisation complete :

```
Zone:
  - DNS: Edit
  - SSL and Certificates: Edit

Account:
  - Cloudflare Tunnel: Edit
  - Access: Apps and Policies: Edit
```

### 5.3 Exemple de requete API

**Creer un certificat Origin :**

```bash
curl -X POST "https://api.cloudflare.com/client/v4/certificates" \
  -H "Authorization: Bearer <API_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "hostnames": ["*.hdl.tg", "hdl.tg"],
    "requested_validity": 5475,
    "request_type": "origin-rsa"
  }'
```

**Reponse :**

```json
{
  "success": true,
  "result": {
    "id": "cert-id",
    "certificate": "-----BEGIN CERTIFICATE-----...",
    "private_key": "-----BEGIN PRIVATE KEY-----...",
    "hostnames": ["*.hdl.tg", "hdl.tg"],
    "expires_on": "2040-01-01T00:00:00Z"
  }
}
```

---

## 6. Gestion des services

### 6.1 Service systemd

**Fichier service** : `/etc/systemd/system/cloudflared-<nom>.service`

```ini
[Unit]
Description=Cloudflare Tunnel - <nom>
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/cloudflared tunnel --config /etc/cloudflared/config.yml run
Restart=on-failure
RestartSec=5
TimeoutStartSec=0

StandardOutput=journal
StandardError=journal
SyslogIdentifier=cloudflared-<nom>

[Install]
WantedBy=multi-user.target
```

### 6.2 Commandes systemctl

```bash
# Recharger la configuration systemd
sudo systemctl daemon-reload

# Gestion du service
sudo systemctl start cloudflared-<nom>
sudo systemctl stop cloudflared-<nom>
sudo systemctl restart cloudflared-<nom>
sudo systemctl enable cloudflared-<nom>
sudo systemctl disable cloudflared-<nom>

# Statut
sudo systemctl status cloudflared-<nom>
sudo systemctl is-active cloudflared-<nom>
sudo systemctl is-enabled cloudflared-<nom>
```

### 6.3 Logs avec journalctl

```bash
# Voir les logs recents
sudo journalctl -u cloudflared-<nom> -n 50

# Suivre les logs en temps reel
sudo journalctl -u cloudflared-<nom> -f

# Logs depuis le dernier demarrage
sudo journalctl -u cloudflared-<nom> -b

# Logs d'une periode specifique
sudo journalctl -u cloudflared-<nom> --since "2024-01-01" --until "2024-01-02"

# Exporter les logs
sudo journalctl -u cloudflared-<nom> > tunnel.log
```

### 6.4 Metriques Prometheus

Activer dans `config.yml` :

```yaml
metrics: 0.0.0.0:2000
```

Metriques disponibles :

```
# Connexions tunnel
cloudflared_tunnel_connections_active
cloudflared_tunnel_connections_total

# Requetes
cloudflared_tunnel_requests_total
cloudflared_tunnel_requests_errors_total

# Latence
cloudflared_tunnel_request_duration_seconds
```

---

## 7. Certificats SSL Origin

### 7.1 Pourquoi utiliser des certificats Origin ?

1. **Chiffrement backend** : Securise la communication entre Cloudflare et votre serveur
2. **Longue duree** : Validite jusqu'a 15 ans
3. **Gratuit** : Inclus dans tous les plans Cloudflare
4. **Confiance** : Reconnu uniquement par Cloudflare (protection additionnelle)

### 7.2 Configuration SSL Cloudflare

Dans le dashboard Cloudflare, configurez :

**SSL/TLS > Overview :**
- Mode : **Full (strict)** (recommande avec certificat Origin)

**SSL/TLS > Origin Server :**
- Origin Certificates : Gerer vos certificats

### 7.3 Integration Nginx

```nginx
server {
    listen 443 ssl http2;
    server_name app.hdl.tg;

    # Certificat Origin
    ssl_certificate     /etc/cloudflare-certs/hdl.tg.pem;
    ssl_certificate_key /etc/cloudflare-certs/hdl.tg.key;

    # Ou avec fullchain
    # ssl_certificate     /etc/cloudflare-certs/hdl.tg.fullchain.pem;

    # Parametres SSL
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;

    # HSTS (optionnel, recommande)
    add_header Strict-Transport-Security "max-age=63072000" always;

    location / {
        proxy_pass http://127.0.0.1:8069;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# Redirection HTTP -> HTTPS
server {
    listen 80;
    server_name app.hdl.tg;
    return 301 https://$host$request_uri;
}
```

### 7.4 Integration Traefik (Docker)

```yaml
# docker-compose.yml
version: '3'

services:
  traefik:
    image: traefik:v2.10
    command:
      - --providers.docker=true
      - --entrypoints.websecure.address=:443
    ports:
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /etc/cloudflare-certs:/certs:ro

  app:
    image: myapp:latest
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.app.rule=Host(`app.hdl.tg`)"
      - "traefik.http.routers.app.entrypoints=websecure"
      - "traefik.http.routers.app.tls=true"
```

---

## 8. Zero Trust Network Access

### 8.1 Restriction par IP (WAF)

Creer une regle qui bloque tout sauf certaines IPs :

**Expression WAF :**
```
(http.host eq "app.hdl.tg" or http.host eq "api.hdl.tg") and not ip.src in {102.64.145.19 41.207.123.45}
```

**Via l'API :**

```bash
# 1. Creer le filtre
curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/filters" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '[{
    "expression": "(http.host eq \"app.hdl.tg\") and not ip.src in {102.64.145.19}"
  }]'

# 2. Creer la regle
curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/firewall/rules" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '[{
    "filter": {"id": "<filter-id>"},
    "action": "block",
    "description": "IP Restriction"
  }]'
```

### 8.2 Cloudflare Access

Creer une application Access pour authentifier les utilisateurs :

**Types d'applications :**
- `self_hosted` : Application web
- `ssh` : Acces SSH
- `vnc` : Acces VNC

**Via l'API :**

```bash
curl -X POST "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/access/apps" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Application Interne",
    "domain": "app.hdl.tg",
    "type": "self_hosted",
    "session_duration": "24h"
  }'
```

### 8.3 Politiques Access

Configurables via le dashboard Zero Trust (https://one.dash.cloudflare.com) :

**Types de politiques :**
- **Allow** : Autoriser l'acces
- **Block** : Bloquer l'acces
- **Bypass** : Ignorer l'authentification

**Criteres disponibles :**
- Emails ou domaines email
- Groupes (SAML, OIDC)
- Plages IP
- Pays
- Service Tokens
- Certificats mTLS

---

## 9. Split DNS et Intranet

### 9.1 Concept

Le Split DNS permet aux utilisateurs internes d'acceder directement aux services sans passer par Internet.

```
                        Internet
                            |
    +------------+----------+----------+------------+
    |            |                     |            |
    v            v                     v            v
  User 1      User 2                User 3      User 4
 (Externe)   (Externe)             (Interne)   (Interne)
    |            |                     |            |
    v            v                     |            |
  Cloudflare  Cloudflare              |            |
    |            |                     |            |
    v            v                     v            v
    +------------+---------------------+------------+
                 |
                 v
           Serveur Interne
           (10.10.1.25:8080)
```

### 9.2 Configuration /etc/hosts

Ajouter sur les machines internes :

```
# Applications Cloudflare - Acces direct intranet
10.10.1.25    app.hdl.tg
10.10.1.26    api.hdl.tg
10.10.1.25    ssh.hdl.tg
```

### 9.3 Configuration dnsmasq

```conf
# /etc/dnsmasq.conf
address=/app.hdl.tg/10.10.1.25
address=/api.hdl.tg/10.10.1.26
address=/ssh.hdl.tg/10.10.1.25
```

### 9.4 Configuration BIND

```
; Zone hdl.tg - Intranet
$TTL 3600
@       IN      SOA     ns1.hdl.tg. admin.hdl.tg. (
                        2024010101 ; Serial
                        3600       ; Refresh
                        1800       ; Retry
                        604800     ; Expire
                        86400 )    ; Minimum TTL

        IN      NS      ns1.hdl.tg.

app     IN      A       10.10.1.25
api     IN      A       10.10.1.26
ssh     IN      A       10.10.1.25
```

---

## 10. Maintenance et operations

### 10.1 Sauvegarde

**Fichiers a sauvegarder :**

```bash
# Configuration
/etc/cloudflared/config.yml
/etc/cloudflared/<tunnel-id>.json
/etc/cloudflared/.cf_config

# Certificats
/etc/cloudflare-certs/

# Authentification
/root/.cloudflared/cert.pem

# Service
/etc/systemd/system/cloudflared-*.service
```

**Script de sauvegarde :**

```bash
#!/bin/bash
BACKUP_DIR="/backup/cloudflare/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

cp -r /etc/cloudflared "$BACKUP_DIR/"
cp -r /etc/cloudflare-certs "$BACKUP_DIR/"
cp -r /root/.cloudflared "$BACKUP_DIR/"
cp /etc/systemd/system/cloudflared-*.service "$BACKUP_DIR/"

tar -czf "$BACKUP_DIR.tar.gz" "$BACKUP_DIR"
rm -rf "$BACKUP_DIR"
```

### 10.2 Restauration

```bash
#!/bin/bash
BACKUP_FILE="$1"

tar -xzf "$BACKUP_FILE" -C /tmp
cp -r /tmp/*/cloudflared/* /etc/cloudflared/
cp -r /tmp/*/cloudflare-certs/* /etc/cloudflare-certs/
cp -r /tmp/*/.cloudflared/* /root/.cloudflared/
cp /tmp/*/cloudflared-*.service /etc/systemd/system/

systemctl daemon-reload
systemctl restart cloudflared-*
```

### 10.3 Mise a jour cloudflared

```bash
# Via le manager
sudo ./cloudflare-manager.sh
# Menu 1 > Option 5

# Ou manuellement
sudo systemctl stop cloudflared-*
curl -L -o /usr/local/bin/cloudflared \
  https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x /usr/local/bin/cloudflared
sudo systemctl start cloudflared-*
```

### 10.4 Rotation des credentials

En cas de compromission :

```bash
# 1. Revoquer le tunnel existant
cloudflared tunnel delete <nom-tunnel>

# 2. Recreer le tunnel
cloudflared tunnel create <nom-tunnel>

# 3. Mettre a jour la configuration
# Remplacer le tunnel ID et copier les nouveaux credentials

# 4. Redemarrer
sudo systemctl restart cloudflared-*
```

---

## 11. Reference des erreurs

### 11.1 Erreurs courantes

| Erreur | Cause | Solution |
|--------|-------|----------|
| `failed to connect to origin` | Service backend inaccessible | Verifier que l'application est demarree |
| `failed to retrieve credentials` | Fichier credentials manquant | Re-authentifier avec `cloudflared tunnel login` |
| `invalid configuration` | Syntaxe YAML incorrecte | Valider avec `cloudflared tunnel ingress validate` |
| `duplicate hostname` | Domaine deja configure | Supprimer l'entree existante |
| `DNS record already exists` | CNAME existe deja | Supprimer dans le dashboard ou ignorer |
| `authentication failed` | Token API invalide | Verifier/regenerer le token |

### 11.2 Codes de sortie

| Code | Signification |
|------|---------------|
| 0 | Succes |
| 1 | Erreur generale |
| 2 | Erreur de configuration |
| 3 | Erreur d'authentification |

### 11.3 Diagnostic

```bash
# Verifier le statut
sudo systemctl status cloudflared-*

# Voir les logs
sudo journalctl -u cloudflared-* -n 100

# Valider la config
cloudflared tunnel --config /etc/cloudflared/config.yml ingress validate

# Tester en foreground
cloudflared tunnel --config /etc/cloudflared/config.yml run

# Tester la connectivite backend
curl -v http://10.10.1.25:8080

# Verifier le DNS
dig app.hdl.tg
nslookup app.hdl.tg
```

---

## 12. Annexes

### 12.1 Glossaire

| Terme | Definition |
|-------|------------|
| **Anycast** | Technologie de routage ou plusieurs serveurs partagent la meme IP |
| **CNAME** | Canonical Name - Alias DNS pointant vers un autre nom |
| **Edge** | Serveurs Cloudflare repartis mondialement |
| **Ingress** | Trafic entrant / regles de routage |
| **mTLS** | Mutual TLS - Authentification bidirectionnelle |
| **Origin** | Votre serveur backend |
| **QUIC** | Protocole de transport rapide base sur UDP |
| **SNI** | Server Name Indication - Extension TLS |

### 12.2 Ports et protocoles

**Ports utilises par cloudflared (sortants) :**
- 443/TCP - HTTPS
- 7844/TCP - HTTP/2 over TLS
- 7844/UDP - QUIC

**Aucun port entrant requis.**

### 12.3 Limites

| Element | Limite |
|---------|--------|
| Tunnels par compte | Illimite |
| Applications par tunnel | Illimite |
| Taille requete | 100MB (configurable) |
| Timeout connexion | 30s (configurable) |
| Certificats Origin | 15 ans max |

### 12.4 Ressources externes

- [Repository du projet](https://github.com/liksoft/cloudflare-ztna)
- [Documentation Cloudflare Tunnels](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [API Reference](https://api.cloudflare.com/)
- [GitHub cloudflared](https://github.com/cloudflare/cloudflared)
- [Community Forum](https://community.cloudflare.com/)
- [Zero Trust Documentation](https://developers.cloudflare.com/cloudflare-one/)

---

## Historique des versions

| Version | Date | Changements |
|---------|------|-------------|
| 2.0 | 2024-01 | Refonte complete, ajout ZTNA, certificats Origin |
| 1.0 | 2023-06 | Version initiale |

---

**Auteur** : CNSS/HDL - Togo
**Licence** : MIT
