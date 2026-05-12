#!/bin/bash

#===============================================================================
#
#   CLOUDFLARE TUNNEL MANAGER - Script Interactif Complet
#   
#   Fonctionnalités:
#   - Installation/Désinstallation de cloudflared
#   - Gestion des tunnels et applications
#   - Configuration SSL Origin pour intranet
#   - Gestion ZTNA (Zero Trust Network Access)
#
#   Auteur: CNSS/HDL - Togo
#   Version: 2.0
#
#===============================================================================

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

# Configuration
CLOUDFLARED_DIR="/etc/cloudflared"
CLOUDFLARED_BIN="/usr/local/bin/cloudflared"
CERT_DIR="/etc/cloudflare-certs"
CONFIG_FILE="$CLOUDFLARED_DIR/config.yml"
CREDENTIALS_DIR="/root/.cloudflared"

# Variables Cloudflare API
CF_API_BASE="https://api.cloudflare.com/client/v4"
CF_CONFIG_FILE="$CLOUDFLARED_DIR/.cf_config"

#===============================================================================
# FONCTIONS UTILITAIRES
#===============================================================================

print_banner() {
    clear
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                           ║"
    echo "║     ██████╗██╗      ██████╗ ██╗   ██╗██████╗ ███████╗██╗      █████╗     ║"
    echo "║    ██╔════╝██║     ██╔═══██╗██║   ██║██╔══██╗██╔════╝██║     ██╔══██╗    ║"
    echo "║    ██║     ██║     ██║   ██║██║   ██║██║  ██║█████╗  ██║     ███████║    ║"
    echo "║    ██║     ██║     ██║   ██║██║   ██║██║  ██║██╔══╝  ██║     ██╔══██║    ║"
    echo "║    ╚██████╗███████╗╚██████╔╝╚██████╔╝██████╔╝██║     ███████╗██║  ██║    ║"
    echo "║     ╚═════╝╚══════╝ ╚═════╝  ╚═════╝ ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═╝    ║"
    echo "║                                                                           ║"
    echo "║                    TUNNEL MANAGER - Version 2.0                           ║"
    echo "║                         CNSS/HDL - Togo                                   ║"
    echo "║                                                                           ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_section() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}  ✓ $1${NC}"
}

print_error() {
    echo -e "${RED}  ✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}  ⚠ $1${NC}"
}

print_info() {
    echo -e "${CYAN}  ℹ $1${NC}"
}

press_enter() {
    echo ""
    read -p "  Appuie sur Entrée pour continuer..."
}

confirm() {
    read -p "  $1 (o/N): " response
    [[ "$response" =~ ^[Oo]$ ]]
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Ce script doit être exécuté en tant que root"
        echo "  Utilise: sudo $0"
        exit 1
    fi
}

check_dependencies() {
    local missing=()
    
    for cmd in curl jq openssl; do
        if ! command -v $cmd &> /dev/null; then
            missing+=($cmd)
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_warning "Installation des dépendances: ${missing[*]}"
        apt-get update -qq
        apt-get install -y -qq ${missing[*]}
    fi
}

load_cf_config() {
    if [ -f "$CF_CONFIG_FILE" ]; then
        source "$CF_CONFIG_FILE"
    fi
}

save_cf_config() {
    cat > "$CF_CONFIG_FILE" << EOF
CF_API_TOKEN="$CF_API_TOKEN"
CF_ZONE_ID="$CF_ZONE_ID"
CF_ACCOUNT_ID="$CF_ACCOUNT_ID"
CF_DOMAIN="$CF_DOMAIN"
EOF
    chmod 600 "$CF_CONFIG_FILE"
}

get_service_name() {
    if [ -f "$CLOUDFLARED_DIR/.service_name" ]; then
        cat "$CLOUDFLARED_DIR/.service_name"
    else
        local service=$(systemctl list-unit-files 2>/dev/null | grep "cloudflared-" | grep -v "@" | awk '{print $1}' | head -1 | sed 's/.service$//')
        echo "${service:-cloudflared}"
    fi
}

get_tunnel_name_from_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        return 1
    fi

    local tunnel_id
    tunnel_id=$(awk '/^tunnel:/ {print $2; exit}' "$CONFIG_FILE")

    if [ -z "$tunnel_id" ]; then
        return 1
    fi

    cloudflared tunnel list 2>/dev/null | awk -v id="$tunnel_id" '$1 == id {print $2; exit}'
}

backup_config() {
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    fi
}

extract_ingress_apps() {
    local source_file=$1

    awk '
    function flush_app() {
        if (in_app && current_app != "") {
            printf "%s", current_app
        }
        in_app = 0
        current_app = ""
    }

    /^  - hostname:/ {
        flush_app()
        in_app = 1
        current_app = $0 "\n"
        next
    }

    /^  - service: http_status:404/ {
        flush_app()
        next
    }

    /^  - / {
        flush_app()
        next
    }

    in_app && /^    / {
        current_app = current_app $0 "\n"
        next
    }

    END {
        flush_app()
    }
    ' "$source_file"
}

write_config_header() {
    local tunnel_id=$1
    local creds_file=$2

    cat > "$CONFIG_FILE" << EOF
#===============================================================================
# Configuration Cloudflare Tunnel
# Mis à jour le: $(date)
#===============================================================================

tunnel: ${tunnel_id}
credentials-file: ${creds_file}

ingress:
EOF
}

write_ingress_catch_all() {
    cat >> "$CONFIG_FILE" << EOF

  #-----------------------------------------------------------------------------
  # Catch-all (requis - toujours en dernier)
  #-----------------------------------------------------------------------------
  - service: http_status:404
EOF
}

#===============================================================================
# MENU PRINCIPAL
#===============================================================================

main_menu() {
    while true; do
        print_banner
        echo -e "${WHITE}  MENU PRINCIPAL${NC}"
        echo ""
        echo -e "  ${GREEN}1)${NC} 🚀 Installation & Configuration Initiale"
        echo -e "  ${GREEN}2)${NC} 📦 Gestion des Applications"
        echo -e "  ${GREEN}3)${NC} 🔐 Configuration SSL (Certificats Origin)"
        echo -e "  ${GREEN}4)${NC} 🛡️  Configuration ZTNA (Zero Trust)"
        echo -e "  ${GREEN}5)${NC} ⚙️  Gestion du Service"
        echo -e "  ${GREEN}6)${NC} 📊 Informations & Diagnostics"
        echo -e "  ${GREEN}7)${NC} 🗑️  Désinstallation"
        echo ""
        echo -e "  ${RED}0)${NC} Quitter"
        echo ""
        read -p "  Choix: " choice
        
        case $choice in
            1) menu_installation ;;
            2) menu_applications ;;
            3) menu_ssl ;;
            4) menu_ztna ;;
            5) menu_service ;;
            6) menu_diagnostics ;;
            7) menu_uninstall ;;
            0) echo ""; print_info "Au revoir!"; exit 0 ;;
            *) print_error "Choix invalide" ;;
        esac
    done
}

#===============================================================================
# MENU INSTALLATION
#===============================================================================

menu_installation() {
    while true; do
        print_banner
        print_section "🚀 INSTALLATION & CONFIGURATION"
        
        # Vérifier l'état actuel
        local cf_installed="Non"
        local tunnel_configured="Non"
        local service_status="Non installé"
        
        if command -v cloudflared &> /dev/null; then
            cf_installed="Oui ($(cloudflared --version 2>/dev/null | head -1 | awk '{print $2}'))"
        fi
        
        if [ -f "$CONFIG_FILE" ]; then
            tunnel_configured="Oui"
        fi
        
        local svc=$(get_service_name)
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            service_status="${GREEN}Actif${NC}"
        elif systemctl is-enabled --quiet "$svc" 2>/dev/null; then
            service_status="${YELLOW}Inactif${NC}"
        fi
        
        echo -e "  ${CYAN}État actuel:${NC}"
        echo -e "    Cloudflared installé: $cf_installed"
        echo -e "    Tunnel configuré: $tunnel_configured"
        echo -e "    Service: $service_status"
        echo ""
        echo -e "  ${GREEN}1)${NC} Installer cloudflared"
        echo -e "  ${GREEN}2)${NC} Configurer les credentials Cloudflare (API)"
        echo -e "  ${GREEN}3)${NC} Créer un nouveau tunnel"
        echo -e "  ${GREEN}4)${NC} Installation complète (tout-en-un)"
        echo -e "  ${GREEN}5)${NC} Mettre à jour cloudflared"
        echo ""
        echo -e "  ${RED}0)${NC} Retour"
        echo ""
        read -p "  Choix: " choice
        
        case $choice in
            1) install_cloudflared ;;
            2) configure_credentials ;;
            3) create_tunnel ;;
            4) full_installation ;;
            5) update_cloudflared ;;
            0) return ;;
            *) print_error "Choix invalide" ;;
        esac
    done
}

