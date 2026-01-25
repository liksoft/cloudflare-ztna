#!/bin/bash

#===============================================================================
# Script de gestion Cloudflare Tunnel
# Opérations: start, stop, status, logs, add-app, remove-app, list
#===============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

CLOUDFLARED_DIR="/etc/cloudflared"
CONFIG_FILE="$CLOUDFLARED_DIR/config.yml"

#-------------------------------------------------------------------------------
# Détecter le nom du service
#-------------------------------------------------------------------------------
get_service_name() {
    # Essayer de lire depuis le fichier sauvegardé
    if [ -f "$CLOUDFLARED_DIR/.service_name" ]; then
        cat "$CLOUDFLARED_DIR/.service_name"
        return
    fi
    
    # Sinon chercher dans systemd
    local service=$(systemctl list-unit-files | grep "cloudflared-" | grep -v "@" | awk '{print $1}' | head -1 | sed 's/.service$//')
    
    if [ -n "$service" ]; then
        echo "$service"
        return
    fi
    
    # Fallback
    echo "cloudflared"
}

SERVICE_NAME=$(get_service_name)

#-------------------------------------------------------------------------------
# Afficher l'aide
#-------------------------------------------------------------------------------
show_help() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}              Gestion Cloudflare Tunnel - CNSS/HDL                 ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Usage: $0 <commande> [options]"
    echo ""
    echo -e "${CYAN}Gestion du service:${NC}"
    echo "  start              Démarrer le service"
    echo "  stop               Arrêter le service"
    echo "  restart            Redémarrer le service"
    echo "  enable             Activer au démarrage"
    echo "  disable            Désactiver au démarrage"
    echo "  status             Statut du service"
    echo "  logs               Logs en temps réel"
    echo "  test               Lancer en mode test (foreground)"
    echo ""
    echo -e "${CYAN}Gestion des tunnels:${NC}"
    echo "  list               Lister tous les tunnels"
    echo "  info               Informations détaillées"
    echo "  config             Afficher la configuration"
    echo "  validate           Valider la configuration"
    echo ""
    echo -e "${CYAN}Gestion des applications:${NC}"
    echo "  add-app            Ajouter une application (interactif)"
    echo "  add-app <domain> <ip> <port> [protocol]"
    echo "                     Ajouter une application (paramètres)"
    echo "                     Protocoles: http, https, ssh, tcp, rdp, auto"
    echo "  add-ssh <domain> <ip> [port]"
    echo "                     Raccourci pour ajouter un accès SSH"
    echo "  remove-app <domain>"
    echo "                     Supprimer une application"
    echo "  list-apps          Lister les applications configurées"
    echo ""
    echo -e "${CYAN}Exemples:${NC}"
    echo "  $0 start"
    echo "  $0 add-app"
    echo "  $0 add-app api.hdl.tg 10.10.1.24 8080"
    echo "  $0 add-app secure.hdl.tg 10.10.1.24 443 https"
    echo "  $0 add-ssh dev-ssh.hdl.tg 10.10.1.25"
    echo "  $0 add-ssh prod-ssh.hdl.tg 10.10.1.24 22"
    echo ""
}

#-------------------------------------------------------------------------------
# Ajouter un accès SSH (raccourci)
#-------------------------------------------------------------------------------
cmd_add_ssh() {
    local domain=$1
    local ip=$2
    local port=${3:-22}
    
    if [ -z "$domain" ] || [ -z "$ip" ]; then
        echo -e "${RED}Usage: $0 add-ssh <domain> <ip> [port]${NC}"
        echo ""
        echo "Exemples:"
        echo "  $0 add-ssh dev-ssh.hdl.tg 10.10.1.25"
        echo "  $0 add-ssh prod-ssh.hdl.tg 10.10.1.24 22"
        exit 1
    fi
    
    # Appeler add-app avec le protocole SSH
    cmd_add_app "$domain" "$ip" "$port" "ssh"
}

#-------------------------------------------------------------------------------
# Vérifier root
#-------------------------------------------------------------------------------
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}[ERREUR] Ce script doit être exécuté en tant que root${NC}"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# Démarrer le service
#-------------------------------------------------------------------------------
cmd_start() {
    echo -e "${YELLOW}Démarrage du service ${SERVICE_NAME}...${NC}"
    systemctl start "$SERVICE_NAME"
    sleep 2
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}✓ Service démarré${NC}"
        systemctl status "$SERVICE_NAME" --no-pager | head -10
    else
        echo -e "${RED}✗ Échec du démarrage${NC}"
        journalctl -u "$SERVICE_NAME" -n 15 --no-pager
    fi
}

