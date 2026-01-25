#!/bin/bash

#===============================================================================
# Script de configuration Cloudflare Tunnel - Version Dynamique
# Usage: ./setup-cloudflared.sh [options]
#===============================================================================

set -e

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration par défaut (modifiable via arguments ou interactivement)
TUNNEL_NAME=""
HOSTNAME=""
LOCAL_IP=""
LOCAL_PORT=""
LOCAL_PROTOCOL="http"
CLOUDFLARED_DIR="/etc/cloudflared"
CLOUDFLARED_BIN="/usr/local/bin/cloudflared"
INTERACTIVE=true
AUTO_START=false

#-------------------------------------------------------------------------------
# Afficher l'aide
#-------------------------------------------------------------------------------
show_help() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}        Configuration Cloudflare Tunnel - Script Dynamique         ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -n, --name <nom>         Nom du tunnel (ex: hdl-likmed)"
    echo "  -d, --domain <domaine>   Domaine public (ex: test-likmed.hdl.tg)"
    echo "  -i, --ip <ip>            IP locale de l'application (ex: 10.10.1.25)"
    echo "  -p, --port <port>        Port de l'application (ex: 4430)"
    echo "  -s, --protocol <proto>   Protocole: http ou https (défaut: http)"
    echo "  -y, --yes                Mode non-interactif (utilise les valeurs par défaut)"
    echo "  --auto-start             Démarrer automatiquement après installation"
    echo "  -h, --help               Afficher cette aide"
    echo ""
    echo "Exemples:"
    echo ""
    echo "  # Mode interactif (recommandé pour la première fois)"
    echo "  sudo $0"
    echo ""
    echo "  # Mode avec paramètres"
    echo "  sudo $0 -n hdl-test -d test-likmed.hdl.tg -i 10.10.1.25 -p 4430"
    echo ""
    echo "  # Mode complet avec démarrage auto"
    echo "  sudo $0 -n hdl-test -d test-likmed.hdl.tg -i 10.10.1.25 -p 4430 --auto-start"
    echo ""
}

#-------------------------------------------------------------------------------
# Parser les arguments
#-------------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--name)
                TUNNEL_NAME="$2"
                shift 2
                ;;
            -d|--domain)
                HOSTNAME="$2"
                shift 2
                ;;
            -i|--ip)
                LOCAL_IP="$2"
                shift 2
                ;;
            -p|--port)
                LOCAL_PORT="$2"
                shift 2
                ;;
            -s|--protocol)
                LOCAL_PROTOCOL="$2"
                shift 2
                ;;
            -y|--yes)
                INTERACTIVE=false
                shift
                ;;
            --auto-start)
                AUTO_START=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}Option inconnue: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
}

#-------------------------------------------------------------------------------
# Demander les informations de manière interactive
#-------------------------------------------------------------------------------
interactive_config() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       Configuration Cloudflare Tunnel - Mode Interactif        ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Nom du tunnel
    if [ -z "$TUNNEL_NAME" ]; then
        echo -e "${CYAN}┌─ Nom du tunnel${NC}"
        echo -e "${CYAN}│  C'est un identifiant unique pour ce tunnel dans Cloudflare${NC}"
        echo -e "${CYAN}│  Exemple: hdl-test, likmed-prod, cnss-api${NC}"
        read -p "└─ Nom du tunnel: " TUNNEL_NAME
        echo ""
    fi
    
    # Domaine
    if [ -z "$HOSTNAME" ]; then
        echo -e "${CYAN}┌─ Domaine public${NC}"
        echo -e "${CYAN}│  Le sous-domaine qui sera accessible sur Internet${NC}"
        echo -e "${CYAN}│  Exemple: test-likmed.hdl.tg, api.hdl.tg${NC}"
        read -p "└─ Domaine: " HOSTNAME
        echo ""
    fi
    
    # IP locale
    if [ -z "$LOCAL_IP" ]; then
        # Détecter l'IP locale actuelle
        DETECTED_IP=$(hostname -I | awk '{print $1}')
        echo -e "${CYAN}┌─ IP de l'application${NC}"
        echo -e "${CYAN}│  L'adresse IP où tourne l'application à exposer${NC}"
        echo -e "${CYAN}│  IP détectée sur ce serveur: ${DETECTED_IP}${NC}"
        read -p "└─ IP locale [$DETECTED_IP]: " LOCAL_IP
        LOCAL_IP=${LOCAL_IP:-$DETECTED_IP}
        echo ""
    fi
    
    # Port
    if [ -z "$LOCAL_PORT" ]; then
        echo -e "${CYAN}┌─ Port de l'application${NC}"
        echo -e "${CYAN}│  Le port sur lequel l'application écoute${NC}"
        echo -e "${CYAN}│  Exemple: 8080, 3000, 4430, 9000${NC}"
        read -p "└─ Port: " LOCAL_PORT
        echo ""
    fi
    
    # Protocole
    echo -e "${CYAN}┌─ Protocole de l'application${NC}"
    echo -e "${CYAN}│  L'application locale utilise HTTP ou HTTPS ?${NC}"
    read -p "└─ Protocole (http/https) [$LOCAL_PROTOCOL]: " proto_input
    LOCAL_PROTOCOL=${proto_input:-$LOCAL_PROTOCOL}
    echo ""
}