install_cloudflared() {
    print_section "Installation de cloudflared"
    
    if command -v cloudflared &> /dev/null; then
        print_warning "cloudflared est déjà installé"
        cloudflared --version
        if ! confirm "Réinstaller?"; then
            return
        fi
    fi
    
    # Détecter l'architecture
    local arch=$(uname -m)
    local cf_arch=""
    
    case $arch in
        x86_64) cf_arch="amd64" ;;
        aarch64|arm64) cf_arch="arm64" ;;
        armv7l) cf_arch="arm" ;;
        *) print_error "Architecture non supportée: $arch"; return ;;
    esac
    
    print_info "Téléchargement de cloudflared ($cf_arch)..."
    
    local url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cf_arch}"
    
    curl -L -o /tmp/cloudflared "$url" --progress-bar
    mv /tmp/cloudflared "$CLOUDFLARED_BIN"
    chmod +x "$CLOUDFLARED_BIN"
    
    mkdir -p "$CLOUDFLARED_DIR"
    mkdir -p "$CREDENTIALS_DIR"
    
    if cloudflared --version &> /dev/null; then
        print_success "cloudflared installé avec succès"
        cloudflared --version
    else
        print_error "Échec de l'installation"
    fi
    
    press_enter
}

configure_credentials() {
    print_section "Configuration des credentials Cloudflare"
    
    load_cf_config
    
    echo -e "  ${CYAN}Les informations suivantes sont nécessaires:${NC}"
    echo ""
    echo "  1. API Token - Créer sur: https://dash.cloudflare.com/profile/api-tokens"
    echo "     Permissions requises:"
    echo "       - Zone > DNS > Edit"
    echo "       - Zone > SSL and Certificates > Edit"
    echo "       - Account > Cloudflare Tunnel > Edit"
    echo "       - Account > Access: Apps and Policies > Edit"
    echo ""
    echo "  2. Zone ID - Dashboard > Votre domaine > Overview (colonne droite)"
    echo ""
    echo "  3. Account ID - Dashboard > Votre domaine > Overview (colonne droite)"
    echo ""
    
    # API Token
    if [ -n "$CF_API_TOKEN" ]; then
        echo -e "  API Token actuel: ${GREEN}Configuré${NC}"
        if ! confirm "Modifier?"; then
            echo ""
        else
            read -sp "  Nouveau API Token: " CF_API_TOKEN
            echo ""
        fi
    else
        read -sp "  API Token: " CF_API_TOKEN
        echo ""
    fi
    
    # Zone ID
    read -p "  Zone ID [$CF_ZONE_ID]: " input
    CF_ZONE_ID=${input:-$CF_ZONE_ID}
    
    # Account ID
    read -p "  Account ID [$CF_ACCOUNT_ID]: " input
    CF_ACCOUNT_ID=${input:-$CF_ACCOUNT_ID}
    
    # Domaine
    read -p "  Domaine principal [$CF_DOMAIN]: " input
    CF_DOMAIN=${input:-$CF_DOMAIN}
    
    # Tester la connexion
    echo ""
    print_info "Test de la connexion API..."
    
    local response=$(curl -s -X GET "$CF_API_BASE/zones/$CF_ZONE_ID" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json")
    
    local success=$(echo "$response" | jq -r '.success')
    
    if [ "$success" = "true" ]; then
        local zone_name=$(echo "$response" | jq -r '.result.name')
        print_success "Connexion réussie à la zone: $zone_name"
        save_cf_config
        print_success "Configuration sauvegardée"
    else
        print_error "Échec de la connexion API"
        echo "$response" | jq -r '.errors[]?.message' 2>/dev/null
    fi
    
    press_enter
}

create_tunnel() {
    print_section "Création d'un nouveau tunnel"
    
    if ! command -v cloudflared &> /dev/null; then
        print_error "cloudflared n'est pas installé"
        press_enter
        return
    fi
    
    # Vérifier l'authentification
    if [ ! -f "$CREDENTIALS_DIR/cert.pem" ]; then
        print_info "Authentification Cloudflare requise"
        echo ""
        echo -e "  ${YELLOW}Une URL va s'afficher. Copie-la et ouvre-la dans ton navigateur.${NC}"
        echo ""
        press_enter
        
        cloudflared tunnel login
        
        if [ ! -f "$CREDENTIALS_DIR/cert.pem" ]; then
            print_error "Authentification échouée"
            press_enter
            return
        fi
        print_success "Authentification réussie"
    fi
    
    # Lister les tunnels existants
    echo ""
    print_info "Tunnels existants:"
    cloudflared tunnel list 2>/dev/null || echo "  Aucun"
    echo ""
    
    # Nom du tunnel
    read -p "  Nom du nouveau tunnel: " tunnel_name
    
    if [ -z "$tunnel_name" ]; then
        print_error "Nom requis"
        press_enter
        return
    fi
    
    # Vérifier si existe déjà
    if cloudflared tunnel list 2>/dev/null | grep -qw "$tunnel_name"; then
        print_warning "Le tunnel '$tunnel_name' existe déjà"
        if ! confirm "Utiliser ce tunnel existant?"; then
            press_enter
            return
        fi
    else
        # Créer le tunnel
        print_info "Création du tunnel..."
        cloudflared tunnel create "$tunnel_name"
    fi
    
    # Récupérer l'ID
    local tunnel_id=$(cloudflared tunnel list | grep -w "$tunnel_name" | awk '{print $1}')
    
    if [ -z "$tunnel_id" ]; then
        print_error "Impossible de récupérer l'ID du tunnel"
        press_enter
        return
    fi
    
    print_success "Tunnel créé: $tunnel_name ($tunnel_id)"
    
    # Copier les credentials
    if [ -f "$CREDENTIALS_DIR/${tunnel_id}.json" ]; then
        cp "$CREDENTIALS_DIR/${tunnel_id}.json" "$CLOUDFLARED_DIR/"
    fi
    
    if [ -f "$CONFIG_FILE" ]; then
        print_warning "Une configuration existe déjà: $CONFIG_FILE"
        if ! confirm "La remplacer par une configuration vide pour ce tunnel?"; then
            print_info "Configuration existante conservée"
            echo "cloudflared-${tunnel_name}" > "$CLOUDFLARED_DIR/.service_name"
            create_systemd_service "$tunnel_name"
            press_enter
            return
        fi
        backup_config
        print_info "Sauvegarde créée: ${CONFIG_FILE}.bak"
    fi

    # Créer la config de base
    cat > "$CONFIG_FILE" << EOF
#===============================================================================
# Configuration Cloudflare Tunnel
# Tunnel: ${tunnel_name}
# Créé le: $(date)
#===============================================================================

tunnel: ${tunnel_id}
credentials-file: ${CLOUDFLARED_DIR}/${tunnel_id}.json

# Logging
# loglevel: info

# Métriques (décommenter pour activer)
# metrics: 0.0.0.0:2000

ingress:
  #-----------------------------------------------------------------------------
  # Ajouter vos applications ci-dessous
  #-----------------------------------------------------------------------------

  #-----------------------------------------------------------------------------
  # Catch-all (requis - toujours en dernier)
  #-----------------------------------------------------------------------------
  - service: http_status:404
EOF

    print_success "Configuration créée: $CONFIG_FILE"
    
    # Sauvegarder le nom du service
    echo "cloudflared-${tunnel_name}" > "$CLOUDFLARED_DIR/.service_name"
    
    # Créer le service systemd
    create_systemd_service "$tunnel_name"
    
    press_enter
}

create_systemd_service() {
    local tunnel_name=$1
    local service_name="cloudflared-${tunnel_name}"
    local service_file="/etc/systemd/system/${service_name}.service"
    
    cat > "$service_file" << EOF
[Unit]
Description=Cloudflare Tunnel - ${tunnel_name}
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=${CLOUDFLARED_BIN} tunnel --config ${CONFIG_FILE} run
Restart=on-failure
RestartSec=5
TimeoutStartSec=0

StandardOutput=journal
StandardError=journal
SyslogIdentifier=${service_name}

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    print_success "Service créé: ${service_name}.service"
}

full_installation() {
    print_section "Installation complète"
    
    echo -e "  Cette option va:"
    echo "    1. Installer cloudflared"
    echo "    2. Configurer les credentials API"
    echo "    3. Authentifier avec Cloudflare"
    echo "    4. Créer un nouveau tunnel"
    echo "    5. Configurer et démarrer le service"
    echo ""
    
    if ! confirm "Continuer?"; then
        return
    fi
    
    # Étape 1: Installer cloudflared
    install_cloudflared
    
    # Étape 2: Configurer credentials
    configure_credentials
    
    # Étape 3 & 4: Créer tunnel (inclut l'authentification)
    create_tunnel
    
    # Étape 5: Démarrer le service
    local svc=$(get_service_name)
    print_info "Démarrage du service..."
    systemctl enable "$svc"
    systemctl start "$svc"
    
    sleep 3
    
    if systemctl is-active --quiet "$svc"; then
        print_success "Service démarré avec succès"
    else
        print_error "Échec du démarrage"
        journalctl -u "$svc" -n 10 --no-pager
    fi
    
    press_enter
}

update_cloudflared() {
    print_section "Mise à jour de cloudflared"
    
    if ! command -v cloudflared &> /dev/null; then
        print_error "cloudflared n'est pas installé"
        press_enter
        return
    fi
    
    local current=$(cloudflared --version 2>/dev/null | head -1)
    print_info "Version actuelle: $current"
    
    print_info "Téléchargement de la dernière version..."
    
    local arch=$(uname -m)
    local cf_arch=""
    
    case $arch in
        x86_64) cf_arch="amd64" ;;
        aarch64|arm64) cf_arch="arm64" ;;
        armv7l) cf_arch="arm" ;;
    esac
    
    local url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cf_arch}"
    
    # Arrêter le service
    local svc=$(get_service_name)
    systemctl stop "$svc" 2>/dev/null || true
    
    curl -L -o /tmp/cloudflared "$url" --progress-bar
    mv /tmp/cloudflared "$CLOUDFLARED_BIN"
    chmod +x "$CLOUDFLARED_BIN"
    
    local new_version=$(cloudflared --version 2>/dev/null | head -1)
    print_success "Nouvelle version: $new_version"
    
    # Redémarrer le service
    systemctl start "$svc" 2>/dev/null || true
    
    press_enter
}