#-------------------------------------------------------------------------------
# Arrêter le service
#-------------------------------------------------------------------------------
cmd_stop() {
    echo -e "${YELLOW}Arrêt du service ${SERVICE_NAME}...${NC}"
    systemctl stop "$SERVICE_NAME"
    echo -e "${GREEN}✓ Service arrêté${NC}"
}

#-------------------------------------------------------------------------------
# Redémarrer le service
#-------------------------------------------------------------------------------
cmd_restart() {
    echo -e "${YELLOW}Redémarrage du service ${SERVICE_NAME}...${NC}"
    systemctl restart "$SERVICE_NAME"
    sleep 2
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}✓ Service redémarré${NC}"
    else
        echo -e "${RED}✗ Échec${NC}"
        journalctl -u "$SERVICE_NAME" -n 15 --no-pager
    fi
}

#-------------------------------------------------------------------------------
# Activer au démarrage
#-------------------------------------------------------------------------------
cmd_enable() {
    echo -e "${YELLOW}Activation du service ${SERVICE_NAME} au démarrage...${NC}"
    systemctl enable "$SERVICE_NAME"
    if systemctl is-enabled --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}✓ Service activé au démarrage${NC}"
    else
        echo -e "${RED}✗ Échec de l'activation${NC}"
    fi
}

#-------------------------------------------------------------------------------
# Désactiver au démarrage
#-------------------------------------------------------------------------------
cmd_disable() {
    echo -e "${YELLOW}Désactivation du service ${SERVICE_NAME} au démarrage...${NC}"
    systemctl disable "$SERVICE_NAME"
    echo -e "${GREEN}✓ Service désactivé au démarrage${NC}"
}

#-------------------------------------------------------------------------------
# Statut du service
#-------------------------------------------------------------------------------
cmd_status() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}                    Statut Cloudflared                             ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}Service: ${SERVICE_NAME}${NC}"
    echo ""
    systemctl status "$SERVICE_NAME" --no-pager 2>/dev/null || echo "Service non configuré"
    echo ""
    echo -e "${BLUE}───────────────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}Tunnels:${NC}"
    cloudflared tunnel list 2>/dev/null || echo "Aucun tunnel"
}

#-------------------------------------------------------------------------------
# Afficher les logs
#-------------------------------------------------------------------------------
cmd_logs() {
    echo -e "${YELLOW}Logs ${SERVICE_NAME} (Ctrl+C pour quitter)...${NC}"
    journalctl -u "$SERVICE_NAME" -f
}

#-------------------------------------------------------------------------------
# Mode test
#-------------------------------------------------------------------------------
cmd_test() {
    echo -e "${YELLOW}Mode test (Ctrl+C pour arrêter)...${NC}"
    cloudflared tunnel --config "$CONFIG_FILE" run
}

#-------------------------------------------------------------------------------
# Lister les tunnels
#-------------------------------------------------------------------------------
cmd_list() {
    echo -e "${BLUE}Tunnels Cloudflare:${NC}"
    echo ""
    cloudflared tunnel list
}

#-------------------------------------------------------------------------------
# Informations détaillées
#-------------------------------------------------------------------------------
cmd_info() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}                 Informations du Tunnel                            ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ -f "$CONFIG_FILE" ]; then
        TUNNEL_ID=$(grep "^tunnel:" "$CONFIG_FILE" | awk '{print $2}')
        echo -e "Tunnel ID: ${GREEN}${TUNNEL_ID}${NC}"
        echo -e "Service:   ${GREEN}${SERVICE_NAME}${NC}"
        echo ""
        cmd_list_apps
    else
        echo -e "${RED}Configuration non trouvée${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}Service:${NC}"
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "  Status: ${GREEN}Actif${NC}"
    else
        echo -e "  Status: ${RED}Inactif${NC}"
    fi
    
    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        echo -e "  Démarrage auto: ${GREEN}Activé${NC}"
    else
        echo -e "  Démarrage auto: ${YELLOW}Désactivé${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}Commandes:${NC}"
    echo "  sudo systemctl start ${SERVICE_NAME}"
    echo "  sudo systemctl enable ${SERVICE_NAME}"
    echo "  sudo journalctl -u ${SERVICE_NAME} -f"
}