#-------------------------------------------------------------------------------
# Valider la configuration
#-------------------------------------------------------------------------------
validate_config() {
    local errors=0
    
    echo -e "${YELLOW}Validation de la configuration...${NC}"
    echo ""
    
    # Vérifier le nom du tunnel
    if [ -z "$TUNNEL_NAME" ]; then
        echo -e "${RED}  ✗ Nom du tunnel manquant${NC}"
        errors=$((errors + 1))
    else
        echo -e "${GREEN}  ✓ Tunnel: $TUNNEL_NAME${NC}"
    fi
    
    # Vérifier le domaine
    if [ -z "$HOSTNAME" ]; then
        echo -e "${RED}  ✗ Domaine manquant${NC}"
        errors=$((errors + 1))
    else
        echo -e "${GREEN}  ✓ Domaine: $HOSTNAME${NC}"
    fi
    
    # Vérifier l'IP
    if [ -z "$LOCAL_IP" ]; then
        echo -e "${RED}  ✗ IP locale manquante${NC}"
        errors=$((errors + 1))
    elif [[ ! $LOCAL_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}  ✗ Format IP invalide: $LOCAL_IP${NC}"
        errors=$((errors + 1))
    else
        echo -e "${GREEN}  ✓ IP: $LOCAL_IP${NC}"
    fi
    
    # Vérifier le port
    if [ -z "$LOCAL_PORT" ]; then
        echo -e "${RED}  ✗ Port manquant${NC}"
        errors=$((errors + 1))
    elif [[ ! $LOCAL_PORT =~ ^[0-9]+$ ]] || [ "$LOCAL_PORT" -lt 1 ] || [ "$LOCAL_PORT" -gt 65535 ]; then
        echo -e "${RED}  ✗ Port invalide: $LOCAL_PORT${NC}"
        errors=$((errors + 1))
    else
        echo -e "${GREEN}  ✓ Port: $LOCAL_PORT${NC}"
    fi
    
    # Vérifier le protocole
    if [[ ! "$LOCAL_PROTOCOL" =~ ^(http|https)$ ]]; then
        echo -e "${RED}  ✗ Protocole invalide: $LOCAL_PROTOCOL (doit être http ou https)${NC}"
        errors=$((errors + 1))
    else
        echo -e "${GREEN}  ✓ Protocole: $LOCAL_PROTOCOL${NC}"
    fi
    
    echo ""
    
    if [ $errors -gt 0 ]; then
        echo -e "${RED}Configuration invalide ($errors erreurs)${NC}"
        exit 1
    fi
    
    # Construire l'URL du service
    LOCAL_SERVICE="${LOCAL_PROTOCOL}://${LOCAL_IP}:${LOCAL_PORT}"
    echo -e "${GREEN}  ✓ Service: $LOCAL_SERVICE${NC}"
    echo ""
}

#-------------------------------------------------------------------------------
# Afficher le résumé et confirmer
#-------------------------------------------------------------------------------
confirm_config() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                    Résumé de la configuration                  ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Nom du tunnel:     ${CYAN}${TUNNEL_NAME}${NC}"
    echo -e "  Domaine public:    ${CYAN}https://${HOSTNAME}${NC}"
    echo -e "  Service local:     ${CYAN}${LOCAL_SERVICE}${NC}"
    echo ""
    echo -e "${BLUE}────────────────────────────────────────────────────────────────────${NC}"
    echo ""
    
    if [ "$INTERACTIVE" = true ]; then
        read -p "Confirmer et continuer l'installation ? (O/n): " confirm
        if [[ "$confirm" =~ ^[Nn]$ ]]; then
            echo -e "${YELLOW}Installation annulée${NC}"
            exit 0
        fi
    fi
}