#===============================================================================
# MENU APPLICATIONS
#===============================================================================

menu_applications() {
    while true; do
        print_banner
        print_section "📦 GESTION DES APPLICATIONS"
        
        echo -e "  ${GREEN}1)${NC} Lister les applications configurées"
        echo -e "  ${GREEN}2)${NC} Ajouter une application WEB (HTTP/HTTPS)"
        echo -e "  ${GREEN}3)${NC} Ajouter un accès SSH"
        echo -e "  ${GREEN}4)${NC} Ajouter un accès RDP"
        echo -e "  ${GREEN}5)${NC} Ajouter un service TCP personnalisé"
        echo -e "  ${GREEN}6)${NC} Modifier une application"
        echo -e "  ${GREEN}7)${NC} Supprimer une application"
        echo -e "  ${GREEN}8)${NC} Éditer la configuration manuellement"
        echo ""
        echo -e "  ${RED}0)${NC} Retour"
        echo ""
        read -p "  Choix: " choice
        
        case $choice in
            1) list_applications ;;
            2) add_web_application ;;
            3) add_ssh_application ;;
            4) add_rdp_application ;;
            5) add_tcp_application ;;
            6) modify_application ;;
            7) remove_application ;;
            8) edit_config ;;
            0) return ;;
            *) print_error "Choix invalide" ;;
        esac
    done
}

list_applications() {
    print_section "Applications configurées"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Aucune configuration trouvée"
        press_enter
        return
    fi
    
    echo -e "  ${CYAN}Domaine                              Service${NC}"
    echo -e "  ${CYAN}────────────────────────────────────────────────────────────────${NC}"
    
    awk '
    /^  - hostname:/ { hostname=$3 }
    /^    service:/ { 
        if (hostname != "" && $2 !~ /http_status/) {
            printf "  %-35s → %s\n", hostname, $2
        }
        hostname=""
    }
    ' "$CONFIG_FILE"
    
    echo ""
    press_enter
}

add_web_application() {
    print_section "Ajouter une application WEB"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Aucun tunnel configuré"
        press_enter
        return
    fi
    
    load_cf_config
    
    echo -e "  ${CYAN}Configuration de l'application:${NC}"
    echo ""
    
    # Domaine
    read -p "  Sous-domaine (ex: app, test, api): " subdomain
    local domain="${subdomain}.${CF_DOMAIN}"
    read -p "  Domaine complet [$domain]: " input
    domain=${input:-$domain}
    
    # IP
    echo ""
    echo -e "  ${CYAN}Exemples d'IPs:${NC}"
    echo "    - 10.10.1.25 (réseau interne)"
    echo "    - 172.30.0.104 (Docker)"
    echo "    - 192.168.1.34 (LAN)"
    echo "    - localhost ou 127.0.0.1 (local)"
    echo ""
    read -p "  IP de l'application: " ip
    
    # Port
    read -p "  Port: " port
    
    # Protocole
    echo ""
    echo "  Protocole:"
    echo "    1) HTTP (défaut)"
    echo "    2) HTTPS"
    read -p "  Choix [1]: " proto_choice
    
    local protocol="http"
    local no_tls="false"
    if [ "$proto_choice" = "2" ]; then
        protocol="https"
        no_tls="true"
    fi
    
    local service="${protocol}://${ip}:${port}"
    
    # Résumé
    echo ""
    echo -e "  ${CYAN}Résumé:${NC}"
    echo "    Domaine: https://${domain}"
    echo "    Service: ${service}"
    echo ""
    
    if ! confirm "Confirmer l'ajout?"; then
        return
    fi
    
    # Ajouter à la config
    add_ingress_entry "$domain" "$service" "$no_tls" || {
        press_enter
        return
    }
    
    # Configurer le DNS
    configure_dns "$domain"
    
    # Redémarrer
    restart_tunnel
    
    print_success "Application ajoutée: https://${domain}"
    press_enter
}

add_ssh_application() {
    print_section "Ajouter un accès SSH"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Aucun tunnel configuré"
        press_enter
        return
    fi
    
    load_cf_config
    
    echo -e "  ${CYAN}Configuration SSH:${NC}"
    echo ""
    
    # Domaine
    read -p "  Nom du serveur (ex: dev-server, prod-db): " server_name
    local domain="${server_name}-ssh.${CF_DOMAIN}"
    read -p "  Domaine complet [$domain]: " input
    domain=${input:-$domain}
    
    # IP
    echo ""
    read -p "  IP du serveur SSH: " ip
    
    # Port
    read -p "  Port SSH [22]: " port
    port=${port:-22}
    
    local service="ssh://${ip}:${port}"
    
    # Résumé
    echo ""
    echo -e "  ${CYAN}Résumé:${NC}"
    echo "    Domaine: ${domain}"
    echo "    Service: ${service}"
    echo ""
    
    if ! confirm "Confirmer l'ajout?"; then
        return
    fi
    
    # Ajouter à la config
    add_ingress_entry "$domain" "$service" "false" "ssh" || {
        press_enter
        return
    }
    
    # Configurer le DNS
    configure_dns "$domain"
    
    # Redémarrer
    restart_tunnel
    
    print_success "Accès SSH ajouté"
    echo ""
    echo -e "  ${CYAN}Configuration côté client:${NC}"
    echo ""
    echo "  Ajouter à ~/.ssh/config:"
    echo ""
    echo "    Host ${server_name}"
    echo "        HostName ${domain}"
    echo "        User <votre_user>"
    echo "        ProxyCommand cloudflared access ssh --hostname %h"
    echo ""
    
    press_enter
}

add_rdp_application() {
    print_section "Ajouter un accès RDP"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Aucun tunnel configuré"
        press_enter
        return
    fi
    
    load_cf_config
    
    echo -e "  ${CYAN}Configuration RDP:${NC}"
    echo ""
    
    # Domaine
    read -p "  Nom du serveur (ex: windows-server, desktop): " server_name
    local domain="${server_name}-rdp.${CF_DOMAIN}"
    read -p "  Domaine complet [$domain]: " input
    domain=${input:-$domain}
    
    # IP
    read -p "  IP du serveur RDP: " ip
    
    # Port
    read -p "  Port RDP [3389]: " port
    port=${port:-3389}
    
    local service="rdp://${ip}:${port}"
    
    # Résumé
    echo ""
    echo -e "  ${CYAN}Résumé:${NC}"
    echo "    Domaine: ${domain}"
    echo "    Service: ${service}"
    echo ""
    
    if ! confirm "Confirmer l'ajout?"; then
        return
    fi
    
    # Ajouter à la config
    add_ingress_entry "$domain" "$service" "false" "rdp" || {
        press_enter
        return
    }
    
    # Configurer le DNS
    configure_dns "$domain"
    
    # Redémarrer
    restart_tunnel
    
    print_success "Accès RDP ajouté: ${domain}"
    print_info "RDP nécessite un client Cloudflare Access côté utilisateur, ce n'est pas une application web ouvrable directement dans le navigateur."
    press_enter
}

add_tcp_application() {
    print_section "Ajouter un service TCP"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Aucun tunnel configuré"
        press_enter
        return
    fi
    
    load_cf_config
    
    echo -e "  ${CYAN}Services TCP courants:${NC}"
    echo "    - MySQL: 3306"
    echo "    - PostgreSQL: 5432"
    echo "    - Redis: 6379"
    echo "    - MongoDB: 27017"
    echo ""
    
    # Domaine
    read -p "  Nom du service (ex: mysql-prod, redis-cache): " service_name
    local domain="${service_name}.${CF_DOMAIN}"
    read -p "  Domaine complet [$domain]: " input
    domain=${input:-$domain}
    
    # IP
    read -p "  IP du serveur: " ip
    
    # Port
    read -p "  Port TCP: " port
    
    local service="tcp://${ip}:${port}"
    
    # Résumé
    echo ""
    echo -e "  ${CYAN}Résumé:${NC}"
    echo "    Domaine: ${domain}"
    echo "    Service: ${service}"
    echo ""
    
    if ! confirm "Confirmer l'ajout?"; then
        return
    fi
    
    # Ajouter à la config
    add_ingress_entry "$domain" "$service" "false" "tcp" || {
        press_enter
        return
    }
    
    # Configurer le DNS
    configure_dns "$domain"
    
    # Redémarrer
    restart_tunnel
    
    print_success "Service TCP ajouté: ${domain}"
    print_info "Les services TCP nécessitent un client Cloudflare Access côté utilisateur, ce n'est pas une URL web classique."
    press_enter
}