#-------------------------------------------------------------------------------
# Afficher la configuration
#-------------------------------------------------------------------------------
cmd_config() {
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "${BLUE}Configuration ($CONFIG_FILE):${NC}"
        echo ""
        cat "$CONFIG_FILE"
    else
        echo -e "${RED}Configuration non trouvée${NC}"
    fi
}

#-------------------------------------------------------------------------------
# Lister les applications
#-------------------------------------------------------------------------------
cmd_list_apps() {
    echo -e "${CYAN}Applications configurées:${NC}"
    echo ""
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Configuration non trouvée${NC}"
        return 1
    fi
    
    # Parser les applications du fichier config
    awk '
    /^  - hostname:/ { hostname=$3 }
    /^    service:/ { 
        if (hostname != "" && $2 !~ /http_status/) {
            printf "  %-30s → %s\n", hostname, $2
        }
        hostname=""
    }
    ' "$CONFIG_FILE"
}

#-------------------------------------------------------------------------------
# Ajouter une application (interactif ou paramètres)
#-------------------------------------------------------------------------------
cmd_add_app() {
    local domain=$1
    local ip=$2
    local port=$3
    local protocol=${4:-auto}
    
    # Mode interactif si pas de paramètres
    if [ -z "$domain" ]; then
        echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
        echo -e "${BLUE}                  Ajouter une application                          ${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
        echo ""
        
        read -p "Domaine (ex: api.hdl.tg): " domain
        
        # Détecter l'IP
        DETECTED_IP=$(hostname -I | awk '{print $1}')
        read -p "IP de l'application [$DETECTED_IP]: " ip
        ip=${ip:-$DETECTED_IP}
        
        read -p "Port: " port
        
        echo -e "${CYAN}Protocoles disponibles:${NC}"
        echo "  - http (défaut pour web)"
        echo "  - https"
        echo "  - ssh (pour accès SSH distant)"
        echo "  - tcp (pour autres services TCP)"
        echo "  - rdp (pour Remote Desktop)"
        echo "  - auto (détection automatique selon le port)"
        read -p "Protocole [auto]: " protocol
        protocol=${protocol:-auto}
        echo ""
    fi
    
    # Valider les entrées
    if [ -z "$domain" ] || [ -z "$ip" ] || [ -z "$port" ]; then
        echo -e "${RED}Paramètres manquants${NC}"
        echo "Usage: $0 add-app <domain> <ip> <port> [protocol]"
        echo ""
        echo "Protocoles: http, https, ssh, tcp, rdp, auto"
        echo ""
        echo "Exemples:"
        echo "  $0 add-app web.hdl.tg 10.10.1.25 8080"
        echo "  $0 add-app ssh.hdl.tg 10.10.1.25 22 ssh"
        echo "  $0 add-app secure.hdl.tg 10.10.1.25 443 https"
        exit 1
    fi
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Configuration non trouvée: $CONFIG_FILE${NC}"
        echo "Exécute d'abord setup-cloudflared.sh"
        exit 1
    fi
    
    # Vérifier si existe déjà
    if grep -q "hostname: ${domain}$" "$CONFIG_FILE"; then
        echo -e "${RED}L'application ${domain} existe déjà${NC}"
        exit 1
    fi
    
    # Auto-détection du protocole selon le port
    if [ "$protocol" = "auto" ]; then
        case $port in
            22)
                protocol="ssh"
                ;;
            443|8443)
                protocol="https"
                ;;
            3389)
                protocol="rdp"
                ;;
            3306|5432|6379|27017)
                protocol="tcp"
                ;;
            *)
                protocol="http"
                ;;
        esac
        echo -e "${CYAN}Protocole auto-détecté: ${protocol}${NC}"
    fi
    
    # Construire l'URL du service
    local service="${protocol}://${ip}:${port}"
    
    echo -e "${YELLOW}Ajout: ${domain} → ${service}${NC}"
    
    # Récupérer le nom du tunnel
    TUNNEL_NAME=$(cloudflared tunnel list 2>/dev/null | grep -v "ID" | head -1 | awk '{print $2}')
    
    # Lire les infos du tunnel
    local tunnel_id=$(grep "^tunnel:" "$CONFIG_FILE" | awk '{print $2}')
    local creds_file=$(grep "^credentials-file:" "$CONFIG_FILE" | awk '{print $2}')
    
    # Collecter les applications existantes
    local apps_data=$(mktemp)
    awk '
    /^  - hostname:/ { 
        in_app=1
        current_app=$0 "\n"
        next
    }
    /^  - service: http_status:404/ {
        in_app=0
        next
    }
    in_app && /^    / {
        current_app=current_app $0 "\n"
        next
    }
    in_app && (/^  -/ || /^  #/ || /^[^ ]/) {
        if (current_app != "") {
            printf "%s", current_app
        }
        in_app=0
        if (/^  - hostname:/) {
            in_app=1
            current_app=$0 "\n"
        }
    }
    END {
        if (in_app && current_app != "") {
            printf "%s", current_app
        }
    }
    ' "$CONFIG_FILE" > "$apps_data"
    
    # Recréer le fichier config proprement
    cat > "$CONFIG_FILE" << EOF