#-------------------------------------------------------------------------------
# Vérifier si on est root
#-------------------------------------------------------------------------------
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}[ERREUR] Ce script doit être exécuté en tant que root${NC}"
        echo "Utilise: sudo $0 $*"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# Tester la connectivité vers l'application
#-------------------------------------------------------------------------------
test_connectivity() {
    echo ""
    echo -e "${YELLOW}[PRÉ-CHECK] Test de connectivité vers ${LOCAL_SERVICE}...${NC}"
    
    if command -v curl &> /dev/null; then
        if curl -s --connect-timeout 5 "$LOCAL_SERVICE" > /dev/null 2>&1; then
            echo -e "${GREEN}  ✓ Application accessible sur ${LOCAL_SERVICE}${NC}"
        else
            echo -e "${YELLOW}  ⚠ Impossible de joindre ${LOCAL_SERVICE}${NC}"
            echo -e "${YELLOW}    Vérifie que l'application est démarrée et accessible${NC}"
            if [ "$INTERACTIVE" = true ]; then
                read -p "  Continuer quand même ? (o/N): " continue_anyway
                if [[ ! "$continue_anyway" =~ ^[Oo]$ ]]; then
                    exit 1
                fi
            fi
        fi
    else
        echo -e "${YELLOW}  ⚠ curl non installé, test de connectivité ignoré${NC}"
    fi
}

#-------------------------------------------------------------------------------
# Installer cloudflared
#-------------------------------------------------------------------------------
install_cloudflared() {
    echo ""
    echo -e "${YELLOW}[1/6] Vérification de cloudflared...${NC}"
    
    if command -v cloudflared &> /dev/null; then
        CURRENT_VERSION=$(cloudflared --version | head -1)
        echo -e "${GREEN}  ✓ cloudflared déjà installé: ${CURRENT_VERSION}${NC}"
        
        if [ "$INTERACTIVE" = true ]; then
            read -p "  Mettre à jour ? (o/N): " update_choice
            if [[ ! "$update_choice" =~ ^[Oo]$ ]]; then
                return 0
            fi
        else
            return 0
        fi
    fi
    
    echo -e "${YELLOW}  Installation de cloudflared...${NC}"
    
    # Détecter l'architecture
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            CLOUDFLARED_ARCH="amd64"
            ;;
        aarch64|arm64)
            CLOUDFLARED_ARCH="arm64"
            ;;
        armv7l)
            CLOUDFLARED_ARCH="arm"
            ;;
        *)
            echo -e "${RED}  Architecture non supportée: $ARCH${NC}"
            exit 1
            ;;
    esac
    
    DOWNLOAD_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CLOUDFLARED_ARCH}"
    
    echo "  Téléchargement depuis: ${DOWNLOAD_URL}"
    curl -L -o /tmp/cloudflared "$DOWNLOAD_URL" --progress-bar
    
    mv /tmp/cloudflared "$CLOUDFLARED_BIN"
    chmod +x "$CLOUDFLARED_BIN"
    
    if cloudflared --version &> /dev/null; then
        echo -e "${GREEN}  ✓ cloudflared installé avec succès${NC}"
        cloudflared --version | head -1
    else
        echo -e "${RED}  ✗ Échec de l'installation${NC}"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# Authentification Cloudflare