add_ingress_entry() {
    local hostname=$1
    local service=$2
    local no_tls=${3:-false}
    local type=${4:-web}
    
    # Lire les infos du tunnel
    local tunnel_id=$(grep "^tunnel:" "$CONFIG_FILE" | awk '{print $2}')
    local creds_file=$(grep "^credentials-file:" "$CONFIG_FILE" | awk '{print $2}')

    if awk -v host="$hostname" '/^  - hostname:/ && $3 == host { found = 1 } END { exit !found }' "$CONFIG_FILE"; then
        print_error "L'application existe déjà: ${hostname}"
        return 1
    fi

    backup_config
    
    # Collecter les applications existantes (sauf catch-all)
    local apps_data=$(mktemp)
    extract_ingress_apps "$CONFIG_FILE" > "$apps_data"
    
    # Créer le nouveau fichier config
    write_config_header "$tunnel_id" "$creds_file"

    # Ajouter les applications existantes
    if [ -s "$apps_data" ]; then
        echo "" >> "$CONFIG_FILE"
        cat "$apps_data" >> "$CONFIG_FILE"
    fi
    
    # Ajouter la nouvelle application
    echo "" >> "$CONFIG_FILE"
    echo "  #-----------------------------------------------------------------------------" >> "$CONFIG_FILE"
    echo "  # ${hostname} → ${service}" >> "$CONFIG_FILE"
    echo "  #-----------------------------------------------------------------------------" >> "$CONFIG_FILE"
    echo "  - hostname: ${hostname}" >> "$CONFIG_FILE"
    echo "    service: ${service}" >> "$CONFIG_FILE"
    
    case $type in
        ssh|rdp|tcp)
            # Pas d'originRequest pour ces types
            ;;
        *)
            echo "    originRequest:" >> "$CONFIG_FILE"
            echo "      connectTimeout: 30s" >> "$CONFIG_FILE"
            if [ "$no_tls" = "true" ]; then
                echo "      noTLSVerify: true" >> "$CONFIG_FILE"
            fi
            ;;
    esac
    
    # Ajouter le catch-all à la fin
    write_ingress_catch_all
    
    # Nettoyer
    rm -f "$apps_data"
}

configure_dns() {
    local hostname=$1
    
    print_info "Configuration DNS pour ${hostname}..."
    
    local tunnel_name
    tunnel_name=$(get_tunnel_name_from_config)
    
    if [ -n "$tunnel_name" ]; then
        cloudflared tunnel route dns "$tunnel_name" "$hostname" 2>/dev/null && \
            print_success "DNS configuré" || \
            print_warning "DNS existe peut-être déjà"
    else
        print_warning "Nom du tunnel introuvable, DNS non configuré automatiquement"
    fi
}