#===============================================================================
# Configuration Cloudflare Tunnel
# Mis à jour le: $(date)
#===============================================================================

tunnel: ${tunnel_id}
credentials-file: ${creds_file}

ingress:
EOF

    # Ajouter les applications existantes
    if [ -s "$apps_data" ]; then
        echo "" >> "$CONFIG_FILE"
        cat "$apps_data" >> "$CONFIG_FILE"
    fi
    
    # Ajouter la nouvelle application
    echo "" >> "$CONFIG_FILE"
    echo "  #-----------------------------------------------------------------------------" >> "$CONFIG_FILE"
    echo "  # ${domain} → ${service}" >> "$CONFIG_FILE"
    echo "  #-----------------------------------------------------------------------------" >> "$CONFIG_FILE"
    echo "  - hostname: ${domain}" >> "$CONFIG_FILE"
    echo "    service: ${service}" >> "$CONFIG_FILE"
    
    case $protocol in
        ssh|rdp|tcp)
            # Pas d'originRequest pour ces types
            ;;
        https)
            echo "    originRequest:" >> "$CONFIG_FILE"
            echo "      connectTimeout: 30s" >> "$CONFIG_FILE"
            echo "      noTLSVerify: true" >> "$CONFIG_FILE"
            ;;
        *)
            echo "    originRequest:" >> "$CONFIG_FILE"
            echo "      connectTimeout: 30s" >> "$CONFIG_FILE"
            ;;
    esac
    
    # Ajouter le catch-all à la fin
    echo "" >> "$CONFIG_FILE"
    echo "  #-----------------------------------------------------------------------------" >> "$CONFIG_FILE"
    echo "  # Catch-all (requis - toujours en dernier)" >> "$CONFIG_FILE"
    echo "  #-----------------------------------------------------------------------------" >> "$CONFIG_FILE"
    echo "  - service: http_status:404" >> "$CONFIG_FILE"
    
    # Nettoyer
    rm -f "$apps_data"
    
    echo -e "${GREEN}✓ Application ajoutée à la configuration${NC}"
    
    # Configurer le DNS
    if [ -n "$TUNNEL_NAME" ]; then
        echo -e "${YELLOW}Configuration DNS...${NC}"
        cloudflared tunnel route dns "$TUNNEL_NAME" "$domain" 2>/dev/null || {
            echo -e "${YELLOW}⚠ DNS existe peut-être déjà${NC}"
        }
        echo -e "${GREEN}✓ DNS configuré${NC}"
    fi
    
    echo ""
    
    # Instructions spécifiques pour SSH
    if [ "$protocol" = "ssh" ]; then
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}  Configuration SSH côté client                                    ${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "  ${YELLOW}1. Installer cloudflared sur ton PC:${NC}"
        echo "     brew install cloudflared  # Mac"
        echo "     # Ou télécharger depuis github.com/cloudflare/cloudflared"
        echo ""
        echo -e "  ${YELLOW}2. Ajouter à ~/.ssh/config:${NC}"
        echo ""
        echo "     Host ${domain}"
        echo "         HostName ${domain}"
        echo "         ProxyCommand cloudflared access ssh --hostname %h"
        echo "         User <ton_user>"
        echo ""
        echo -e "  ${YELLOW}3. Se connecter:${NC}"
        echo "     ssh ${domain}"
        echo ""
    fi
    
    echo -e "${CYAN}Redémarre le service pour appliquer:${NC}"
    echo "  sudo $0 restart"
}