#-------------------------------------------------------------------------------
authenticate_cloudflare() {
    echo ""
    echo -e "${YELLOW}[2/6] Authentification Cloudflare...${NC}"
    
    mkdir -p "$CLOUDFLARED_DIR"
    mkdir -p /root/.cloudflared
    
    if [ -f "/root/.cloudflared/cert.pem" ]; then
        echo -e "${GREEN}  ✓ Déjà authentifié (cert.pem existe)${NC}"
        
        if [ "$INTERACTIVE" = true ]; then
            read -p "  Se ré-authentifier ? (o/N): " reauth_choice
            if [[ ! "$reauth_choice" =~ ^[Oo]$ ]]; then
                return 0
            fi
        else
            return 0
        fi
    fi
    
    echo ""
    echo -e "${BLUE}  ═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  IMPORTANT: Une URL va s'afficher.${NC}"
    echo -e "${BLUE}  1. Copie cette URL et ouvre-la dans ton navigateur${NC}"
    echo -e "${BLUE}  2. Connecte-toi à ton compte Cloudflare${NC}"
    echo -e "${BLUE}  3. Sélectionne le domaine correspondant (hdl.tg)${NC}"
    echo -e "${BLUE}  ═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ "$INTERACTIVE" = true ]; then
        read -p "  Appuie sur Entrée pour continuer..."
    fi
    
    cloudflared tunnel login
    
    if [ -f "/root/.cloudflared/cert.pem" ]; then
        echo -e "${GREEN}  ✓ Authentification réussie${NC}"
    else
        echo -e "${RED}  ✗ Échec de l'authentification${NC}"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# Créer le tunnel
#-------------------------------------------------------------------------------
create_tunnel() {
    echo ""
    echo -e "${YELLOW}[3/6] Création du tunnel '${TUNNEL_NAME}'...${NC}"
    
    EXISTING_TUNNEL=$(cloudflared tunnel list | grep -w "$TUNNEL_NAME" || true)
    
    if [ -n "$EXISTING_TUNNEL" ]; then
        TUNNEL_ID=$(echo "$EXISTING_TUNNEL" | awk '{print $1}')
        echo -e "${GREEN}  ✓ Le tunnel '${TUNNEL_NAME}' existe déjà (ID: ${TUNNEL_ID})${NC}"
        
        if [ "$INTERACTIVE" = true ]; then
            read -p "  Supprimer et recréer ? (o/N): " recreate_choice
            if [[ "$recreate_choice" =~ ^[Oo]$ ]]; then
                echo "  Suppression du tunnel existant..."
                cloudflared tunnel cleanup "$TUNNEL_NAME" 2>/dev/null || true
                cloudflared tunnel delete "$TUNNEL_NAME" 2>/dev/null || true
                sleep 2
            else
                return 0
            fi
        else
            return 0
        fi
    fi
    
    cloudflared tunnel create "$TUNNEL_NAME"
    
    TUNNEL_ID=$(cloudflared tunnel list | grep -w "$TUNNEL_NAME" | awk '{print $1}')
    
    if [ -n "$TUNNEL_ID" ]; then
        echo -e "${GREEN}  ✓ Tunnel créé (ID: ${TUNNEL_ID})${NC}"
    else
        echo -e "${RED}  ✗ Échec de la création du tunnel${NC}"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# Configurer le routage DNS
#-------------------------------------------------------------------------------
configure_dns() {
    echo ""
    echo -e "${YELLOW}[4/6] Configuration DNS pour ${HOSTNAME}...${NC}"
    
    TUNNEL_ID=$(cloudflared tunnel list | grep -w "$TUNNEL_NAME" | awk '{print $1}')
    
    echo -e "${BLUE}  Création CNAME: ${HOSTNAME} → ${TUNNEL_ID}.cfargotunnel.com${NC}"
    
    cloudflared tunnel route dns "$TUNNEL_NAME" "$HOSTNAME" 2>/dev/null || {
        echo -e "${YELLOW}  ⚠ L'enregistrement DNS existe peut-être déjà${NC}"
    }
    
    echo -e "${GREEN}  ✓ Routage DNS configuré${NC}"
}

#-------------------------------------------------------------------------------
# Créer le fichier de configuration
#-------------------------------------------------------------------------------
create_config() {
    echo ""
    echo -e "${YELLOW}[5/6] Création du fichier de configuration...${NC}"
    
    TUNNEL_ID=$(cloudflared tunnel list | grep -w "$TUNNEL_NAME" | awk '{print $1}')
    
    CRED_FILE="/root/.cloudflared/${TUNNEL_ID}.json"
    
    if [ ! -f "$CRED_FILE" ]; then
        echo -e "${RED}  ✗ Fichier de credentials non trouvé: $CRED_FILE${NC}"
        exit 1
    fi
    
    cp "$CRED_FILE" "$CLOUDFLARED_DIR/"
    
    CONFIG_FILE="$CLOUDFLARED_DIR/config.yml"
    
    # Déterminer si on doit désactiver la vérification TLS
    NO_TLS_VERIFY="false"
    if [ "$LOCAL_PROTOCOL" = "https" ]; then
        NO_TLS_VERIFY="true"
    fi
    
    cat > "$CONFIG_FILE" << EOF
#===============================================================================
# Configuration Cloudflare Tunnel
# Généré le: $(date)
# Script: setup-cloudflared.sh
#===============================================================================

tunnel: ${TUNNEL_ID}
credentials-file: ${CLOUDFLARED_DIR}/${TUNNEL_ID}.json

# Logging (debug, info, warn, error, fatal)
# loglevel: info

# Métriques Prometheus (décommenter pour activer)
# metrics: 0.0.0.0:2000

ingress:
  #-----------------------------------------------------------------------------
  # ${HOSTNAME} → ${LOCAL_SERVICE}
  #-----------------------------------------------------------------------------
  - hostname: ${HOSTNAME}
    service: ${LOCAL_SERVICE}
    originRequest:
      connectTimeout: 30s
      noTLSVerify: ${NO_TLS_VERIFY}

  #-----------------------------------------------------------------------------
  # Ajouter d'autres applications ci-dessous
  # Exemple:
  # - hostname: autre-app.hdl.tg
  #   service: http://10.10.1.24:8080
  #-----------------------------------------------------------------------------

  #-----------------------------------------------------------------------------
  # Catch-all (requis)
  #-----------------------------------------------------------------------------
  - service: http_status:404
EOF

    echo -e "${GREEN}  ✓ Configuration créée: $CONFIG_FILE${NC}"
}

#-------------------------------------------------------------------------------
# Créer le service systemd
#-------------------------------------------------------------------------------
create_systemd_service() {
    echo ""
    echo -e "${YELLOW}[6/6] Création du service systemd...${NC}"
    
    SERVICE_NAME="cloudflared-${TUNNEL_NAME}"
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
    
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Cloudflare Tunnel - ${TUNNEL_NAME}
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=${CLOUDFLARED_BIN} tunnel --config ${CLOUDFLARED_DIR}/config.yml run
Restart=on-failure
RestartSec=5
TimeoutStartSec=0

StandardOutput=journal
StandardError=journal
SyslogIdentifier=cloudflared-${TUNNEL_NAME}

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    
    echo -e "${GREEN}  ✓ Service créé: ${SERVICE_NAME}.service${NC}"
    
    # Sauvegarder le nom du service pour les autres fonctions
    echo "$SERVICE_NAME" > "$CLOUDFLARED_DIR/.service_name"
}

#-------------------------------------------------------------------------------
# Afficher le résumé final
#-------------------------------------------------------------------------------
show_final_summary() {
    TUNNEL_ID=$(cloudflared tunnel list | grep -w "$TUNNEL_NAME" | awk '{print $1}')
    SERVICE_NAME="cloudflared-${TUNNEL_NAME}"
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              ✓ INSTALLATION TERMINÉE AVEC SUCCÈS               ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}Tunnel${NC}"
    echo -e "    Nom:          ${TUNNEL_NAME}"
    echo -e "    ID:           ${TUNNEL_ID}"
    echo ""
    echo -e "  ${CYAN}Accès${NC}"
    echo -e "    URL publique: ${GREEN}https://${HOSTNAME}${NC}"
    echo -e "    Service:      ${LOCAL_SERVICE}"
    echo ""
    echo -e "  ${CYAN}Fichiers${NC}"
    echo -e "    Config:       ${CLOUDFLARED_DIR}/config.yml"
    echo -e "    Service:      /etc/systemd/system/${SERVICE_NAME}.service"
    echo ""
    echo -e "${BLUE}────────────────────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${YELLOW}Commandes utiles:${NC}"
    echo ""
    echo "    # Démarrer le service"
    echo -e "    ${CYAN}sudo systemctl start ${SERVICE_NAME}${NC}"
    echo ""
    echo "    # Activer au démarrage"
    echo -e "    ${CYAN}sudo systemctl enable ${SERVICE_NAME}${NC}"
    echo ""
    echo "    # Voir les logs"
    echo -e "    ${CYAN}sudo journalctl -u ${SERVICE_NAME} -f${NC}"
    echo ""
    echo "    # Statut"
    echo -e "    ${CYAN}sudo systemctl status ${SERVICE_NAME}${NC}"
    echo ""
    echo "    # Test manuel (foreground)"
    echo -e "    ${CYAN}cloudflared tunnel --config /etc/cloudflared/config.yml run${NC}"
    echo ""
}

#-------------------------------------------------------------------------------
# Démarrer le tunnel
#-------------------------------------------------------------------------------
start_tunnel() {
    SERVICE_NAME="cloudflared-${TUNNEL_NAME}"
    
    if [ "$AUTO_START" = true ]; then
        echo ""
        echo -e "${YELLOW}Démarrage automatique du service...${NC}"
        systemctl enable "$SERVICE_NAME"
        systemctl start "$SERVICE_NAME"
        sleep 3
        
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            echo -e "${GREEN}✓ Service démarré et activé au démarrage${NC}"
            echo ""
            echo -e "${GREEN}Teste maintenant: https://${HOSTNAME}${NC}"
        else
            echo -e "${RED}✗ Échec du démarrage, voir les logs:${NC}"
            journalctl -u "$SERVICE_NAME" -n 20 --no-pager
        fi
        return
    fi
    
    if [ "$INTERACTIVE" = true ]; then
        echo ""
        echo -e "${YELLOW}Comment veux-tu démarrer le tunnel ?${NC}"
        echo ""
        echo "  1) Démarrer comme service (recommandé - tourne en arrière-plan)"
        echo "  2) Mode test (foreground - s'arrête si tu fermes la session)"
        echo "  3) Ne pas démarrer maintenant"
        echo ""
        read -p "Choix [1]: " start_choice
        start_choice=${start_choice:-1}
        
        case $start_choice in
            1)
                echo ""
                echo -e "${YELLOW}Activation et démarrage du service...${NC}"
                systemctl enable "$SERVICE_NAME"
                systemctl start "$SERVICE_NAME"
                sleep 3
                
                if systemctl is-active --quiet "$SERVICE_NAME"; then
                    echo -e "${GREEN}✓ Service démarré avec succès${NC}"
                    echo -e "${GREEN}✓ Activé au démarrage du serveur${NC}"
                    echo ""
                    echo -e "${GREEN}Teste maintenant: https://${HOSTNAME}${NC}"
                    echo ""
                    echo -e "${CYAN}Commandes utiles:${NC}"
                    echo "  sudo systemctl status ${SERVICE_NAME}"
                    echo "  sudo journalctl -u ${SERVICE_NAME} -f"
                else
                    echo -e "${RED}✗ Échec du démarrage${NC}"
                    journalctl -u "$SERVICE_NAME" -n 20 --no-pager
                fi
                ;;
            2)
                echo ""
                echo -e "${YELLOW}Démarrage en mode test (Ctrl+C pour arrêter)...${NC}"
                echo -e "${GREEN}Teste dans ton navigateur: https://${HOSTNAME}${NC}"
                echo ""
                cloudflared tunnel --config "$CLOUDFLARED_DIR/config.yml" run
                ;;
            3)
                echo ""
                echo -e "${YELLOW}Tu pourras démarrer plus tard avec:${NC}"
                echo "  sudo systemctl enable ${SERVICE_NAME}"
                echo "  sudo systemctl start ${SERVICE_NAME}"
                ;;
            *)
                echo -e "${RED}Choix invalide${NC}"
                ;;
        esac
    fi
}

#===============================================================================
# MAIN
#===============================================================================

# Parser les arguments
parse_args "$@"

# Vérifier root
check_root

# Mode interactif si pas tous les paramètres fournis
if [ -z "$TUNNEL_NAME" ] || [ -z "$HOSTNAME" ] || [ -z "$LOCAL_IP" ] || [ -z "$LOCAL_PORT" ]; then
    interactive_config
fi

# Valider la configuration
validate_config

# Confirmer
confirm_config

# Tester la connectivité
test_connectivity

# Installation
install_cloudflared
authenticate_cloudflare
create_tunnel
configure_dns
create_config
create_systemd_service

# Résumé
show_final_summary

# Démarrer
start_tunnel