modify_application() {
    print_section "Modifier une application"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Aucune configuration trouvée"
        press_enter
        return
    fi
    
    # Lister les applications dans un tableau
    echo -e "  ${CYAN}Applications configurées:${NC}"
    echo ""
    
    local -a apps_array=()
    local -a services_array=()
    
    while IFS= read -r line; do
        local app=$(echo "$line" | awk '{print $1}')
        local svc=$(echo "$line" | awk '{print $2}')
        [ -n "$app" ] && apps_array+=("$app") && services_array+=("$svc")
    done < <(awk '
    /^  - hostname:/ { hostname=$3 }
    /^    service:/ { 
        if (hostname != "" && $2 !~ /http_status/) {
            print hostname, $2
        }
        hostname=""
    }
    ' "$CONFIG_FILE")
    
    if [ ${#apps_array[@]} -eq 0 ]; then
        print_warning "Aucune application configurée"
        press_enter
        return
    fi
    
    local i=1
    for idx in "${!apps_array[@]}"; do
        echo "    $i) ${apps_array[$idx]} → ${services_array[$idx]}"
        i=$((i + 1))
    done
    
    echo ""
    read -p "  Numéro ou domaine à modifier: " input
    
    if [ -z "$input" ]; then
        return
    fi
    
    local domain=""
    local current_service=""
    local selected_idx=0
    
    # Vérifier si c'est un numéro ou un domaine
    if [[ "$input" =~ ^[0-9]+$ ]]; then
        if [ "$input" -ge 1 ] && [ "$input" -le ${#apps_array[@]} ]; then
            selected_idx=$((input-1))
            domain="${apps_array[$selected_idx]}"
            current_service="${services_array[$selected_idx]}"
        else
            print_error "Numéro invalide"
            press_enter
            return
        fi
    else
        domain="$input"
        for idx in "${!apps_array[@]}"; do
            if [ "${apps_array[$idx]}" = "$domain" ]; then
                selected_idx=$idx
                current_service="${services_array[$idx]}"
                break
            fi
        done
    fi
    
    if [ -z "$current_service" ]; then
        print_error "Application non trouvée: ${domain}"
        press_enter
        return
    fi
    
    # Extraire les composants du service actuel
    local current_protocol=$(echo "$current_service" | sed -E 's|^([^:]+)://.*|\1|')
    local current_ip=$(echo "$current_service" | sed -E 's|^[^:]+://([^:]+):.*|\1|')
    local current_port=$(echo "$current_service" | sed -E 's|^[^:]+://[^:]+:([0-9]+).*|\1|')
    
    echo ""
    echo -e "  ${CYAN}Configuration actuelle:${NC}"
    echo "    Domaine:   ${domain}"
    echo "    Protocole: ${current_protocol}"
    echo "    IP:        ${current_ip}"
    echo "    Port:      ${current_port}"
    echo ""
    echo -e "  ${CYAN}Nouvelles valeurs (Entrée pour garder l'actuelle):${NC}"
    echo ""
    
    # Nouveau protocole
    echo "  Protocoles: http, https, ssh, tcp, rdp"
    read -p "  Protocole [$current_protocol]: " new_protocol
    new_protocol=${new_protocol:-$current_protocol}
    
    # Nouvelle IP
    read -p "  IP [$current_ip]: " new_ip
    new_ip=${new_ip:-$current_ip}
    
    # Nouveau port
    read -p "  Port [$current_port]: " new_port
    new_port=${new_port:-$current_port}
    
    local new_service="${new_protocol}://${new_ip}:${new_port}"
    
    echo ""
    echo -e "  ${CYAN}Résumé des modifications:${NC}"
    echo "    Ancien: ${current_service}"
    echo "    Nouveau: ${new_service}"
    echo ""
    
    if ! confirm "Appliquer les modifications?"; then
        return
    fi
    
    # Lire les infos du tunnel
    local tunnel_id=$(grep "^tunnel:" "$CONFIG_FILE" | awk '{print $2}')
    local creds_file=$(grep "^credentials-file:" "$CONFIG_FILE" | awk '{print $2}')
    
    backup_config

    # Collecter toutes les applications avec modification
    local apps_data=$(mktemp)
    awk -v modify_domain="$domain" -v new_service="$new_service" '
    function flush_app() {
        if (in_app && current_app != "") {
            printf "%s", current_app
        }
        in_app = 0
        current_app = ""
        modifying = 0
    }

    /^  - hostname:/ {
        flush_app()
        current_hostname = $3
        in_app = 1
        modifying = (current_hostname == modify_domain)
        current_app = "  - hostname: " current_hostname "\n"
        if (modifying) {
            current_app = current_app "    service: " new_service "\n"
        }
        next
    }

    /^  - service: http_status:404/ {
        flush_app()
        next
    }

    /^  - / {
        flush_app()
        next
    }

    in_app && modifying && /^    service:/ { next }
    in_app && modifying && /^    originRequest:/ { skip_origin = 1; next }
    in_app && modifying && skip_origin && /^      / { next }
    in_app && modifying { skip_origin = 0 }

    in_app && /^    / {
        current_app = current_app $0 "\n"
        next
    }

    END {
        flush_app()
    }
    ' "$CONFIG_FILE" > "$apps_data"
    
    # Recréer le fichier config proprement
    write_config_header "$tunnel_id" "$creds_file"

    # Ajouter les applications
    if [ -s "$apps_data" ]; then
        echo "" >> "$CONFIG_FILE"
        cat "$apps_data" >> "$CONFIG_FILE"
    fi
    
    # Ajouter originRequest si nécessaire pour l'app modifiée
    # On va reconstruire proprement
    local final_config=$(mktemp)
    cp "$CONFIG_FILE" "$final_config"
    
    # Recréer avec originRequest approprié
    write_config_header "$tunnel_id" "$creds_file"

    # Parcourir les apps et ajouter avec bon format
    while IFS= read -r line; do
        local app_domain=$(echo "$line" | awk '{print $1}')
        local app_service=$(echo "$line" | awk '{print $2}')
        local app_protocol=$(echo "$app_service" | sed -E 's|^([^:]+)://.*|\1|')
        
        echo "" >> "$CONFIG_FILE"
        echo "  #-----------------------------------------------------------------------------" >> "$CONFIG_FILE"
        echo "  # ${app_domain} → ${app_service}" >> "$CONFIG_FILE"
        echo "  #-----------------------------------------------------------------------------" >> "$CONFIG_FILE"
        echo "  - hostname: ${app_domain}" >> "$CONFIG_FILE"
        echo "    service: ${app_service}" >> "$CONFIG_FILE"
        
        case $app_protocol in
            ssh|rdp|tcp)
                # Pas d'originRequest
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
    done < <(awk '
    /^  - hostname:/ { hostname=$3 }
    /^    service:/ { 
        if (hostname != "" && $2 !~ /http_status/) {
            print hostname, $2
        }
        hostname=""
    }
    ' "$final_config")
    
    # Ajouter le catch-all
    write_ingress_catch_all
    
    # Nettoyer
    rm -f "$apps_data" "$final_config"
    
    print_success "Application ${domain} modifiée"
    
    restart_tunnel
    
    press_enter
}

remove_application() {
    print_section "Supprimer une application"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Aucune configuration trouvée"
        press_enter
        return
    fi
    
    # Lister les applications dans un tableau
    echo -e "  ${CYAN}Applications configurées:${NC}"
    echo ""
    
    local -a apps_array=()
    while IFS= read -r app; do
        [ -n "$app" ] && apps_array+=("$app")
    done < <(awk '/^  - hostname:/ { print $3 }' "$CONFIG_FILE" | grep -v "^$")
    
    if [ ${#apps_array[@]} -eq 0 ]; then
        print_warning "Aucune application configurée"
        press_enter
        return
    fi
    
    local i=1
    for app in "${apps_array[@]}"; do
        echo "    $i) $app"
        i=$((i + 1))
    done
    
    echo ""
    read -p "  Numéro ou domaine à supprimer: " input
    
    if [ -z "$input" ]; then
        return
    fi
    
    local domain=""
    
    # Vérifier si c'est un numéro ou un domaine
    if [[ "$input" =~ ^[0-9]+$ ]]; then
        # C'est un numéro
        if [ "$input" -ge 1 ] && [ "$input" -le ${#apps_array[@]} ]; then
            domain="${apps_array[$((input-1))]}"
        else
            print_error "Numéro invalide"
            press_enter
            return
        fi
    else
        # C'est un domaine
        domain="$input"
    fi
    
    if ! awk -v host="$domain" '/^  - hostname:/ && $3 == host { found = 1 } END { exit !found }' "$CONFIG_FILE"; then
        print_error "Application non trouvée: ${domain}"
        press_enter
        return
    fi
    
    echo ""
    echo -e "  ${YELLOW}Application sélectionnée: ${domain}${NC}"
    
    if ! confirm "Supprimer ${domain}?"; then
        return
    fi
    
    # Créer une sauvegarde
    backup_config
    
    # Lire les infos du tunnel
    local tunnel_id=$(grep "^tunnel:" "$CONFIG_FILE" | awk '{print $2}')
    local creds_file=$(grep "^credentials-file:" "$CONFIG_FILE" | awk '{print $2}')
    
    # Collecter les applications existantes SAUF celle à supprimer
    local apps_data=$(mktemp)
    awk -v exclude="$domain" '
    function flush_app() {
        if (current_app != "" && current_hostname != exclude) {
            printf "%s", current_app
        }
        in_app = 0
        current_app = ""
        current_hostname = ""
    }

    /^  - hostname:/ {
        flush_app()
        current_hostname = $3
        in_app = 1
        current_app = $0 "\n"
        next
    }

    /^  - service: http_status:404/ {
        flush_app()
        next
    }

    /^  - / {
        flush_app()
        next
    }

    in_app && /^    / {
        current_app = current_app $0 "\n"
        next
    }

    END {
        flush_app()
    }
    ' "$CONFIG_FILE" > "$apps_data"
    
    # Recréer le fichier config proprement
    write_config_header "$tunnel_id" "$creds_file"

    # Ajouter les applications restantes
    if [ -s "$apps_data" ]; then
        echo "" >> "$CONFIG_FILE"
        cat "$apps_data" >> "$CONFIG_FILE"
    fi
    
    # Ajouter le catch-all à la fin
    write_ingress_catch_all
    
    # Nettoyer
    rm -f "$apps_data"
    
    print_success "Application ${domain} supprimée"
    print_warning "L'enregistrement DNS n'est pas supprimé automatiquement"
    
    restart_tunnel
    
    press_enter
}

edit_config() {
    print_section "Édition de la configuration"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Aucune configuration trouvée"
        press_enter
        return
    fi
    
    local editor=${EDITOR:-nano}
    $editor "$CONFIG_FILE"
    
    # Valider après édition
    print_info "Validation de la configuration..."
    
    if cloudflared tunnel --config "$CONFIG_FILE" ingress validate 2>/dev/null; then
        print_success "Configuration valide"
        
        if confirm "Redémarrer le service?"; then
            restart_tunnel
        fi
    else
        print_error "Configuration invalide"
    fi
    
    press_enter
}

restart_tunnel() {
    local svc=$(get_service_name)
    print_info "Redémarrage du tunnel..."
    systemctl restart "$svc" 2>/dev/null || true
    sleep 2
    
    if systemctl is-active --quiet "$svc"; then
        print_success "Tunnel redémarré"
    else
        print_error "Échec du redémarrage"
    fi
}

#===============================================================================
# MENU SSL
#===============================================================================

menu_ssl() {
    while true; do
        print_banner
        print_section "🔐 CONFIGURATION SSL (CERTIFICATS ORIGIN)"
        
        echo -e "  ${CYAN}Les certificats Origin permettent:${NC}"
        echo "    - HTTPS pour les utilisateurs internes (intranet)"
        echo "    - Communication sécurisée entre Cloudflare et votre serveur"
        echo "    - Validité jusqu'à 15 ans"
        echo ""
        echo -e "  ${GREEN}1)${NC} Générer un nouveau certificat Origin"
        echo -e "  ${GREEN}2)${NC} Lister les certificats existants"
        echo -e "  ${GREEN}3)${NC} Afficher les chemins des certificats"
        echo -e "  ${GREEN}4)${NC} Générer une config Nginx avec SSL"
        echo -e "  ${GREEN}5)${NC} Configurer le DNS interne (split DNS)"
        echo ""
        echo -e "  ${RED}0)${NC} Retour"
        echo ""
        read -p "  Choix: " choice
        
        case $choice in
            1) generate_origin_cert ;;
            2) list_origin_certs ;;
            3) show_cert_paths ;;
            4) generate_nginx_ssl_config ;;
            5) configure_split_dns ;;
            0) return ;;
            *) print_error "Choix invalide" ;;
        esac
    done
}

generate_origin_cert() {
    print_section "Génération du certificat Origin"
    
    load_cf_config
    
    if [ -z "$CF_API_TOKEN" ] || [ -z "$CF_ZONE_ID" ]; then
        print_error "Credentials API non configurés"
        print_info "Allez dans: Installation > Configurer les credentials"
        press_enter
        return
    fi
    
    mkdir -p "$CERT_DIR"
    
    # Domaine
    echo -e "  ${CYAN}Configuration du certificat:${NC}"
    echo ""
    
    local default_hostnames="*.${CF_DOMAIN},${CF_DOMAIN}"
    read -p "  Hostnames à couvrir [$default_hostnames]: " hostnames
    hostnames=${hostnames:-$default_hostnames}
    
    # Validité
    echo ""
    echo "  Durée de validité:"
    echo "    1) 7 jours"
    echo "    2) 30 jours"
    echo "    3) 90 jours"
    echo "    4) 1 an"
    echo "    5) 5 ans"
    echo "    6) 15 ans (recommandé)"
    read -p "  Choix [6]: " validity_choice
    
    local validity_days=5475
    case $validity_choice in
        1) validity_days=7 ;;
        2) validity_days=30 ;;
        3) validity_days=90 ;;
        4) validity_days=365 ;;
        5) validity_days=1825 ;;
        6|"") validity_days=5475 ;;
    esac
    
    echo ""
    print_info "Génération du certificat via l'API Cloudflare..."
    
    # Construire la requête
    local hostnames_json=$(echo "$hostnames" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$"; ""))')
    
    local request_body=$(cat << EOF
{
    "hostnames": $hostnames_json,
    "requested_validity": $validity_days,
    "request_type": "origin-rsa"
}
EOF
)
    
    local response=$(curl -s -X POST "$CF_API_BASE/certificates" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$request_body")
    
    local success=$(echo "$response" | jq -r '.success')
    
    if [ "$success" != "true" ]; then
        print_error "Échec de la génération"
        echo "$response" | jq -r '.errors[]?.message' 2>/dev/null
        press_enter
        return
    fi
    
    # Extraire et sauvegarder
    local certificate=$(echo "$response" | jq -r '.result.certificate')
    local private_key=$(echo "$response" | jq -r '.result.private_key')
    local cert_id=$(echo "$response" | jq -r '.result.id')
    local expires_on=$(echo "$response" | jq -r '.result.expires_on')
    
    echo "$certificate" > "$CERT_DIR/${CF_DOMAIN}.pem"
    chmod 644 "$CERT_DIR/${CF_DOMAIN}.pem"
    
    if [ -n "$private_key" ] && [ "$private_key" != "null" ]; then
        echo "$private_key" > "$CERT_DIR/${CF_DOMAIN}.key"
        chmod 600 "$CERT_DIR/${CF_DOMAIN}.key"
    fi
    
    echo "$cert_id" > "$CERT_DIR/${CF_DOMAIN}.id"
    
    # Télécharger le CA Root
    curl -s "https://developers.cloudflare.com/ssl/static/origin_ca_rsa_root.pem" \
        -o "$CERT_DIR/cloudflare-origin-ca.pem"
    
    # Créer le fullchain
    cat "$CERT_DIR/${CF_DOMAIN}.pem" "$CERT_DIR/cloudflare-origin-ca.pem" \
        > "$CERT_DIR/${CF_DOMAIN}.fullchain.pem"
    
    print_success "Certificat généré avec succès"
    echo ""
    echo -e "  ${CYAN}Informations:${NC}"
    echo "    ID: $cert_id"
    echo "    Expire: $expires_on"
    echo ""
    echo -e "  ${CYAN}Fichiers créés:${NC}"
    echo "    Certificat: $CERT_DIR/${CF_DOMAIN}.pem"
    echo "    Clé privée: $CERT_DIR/${CF_DOMAIN}.key"
    echo "    Fullchain:  $CERT_DIR/${CF_DOMAIN}.fullchain.pem"
    
    press_enter
}

list_origin_certs() {
    print_section "Certificats Origin existants"
    
    load_cf_config
    
    if [ -z "$CF_API_TOKEN" ]; then
        print_error "API Token non configuré"
        press_enter
        return
    fi
    
    print_info "Récupération des certificats..."
    
    local response=$(curl -s -X GET "$CF_API_BASE/certificates?zone_id=$CF_ZONE_ID" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json")
    
    local success=$(echo "$response" | jq -r '.success')
    
    if [ "$success" != "true" ]; then
        print_error "Échec de la requête"
        press_enter
        return
    fi
    
    echo ""
    echo "$response" | jq -r '.result[] | "  ID: \(.id)\n  Hostnames: \(.hostnames | join(", "))\n  Expire: \(.expires_on)\n  ─────────────────────────────────────────────"'
    
    press_enter
}

show_cert_paths() {
    print_section "Chemins des certificats"
    
    load_cf_config
    
    echo -e "  ${CYAN}Utilisation avec Nginx:${NC}"
    echo ""
    echo "    ssl_certificate     $CERT_DIR/${CF_DOMAIN}.pem;"
    echo "    ssl_certificate_key $CERT_DIR/${CF_DOMAIN}.key;"
    echo ""
    echo -e "  ${CYAN}Utilisation avec Docker:${NC}"
    echo ""
    echo "    volumes:"
    echo "      - $CERT_DIR:/certs:ro"
    echo ""
    echo -e "  ${CYAN}Vérifier le certificat:${NC}"
    echo ""
    echo "    openssl x509 -in $CERT_DIR/${CF_DOMAIN}.pem -text -noout"
    echo ""
    
    press_enter
}

generate_nginx_ssl_config() {
    print_section "Génération config Nginx SSL"
    
    load_cf_config
    
    echo -e "  ${CYAN}Configuration du serveur:${NC}"
    echo ""
    
    read -p "  Domaine: " domain
    read -p "  IP du backend: " backend_ip
    read -p "  Port du backend: " backend_port
    read -p "  Port HTTPS [443]: " https_port
    https_port=${https_port:-443}
    
    local config_file="$CERT_DIR/nginx-${domain}.conf"
    
    cat > "$config_file" << EOF
# Configuration Nginx SSL pour ${domain}
# Généré le $(date)

server {
    listen ${https_port} ssl http2;
    listen [::]:${https_port} ssl http2;
    server_name ${domain};

    # Certificat Cloudflare Origin
    ssl_certificate     ${CERT_DIR}/${CF_DOMAIN}.pem;
    ssl_certificate_key ${CERT_DIR}/${CF_DOMAIN}.key;

    # Configuration SSL
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;

    # Headers de sécurité
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    location / {
        proxy_pass http://${backend_ip}:${backend_port};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}

# Redirection HTTP vers HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};
    return 301 https://\$host\$request_uri;
}
EOF

    print_success "Configuration créée: $config_file"
    echo ""
    echo "  Pour l'activer:"
    echo "    sudo cp $config_file /etc/nginx/sites-available/"
    echo "    sudo ln -s /etc/nginx/sites-available/nginx-${domain}.conf /etc/nginx/sites-enabled/"
    echo "    sudo nginx -t && sudo systemctl reload nginx"
    
    press_enter
}

configure_split_dns() {
    print_section "Configuration Split DNS (Intranet)"
    
    echo -e "  ${CYAN}Le Split DNS permet aux utilisateurs internes d'accéder${NC}"
    echo -e "  ${CYAN}directement aux services sans passer par Internet.${NC}"
    echo ""
    echo "  Options:"
    echo ""
    echo -e "  ${GREEN}1)${NC} Générer des entrées pour /etc/hosts"
    echo -e "  ${GREEN}2)${NC} Générer une zone DNS (pour serveur DNS interne)"
    echo -e "  ${GREEN}3)${NC} Instructions pour dnsmasq"
    echo ""
    read -p "  Choix: " choice
    
    case $choice in
        1) generate_hosts_entries ;;
        2) generate_dns_zone ;;
        3) show_dnsmasq_config ;;
    esac
}