#-------------------------------------------------------------------------------
# Supprimer une application
#-------------------------------------------------------------------------------
cmd_remove_app() {
    local domain=$1
    
    if [ -z "$domain" ]; then
        echo -e "${RED}Usage: $0 remove-app <domain>${NC}"
        exit 1
    fi
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Configuration non trouvée${NC}"
        exit 1
    fi
    
    if ! grep -q "hostname: ${domain}$" "$CONFIG_FILE"; then
        echo -e "${RED}Application ${domain} non trouvée${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}Suppression de ${domain}...${NC}"
    
    # Créer une sauvegarde
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    
    # Supprimer le bloc complet (commentaire + hostname + service + originRequest)
    # C'est un peu délicat avec sed, utilisons awk
    awk -v domain="$domain" '
    BEGIN { skip = 0; skip_count = 0 }
    /^  #-+$/ && !skip { 
        # Stocker la ligne de commentaire
        comment_line = $0
        getline
        if ($0 ~ "# " domain " ") {
            skip = 1
            skip_count = 0
            next
        } else {
            print comment_line
        }
    }
    skip && /^  #-+$/ { skip_count++ }
    skip && skip_count >= 1 && /^  - hostname:/ { skip = 0 }
    skip && /^  - hostname:/ && $0 ~ domain { skip = 1; next }
    skip && /^    service:/ { next }
    skip && /^    originRequest:/ { next }
    skip && /^      / { next }
    skip && /^  - hostname:/ { skip = 0 }
    !skip { print }
    ' "${CONFIG_FILE}.bak" > "$CONFIG_FILE"
    
    # Méthode alternative plus simple: supprimer les lignes contenant le domain
    # et les lignes service/originRequest qui suivent
    sed -i "/${domain}/,/^  - hostname:\|^  - service: http_status/{ /${domain}/d; /service:/d; /originRequest:/d; /connectTimeout:/d; /noTLSVerify:/d; }" "$CONFIG_FILE"
    
    echo -e "${GREEN}✓ Application supprimée${NC}"
    echo ""
    echo -e "${YELLOW}Notes:${NC}"
    echo "  - L'enregistrement DNS n'est pas supprimé automatiquement"
    echo "  - Supprime-le dans le dashboard Cloudflare si nécessaire"
    echo ""
    echo -e "${CYAN}Redémarre le service:${NC}"
    echo "  sudo $0 restart"
}

#-------------------------------------------------------------------------------
# Valider la configuration
#-------------------------------------------------------------------------------
cmd_validate() {
    echo -e "${YELLOW}Validation de la configuration...${NC}"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}✗ Configuration non trouvée${NC}"
        exit 1
    fi
    
    cloudflared tunnel --config "$CONFIG_FILE" ingress validate
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Configuration valide${NC}"
    else
        echo -e "${RED}✗ Configuration invalide${NC}"
        exit 1
    fi
}

#===============================================================================
# MAIN
#===============================================================================

case "${1:-help}" in
    start)
        check_root
        cmd_start
        ;;
    stop)
        check_root
        cmd_stop
        ;;
    restart)
        check_root
        cmd_restart
        ;;
    enable)
        check_root
        cmd_enable
        ;;
    disable)
        check_root
        cmd_disable
        ;;
    status)
        cmd_status
        ;;
    logs)
        cmd_logs
        ;;
    test)
        cmd_test
        ;;
    list)
        cmd_list
        ;;
    info)
        cmd_info
        ;;
    config)
        cmd_config
        ;;
    add-app)
        check_root
        cmd_add_app "$2" "$3" "$4" "$5"
        ;;
    add-ssh)
        check_root
        cmd_add_ssh "$2" "$3" "$4"
        ;;
    remove-app)
        check_root
        cmd_remove_app "$2"
        ;;
    list-apps)
        cmd_list_apps
        ;;
    validate)
        cmd_validate
        ;;
    help|--help|-h|*)
        show_help
        ;;
esac