generate_hosts_entries() {
    print_section "Entrées /etc/hosts"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Aucune configuration trouvée"
        press_enter
        return
    fi
    
    echo -e "  ${CYAN}Ajouter ces lignes à /etc/hosts des machines internes:${NC}"
    echo ""
    
    if [ -f "$CONFIG_FILE" ]; then
        grep -A1 "hostname:" "$CONFIG_FILE" | while read -r line; do
            if echo "$line" | grep -q "hostname:"; then
                hostname=$(echo "$line" | awk '{print $3}')
            elif echo "$line" | grep -q "service:"; then
                service=$(echo "$line" | awk '{print $2}')
                if [[ "$service" != *"http_status"* ]]; then
                    # Extraire IP (entre :// et :port ou fin)
                    ip=$(echo "$service" | sed -E 's|.*://([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+).*|\1|')
                    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                        printf "  %-15s\t%s\n" "$ip" "$hostname"
                    fi
                fi
            fi
        done
    fi
    
    echo ""
    press_enter
}

generate_dns_zone() {
    print_section "Zone DNS interne"
    
    load_cf_config
    
    echo -e "  ${CYAN}Zone DNS pour serveur interne:${NC}"
    echo ""
    echo "  ; Zone ${CF_DOMAIN} - Intranet"
    echo "  \$TTL 3600"
    echo ""
    
    if [ -f "$CONFIG_FILE" ]; then
        grep -A1 "hostname:" "$CONFIG_FILE" | while read -r line; do
            if echo "$line" | grep -q "hostname:"; then
                hostname=$(echo "$line" | awk '{print $3}')
            elif echo "$line" | grep -q "service:"; then
                service=$(echo "$line" | awk '{print $2}')
                if [[ "$service" != *"http_status"* ]]; then
                    ip=$(echo "$service" | sed -E 's|.*://([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+).*|\1|')
                    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                        short_hostname=$(echo "$hostname" | sed "s/\.${CF_DOMAIN}$//")
                        printf "  %-20s IN A     %s\n" "$short_hostname" "$ip"
                    fi
                fi
            fi
        done
    fi
    
    echo ""
    press_enter
}

show_dnsmasq_config() {
    print_section "Configuration dnsmasq"
    
    load_cf_config
    
    echo -e "  ${CYAN}Ajouter à /etc/dnsmasq.conf:${NC}"
    echo ""
    
    if [ -f "$CONFIG_FILE" ]; then
        grep -A1 "hostname:" "$CONFIG_FILE" | while read -r line; do
            if echo "$line" | grep -q "hostname:"; then
                hostname=$(echo "$line" | awk '{print $3}')
            elif echo "$line" | grep -q "service:"; then
                service=$(echo "$line" | awk '{print $2}')
                if [[ "$service" != *"http_status"* ]]; then
                    ip=$(echo "$service" | sed -E 's|.*://([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+).*|\1|')
                    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                        echo "  address=/${hostname}/${ip}"
                    fi
                fi
            fi
        done
    fi
    
    echo ""
    press_enter
}

#===============================================================================
# MENU ZTNA (Zero Trust)
#===============================================================================

menu_ztna() {
    while true; do
        print_banner
        print_section "🛡️ CONFIGURATION ZTNA (ZERO TRUST)"
        
        echo -e "  ${CYAN}Zero Trust Network Access permet de:${NC}"
        echo "    - Restreindre l'accès par IP"
        echo "    - Authentifier les utilisateurs (email, SSO)"
        echo "    - Définir des politiques d'accès"
        echo ""
        echo -e "  ${GREEN}1)${NC} Configurer une restriction par IP (WAF)"
        echo -e "  ${GREEN}2)${NC} Créer une application Access"
        echo -e "  ${GREEN}3)${NC} Gérer les politiques d'accès"
        echo -e "  ${GREEN}4)${NC} Lister les règles WAF existantes"
        echo -e "  ${GREEN}5)${NC} Ajouter une IP autorisée"
        echo -e "  ${GREEN}6)${NC} Supprimer une règle WAF"
        echo ""
        echo -e "  ${RED}0)${NC} Retour"
        echo ""
        read -p "  Choix: " choice
        
        case $choice in
            1) configure_ip_restriction ;;
            2) create_access_application ;;
            3) manage_access_policies ;;
            4) list_waf_rules ;;
            5) add_allowed_ip ;;
            6) delete_waf_rule ;;
            0) return ;;
            *) print_error "Choix invalide" ;;
        esac
    done
}

configure_ip_restriction() {
    print_section "Restriction par IP (WAF)"
    
    load_cf_config
    
    if [ -z "$CF_API_TOKEN" ] || [ -z "$CF_ZONE_ID" ]; then
        print_error "Credentials API non configurés"
        press_enter
        return
    fi
    
    echo -e "  ${CYAN}Cette règle bloquera tout le monde sauf les IPs autorisées.${NC}"
    echo ""
    
    # Sélectionner les domaines
    echo "  Domaines à protéger:"
    echo ""
    
    if [ -f "$CONFIG_FILE" ]; then
        awk '/^  - hostname:/ { print "    - " $3 }' "$CONFIG_FILE" | grep -v "^$"
    fi
    
    echo ""
    read -p "  Domaines (séparés par des espaces): " domains
    
    if [ -z "$domains" ]; then
        print_error "Domaines requis"
        press_enter
        return
    fi
    
    # IPs autorisées
    echo ""
    echo -e "  ${CYAN}IPs autorisées (une par ligne, vide pour terminer):${NC}"
    
    local ips=()
    while true; do
        read -p "  IP (ex: 102.64.145.19): " ip
        [ -z "$ip" ] && break
        ips+=("$ip")
    done
    
    if [ ${#ips[@]} -eq 0 ]; then
        print_error "Au moins une IP requise"
        press_enter
        return
    fi
    
    # Construire l'expression
    local domain_expr=""
    for d in $domains; do
        [ -n "$domain_expr" ] && domain_expr+=" or "
        domain_expr+="http.host eq \"$d\""
    done
    
    local ip_list=$(IFS=' '; echo "${ips[*]}")
    local expression="($domain_expr) and not ip.src in {$ip_list}"
    
    echo ""
    echo -e "  ${CYAN}Règle qui sera créée:${NC}"
    echo "    Expression: $expression"
    echo "    Action: Block"
    echo ""
    
    if ! confirm "Créer cette règle?"; then
        return
    fi
    
    # Créer le filtre et la règle
    print_info "Création de la règle WAF..."
    
    local filter_response=$(curl -s -X POST "$CF_API_BASE/zones/$CF_ZONE_ID/filters" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "[{\"expression\": \"$expression\"}]")
    
    local filter_success=$(echo "$filter_response" | jq -r '.success')
    
    if [ "$filter_success" != "true" ]; then
        print_error "Échec de la création du filtre"
        echo "$filter_response" | jq -r '.errors[]?.message' 2>/dev/null
        press_enter
        return
    fi
    
    local filter_id=$(echo "$filter_response" | jq -r '.result[0].id')
    
    # Créer la règle firewall
    local rule_response=$(curl -s -X POST "$CF_API_BASE/zones/$CF_ZONE_ID/firewall/rules" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "[{\"filter\": {\"id\": \"$filter_id\"}, \"action\": \"block\", \"description\": \"IP Restriction - Created by Tunnel Manager\"}]")
    
    local rule_success=$(echo "$rule_response" | jq -r '.success')
    
    if [ "$rule_success" = "true" ]; then
        print_success "Règle WAF créée avec succès"
    else
        print_error "Échec de la création de la règle"
        echo "$rule_response" | jq -r '.errors[]?.message' 2>/dev/null
    fi
    
    press_enter
}

list_waf_rules() {
    print_section "Règles WAF existantes"
    
    load_cf_config
    
    if [ -z "$CF_API_TOKEN" ] || [ -z "$CF_ZONE_ID" ]; then
        print_error "Credentials API non configurés"
        press_enter
        return
    fi
    
    print_info "Récupération des règles..."
    
    local response=$(curl -s -X GET "$CF_API_BASE/zones/$CF_ZONE_ID/firewall/rules" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json")
    
    local success=$(echo "$response" | jq -r '.success')
    
    if [ "$success" != "true" ]; then
        print_error "Échec de la requête"
        press_enter
        return
    fi
    
    echo ""
    echo "$response" | jq -r '.result[] | "  ID: \(.id)\n  Description: \(.description // "N/A")\n  Action: \(.action)\n  Expression: \(.filter.expression)\n  ─────────────────────────────────────────────"'
    
    press_enter
}

add_allowed_ip() {
    print_section "Ajouter une IP autorisée"
    
    load_cf_config
    
    print_info "Cette fonction modifie une règle WAF existante pour ajouter une IP."
    echo ""
    
    # Lister les règles
    local response=$(curl -s -X GET "$CF_API_BASE/zones/$CF_ZONE_ID/firewall/rules" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json")
    
    echo -e "  ${CYAN}Règles existantes:${NC}"
    echo "$response" | jq -r '.result[] | "    \(.id): \(.description // "N/A")"'
    echo ""
    
    read -p "  ID de la règle à modifier: " rule_id
    read -p "  Nouvelle IP à autoriser: " new_ip
    
    if [ -z "$rule_id" ] || [ -z "$new_ip" ]; then
        print_error "ID et IP requis"
        press_enter
        return
    fi
    
    # Récupérer l'expression actuelle
    local current_expression=$(echo "$response" | jq -r --arg id "$rule_id" '.result[] | select(.id == $id) | .filter.expression')
    local filter_id=$(echo "$response" | jq -r --arg id "$rule_id" '.result[] | select(.id == $id) | .filter.id')
    
    if [ -z "$current_expression" ]; then
        print_error "Règle non trouvée"
        press_enter
        return
    fi
    
    # Ajouter la nouvelle IP
    local new_expression=$(echo "$current_expression" | sed "s/in {/in {$new_ip /")
    
    echo ""
    echo -e "  ${CYAN}Nouvelle expression:${NC}"
    echo "    $new_expression"
    echo ""
    
    if ! confirm "Appliquer?"; then
        return
    fi
    
    # Mettre à jour le filtre
    local update_response=$(curl -s -X PUT "$CF_API_BASE/zones/$CF_ZONE_ID/filters/$filter_id" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"id\": \"$filter_id\", \"expression\": \"$new_expression\"}")
    
    local update_success=$(echo "$update_response" | jq -r '.success')
    
    if [ "$update_success" = "true" ]; then
        print_success "IP ajoutée avec succès"
    else
        print_error "Échec de la mise à jour"
        echo "$update_response" | jq -r '.errors[]?.message' 2>/dev/null
    fi
    
    press_enter
}

delete_waf_rule() {
    print_section "Supprimer une règle WAF"
    
    load_cf_config
    
    # Lister les règles
    local response=$(curl -s -X GET "$CF_API_BASE/zones/$CF_ZONE_ID/firewall/rules" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json")
    
    echo -e "  ${CYAN}Règles existantes:${NC}"
    echo "$response" | jq -r '.result[] | "    \(.id): \(.description // "N/A")"'
    echo ""
    
    read -p "  ID de la règle à supprimer: " rule_id
    
    if [ -z "$rule_id" ]; then
        return
    fi
    
    if ! confirm "Supprimer cette règle?"; then
        return
    fi
    
    local delete_response=$(curl -s -X DELETE "$CF_API_BASE/zones/$CF_ZONE_ID/firewall/rules/$rule_id" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json")
    
    local delete_success=$(echo "$delete_response" | jq -r '.success')
    
    if [ "$delete_success" = "true" ]; then
        print_success "Règle supprimée"
    else
        print_error "Échec de la suppression"
    fi
    
    press_enter
}

create_access_application() {
    print_section "Créer une application Access"
    
    load_cf_config
    
    if [ -z "$CF_ACCOUNT_ID" ]; then
        print_error "Account ID non configuré"
        press_enter
        return
    fi
    
    echo -e "  ${CYAN}Configuration de l'application Access:${NC}"
    echo ""
    
    read -p "  Nom de l'application: " app_name
    read -p "  Domaine (ex: app.hdl.tg): " app_domain
    
    echo ""
    echo "  Type d'application:"
    echo "    1) Self-hosted (application web)"
    echo "    2) SSH"
    echo "    3) VNC"
    read -p "  Choix [1]: " app_type_choice
    
    local app_type="self_hosted"
    case $app_type_choice in
        2) app_type="ssh" ;;
        3) app_type="vnc" ;;
    esac
    
    echo ""
    
    if ! confirm "Créer l'application Access?"; then
        return
    fi
    
    print_info "Création de l'application..."
    
    local request_body=$(cat << EOF
{
    "name": "$app_name",
    "domain": "$app_domain",
    "type": "$app_type",
    "session_duration": "24h"
}
EOF
)
    
    local response=$(curl -s -X POST "$CF_API_BASE/accounts/$CF_ACCOUNT_ID/access/apps" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$request_body")
    
    local success=$(echo "$response" | jq -r '.success')
    
    if [ "$success" = "true" ]; then
        local app_id=$(echo "$response" | jq -r '.result.id')
        print_success "Application créée: $app_id"
        echo ""
        print_info "Configurez maintenant les politiques d'accès dans le dashboard Zero Trust"
        echo "  https://one.dash.cloudflare.com"
    else
        print_error "Échec de la création"
        echo "$response" | jq -r '.errors[]?.message' 2>/dev/null
    fi
    
    press_enter
}

manage_access_policies() {
    print_section "Gestion des politiques Access"
    
    load_cf_config
    
    echo -e "  ${CYAN}Les politiques Access se gèrent via le dashboard Zero Trust.${NC}"
    echo ""
    echo "  URL: https://one.dash.cloudflare.com"
    echo ""
    echo "  Navigation:"
    echo "    1. Access > Applications"
    echo "    2. Sélectionner une application"
    echo "    3. Onglet 'Policies'"
    echo ""
    echo "  Types de politiques:"
    echo "    - Allow: Autoriser l'accès"
    echo "    - Block: Bloquer l'accès"
    echo "    - Bypass: Ignorer l'authentification"
    echo ""
    echo "  Critères disponibles:"
    echo "    - Emails"
    echo "    - IP Ranges"
    echo "    - Pays"
    echo "    - Service Token"
    echo "    - etc."
    
    press_enter
}

#===============================================================================
# MENU SERVICE
#===============================================================================

menu_service() {
    while true; do
        print_banner
        print_section "⚙️ GESTION DU SERVICE"
        
        local svc=$(get_service_name)
        local status="Inconnu"
        local enabled="Inconnu"
        
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            status="${GREEN}Actif${NC}"
        else
            status="${RED}Inactif${NC}"
        fi
        
        if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
            enabled="${GREEN}Oui${NC}"
        else
            enabled="${YELLOW}Non${NC}"
        fi
        
        echo -e "  ${CYAN}Service: ${WHITE}$svc${NC}"
        echo -e "  ${CYAN}Status: ${NC}$status"
        echo -e "  ${CYAN}Démarrage auto: ${NC}$enabled"
        echo ""
        echo -e "  ${GREEN}1)${NC} Démarrer"
        echo -e "  ${GREEN}2)${NC} Arrêter"
        echo -e "  ${GREEN}3)${NC} Redémarrer"
        echo -e "  ${GREEN}4)${NC} Activer au démarrage"
        echo -e "  ${GREEN}5)${NC} Désactiver au démarrage"
        echo -e "  ${GREEN}6)${NC} Voir les logs"
        echo -e "  ${GREEN}7)${NC} Status détaillé"
        echo ""
        echo -e "  ${RED}0)${NC} Retour"
        echo ""
        read -p "  Choix: " choice
        
        case $choice in
            1) systemctl start "$svc"; print_success "Service démarré"; press_enter ;;
            2) systemctl stop "$svc"; print_success "Service arrêté"; press_enter ;;
            3) systemctl restart "$svc"; print_success "Service redémarré"; press_enter ;;
            4) systemctl enable "$svc"; print_success "Activé au démarrage"; press_enter ;;
            5) systemctl disable "$svc"; print_success "Désactivé"; press_enter ;;
            6) journalctl -u "$svc" -f ;;
            7) systemctl status "$svc" --no-pager; press_enter ;;
            0) return ;;
            *) print_error "Choix invalide" ;;
        esac
    done
}

#===============================================================================
# MENU DIAGNOSTICS
#===============================================================================

menu_diagnostics() {
    while true; do
        print_banner
        print_section "📊 INFORMATIONS & DIAGNOSTICS"
        
        echo -e "  ${GREEN}1)${NC} Informations du tunnel"
        echo -e "  ${GREEN}2)${NC} Lister les tunnels"
        echo -e "  ${GREEN}3)${NC} Afficher la configuration"
        echo -e "  ${GREEN}4)${NC} Valider la configuration"
        echo -e "  ${GREEN}5)${NC} Tester la connectivité"
        echo -e "  ${GREEN}6)${NC} Informations système"
        echo ""
        echo -e "  ${RED}0)${NC} Retour"
        echo ""
        read -p "  Choix: " choice
        
        case $choice in
            1) show_tunnel_info ;;
            2) cloudflared tunnel list; press_enter ;;
            3) cat "$CONFIG_FILE" 2>/dev/null || print_error "Pas de configuration"; press_enter ;;
            4) cloudflared tunnel --config "$CONFIG_FILE" ingress validate 2>&1; press_enter ;;
            5) test_connectivity ;;
            6) show_system_info ;;
            0) return ;;
            *) print_error "Choix invalide" ;;
        esac
    done
}

show_tunnel_info() {
    print_section "Informations du tunnel"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Aucune configuration"
        press_enter
        return
    fi
    
    local tunnel_id=$(grep "^tunnel:" "$CONFIG_FILE" | awk '{print $2}')
    local svc=$(get_service_name)
    
    echo -e "  ${CYAN}Tunnel ID:${NC} $tunnel_id"
    echo -e "  ${CYAN}Service:${NC} $svc"
    echo ""
    echo -e "  ${CYAN}Applications:${NC}"
    
    awk '
    /^  - hostname:/ { hostname=$3 }
    /^    service:/ { 
        if (hostname != "" && $2 !~ /http_status/) {
            printf "    %-35s → %s\n", hostname, $2
        }
        hostname=""
    }
    ' "$CONFIG_FILE"
    
    echo ""
    
    # Connexions actives
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo -e "  ${CYAN}Connexions:${NC}"
        journalctl -u "$svc" --no-pager -n 50 2>/dev/null | grep "Registered tunnel connection" | tail -4 | \
            awk '{print "    " $0}'
    fi
    
    press_enter
}

test_connectivity() {
    print_section "Test de connectivité"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Aucune configuration"
        press_enter
        return
    fi
    
    echo -e "  ${CYAN}Test des services configurés:${NC}"
    echo ""
    
    awk '
    /^    service:/ { 
        if ($2 !~ /http_status/) {
            print $2
        }
    }
    ' "$CONFIG_FILE" | while read -r service; do
        # Extraire IP et port
        local target=$(echo "$service" | sed 's|.*://||' | sed 's|/.*||')
        local ip=$(echo "$target" | cut -d: -f1)
        local port=$(echo "$target" | cut -d: -f2)
        
        printf "  %-40s " "$service"
        
        if timeout 3 bash -c "echo >/dev/tcp/$ip/$port" 2>/dev/null; then
            echo -e "${GREEN}✓ OK${NC}"
        else
            echo -e "${RED}✗ ÉCHEC${NC}"
        fi
    done
    
    press_enter
}

show_system_info() {
    print_section "Informations système"
    
    echo -e "  ${CYAN}Système:${NC}"
    echo "    OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2)"
    echo "    Kernel: $(uname -r)"
    echo "    Architecture: $(uname -m)"
    echo ""
    echo -e "  ${CYAN}Réseau:${NC}"
    echo "    IP: $(hostname -I | awk '{print $1}')"
    echo "    Hostname: $(hostname -f 2>/dev/null || hostname)"
    echo ""
    echo -e "  ${CYAN}Cloudflared:${NC}"
    if command -v cloudflared &> /dev/null; then
        echo "    Version: $(cloudflared --version 2>/dev/null | head -1)"
        echo "    Binaire: $CLOUDFLARED_BIN"
    else
        echo "    Non installé"
    fi
    
    press_enter
}

#===============================================================================
# MENU DÉSINSTALLATION
#===============================================================================

menu_uninstall() {
    print_banner
    print_section "🗑️ DÉSINSTALLATION"
    
    echo -e "  ${RED}ATTENTION: Cette action est irréversible!${NC}"
    echo ""
    echo "  Options:"
    echo -e "  ${GREEN}1)${NC} Supprimer uniquement le tunnel (garde cloudflared)"
    echo -e "  ${GREEN}2)${NC} Désinstallation complète"
    echo ""
    echo -e "  ${RED}0)${NC} Annuler"
    echo ""
    read -p "  Choix: " choice
    
    case $choice in
        1) remove_tunnel ;;
        2) full_uninstall ;;
        0) return ;;
    esac
}

remove_tunnel() {
    print_section "Suppression du tunnel"
    
    local svc=$(get_service_name)
    
    # Arrêter le service
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
    
    # Lister les tunnels
    echo "  Tunnels existants:"
    cloudflared tunnel list 2>/dev/null
    echo ""
    
    read -p "  Nom du tunnel à supprimer: " tunnel_name
    
    if [ -z "$tunnel_name" ]; then
        return
    fi
    
    if ! confirm "Supprimer le tunnel '$tunnel_name'?"; then
        return
    fi
    
    cloudflared tunnel cleanup "$tunnel_name" 2>/dev/null || true
    cloudflared tunnel delete "$tunnel_name" 2>/dev/null || true
    
    # Supprimer les fichiers
    rm -f "/etc/systemd/system/${svc}.service"
    rm -f "$CONFIG_FILE"
    rm -f "$CLOUDFLARED_DIR/.service_name"
    
    systemctl daemon-reload
    
    print_success "Tunnel supprimé"
    press_enter
}

full_uninstall() {
    print_section "Désinstallation complète"
    
    echo -e "  ${RED}Ceci va supprimer:${NC}"
    echo "    - cloudflared"
    echo "    - Tous les tunnels"
    echo "    - Toute la configuration"
    echo "    - Les certificats Origin"
    echo ""
    
    if ! confirm "Continuer?"; then
        return
    fi
    
    read -p "  Tapez 'CONFIRMER' pour continuer: " confirmation
    
    if [ "$confirmation" != "CONFIRMER" ]; then
        print_info "Annulé"
        press_enter
        return
    fi
    
    print_info "Désinstallation en cours..."
    
    # Arrêter tous les services cloudflared
    for svc in $(systemctl list-units --type=service --all | grep cloudflared | awk '{print $1}'); do
        systemctl stop "$svc" 2>/dev/null || true
        systemctl disable "$svc" 2>/dev/null || true
    done
    
    # Supprimer tous les tunnels
    for tunnel in $(cloudflared tunnel list 2>/dev/null | tail -n +2 | awk '{print $2}'); do
        cloudflared tunnel cleanup "$tunnel" 2>/dev/null || true
        cloudflared tunnel delete "$tunnel" 2>/dev/null || true
    done
    
    # Supprimer les fichiers
    rm -rf "$CLOUDFLARED_DIR"
    rm -rf "$CREDENTIALS_DIR"
    rm -rf "$CERT_DIR"
    rm -f "$CLOUDFLARED_BIN"
    rm -f /etc/systemd/system/cloudflared*.service
    
    systemctl daemon-reload
    
    print_success "Désinstallation terminée"
    press_enter
}

#===============================================================================
# MAIN
#===============================================================================

check_root
check_dependencies
main_menu
