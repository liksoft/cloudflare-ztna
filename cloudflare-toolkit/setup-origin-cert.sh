#!/bin/bash

#===============================================================================
# Script d'installation Cloudflare Origin Certificate
# Génère et installe un certificat SSL via l'API Cloudflare
#===============================================================================

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration par défaut
CERT_DIR="/etc/cloudflare-certs"
VALIDITY_DAYS=5475  # 15 ans
KEY_TYPE="rsa"      # rsa ou ecdsa

# Variables à remplir
CF_API_TOKEN=""
CF_ZONE_ID=""
DOMAIN=""
HOSTNAMES=""

#-------------------------------------------------------------------------------
# Afficher l'aide
#-------------------------------------------------------------------------------
show_help() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}        Cloudflare Origin Certificate - Installation               ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -t, --token <token>      API Token Cloudflare (avec permissions Origin CA)"
    echo "  -z, --zone <zone_id>     Zone ID du domaine"
    echo "  -d, --domain <domain>    Domaine principal (ex: hdl.tg)"
    echo "  -h, --hostnames <hosts>  Hostnames couverts (ex: \"*.hdl.tg,hdl.tg\")"
    echo "  -o, --output <dir>       Dossier de sortie (défaut: /etc/cloudflare-certs)"
    echo "  -v, --validity <days>    Validité en jours (défaut: 5475 = 15 ans)"
    echo "  -k, --key-type <type>    Type de clé: rsa ou ecdsa (défaut: rsa)"
    echo "  --help                   Afficher cette aide"
    echo ""
    echo "Exemples:"
    echo ""
    echo "  # Mode interactif"
    echo "  sudo $0"
    echo ""
    echo "  # Mode paramètres"
    echo "  sudo $0 -t <API_TOKEN> -z <ZONE_ID> -d hdl.tg -h \"*.hdl.tg,hdl.tg\""
    echo ""
    echo -e "${YELLOW}Comment obtenir les informations nécessaires :${NC}"
    echo ""
    echo "  1. API Token :"
    echo "     - Cloudflare Dashboard → My Profile → API Tokens"
    echo "     - Create Token → Custom Token"
    echo "     - Permissions: Zone → SSL and Certificates → Edit"
    echo "     - Zone Resources: Include → Specific Zone → hdl.tg"
    echo ""
    echo "  2. Zone ID :"
    echo "     - Cloudflare Dashboard → hdl.tg → Overview"
    echo "     - Dans la colonne de droite : Zone ID"
    echo ""
}

#-------------------------------------------------------------------------------
# Parser les arguments
#-------------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--token)
                CF_API_TOKEN="$2"
                shift 2
                ;;
            -z|--zone)
                CF_ZONE_ID="$2"
                shift 2
                ;;
            -d|--domain)
                DOMAIN="$2"
                shift 2
                ;;
            -h|--hostnames)
                HOSTNAMES="$2"
                shift 2
                ;;
            -o|--output)
                CERT_DIR="$2"
                shift 2
                ;;
            -v|--validity)
                VALIDITY_DAYS="$2"
                shift 2
                ;;
            -k|--key-type)
                KEY_TYPE="$2"
                shift 2
                ;;
            --help)
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
# Mode interactif
#-------------------------------------------------------------------------------
interactive_mode() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Cloudflare Origin Certificate - Configuration             ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # API Token
    if [ -z "$CF_API_TOKEN" ]; then
        echo -e "${CYAN}┌─ API Token Cloudflare${NC}"
        echo -e "${CYAN}│  Crée un token avec permission: SSL and Certificates → Edit${NC}"
        echo -e "${CYAN}│  Dashboard → My Profile → API Tokens → Create Token${NC}"
        read -sp "└─ API Token: " CF_API_TOKEN
        echo ""
        echo ""
    fi
    
    # Zone ID
    if [ -z "$CF_ZONE_ID" ]; then
        echo -e "${CYAN}┌─ Zone ID${NC}"
        echo -e "${CYAN}│  Dashboard → hdl.tg → Overview → Zone ID (colonne droite)${NC}"
        read -p "└─ Zone ID: " CF_ZONE_ID
        echo ""
    fi
    
    # Domain
    if [ -z "$DOMAIN" ]; then
        echo -e "${CYAN}┌─ Domaine principal${NC}"
        read -p "└─ Domaine (ex: hdl.tg): " DOMAIN
        echo ""
    fi
    
    # Hostnames
    if [ -z "$HOSTNAMES" ]; then
        DEFAULT_HOSTNAMES="*.${DOMAIN},${DOMAIN}"
        echo -e "${CYAN}┌─ Hostnames à couvrir${NC}"
        echo -e "${CYAN}│  Séparer par des virgules${NC}"
        read -p "└─ Hostnames [$DEFAULT_HOSTNAMES]: " HOSTNAMES
        HOSTNAMES=${HOSTNAMES:-$DEFAULT_HOSTNAMES}
        echo ""
    fi
    
    # Validité
    echo -e "${CYAN}┌─ Durée de validité${NC}"
    echo -e "${CYAN}│  Options: 7 (7 jours), 30, 90, 365, 730 (2 ans), 1095 (3 ans),"
    echo -e "${CYAN}│           1825 (5 ans), 3650 (10 ans), 5475 (15 ans)${NC}"
    read -p "└─ Jours [$VALIDITY_DAYS]: " input_validity
    VALIDITY_DAYS=${input_validity:-$VALIDITY_DAYS}
    echo ""
}

#-------------------------------------------------------------------------------
# Vérifier les prérequis
#-------------------------------------------------------------------------------
check_prerequisites() {
    echo -e "${YELLOW}Vérification des prérequis...${NC}"
    
    # Vérifier root
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}✗ Ce script doit être exécuté en tant que root${NC}"
        exit 1
    fi
    echo -e "${GREEN}  ✓ Droits root${NC}"
    
    # Vérifier curl
    if ! command -v curl &> /dev/null; then
        echo -e "${YELLOW}  ⚠ Installation de curl...${NC}"
        apt-get update && apt-get install -y curl
    fi
    echo -e "${GREEN}  ✓ curl disponible${NC}"
    
    # Vérifier jq
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}  ⚠ Installation de jq...${NC}"
        apt-get update && apt-get install -y jq
    fi
    echo -e "${GREEN}  ✓ jq disponible${NC}"
    
    # Vérifier openssl
    if ! command -v openssl &> /dev/null; then
        echo -e "${RED}✗ openssl non trouvé${NC}"
        exit 1
    fi
    echo -e "${GREEN}  ✓ openssl disponible${NC}"
    
    echo ""
}

#-------------------------------------------------------------------------------
# Valider la configuration
#-------------------------------------------------------------------------------
validate_config() {
    local errors=0
    
    echo -e "${YELLOW}Validation de la configuration...${NC}"
    
    if [ -z "$CF_API_TOKEN" ]; then
        echo -e "${RED}  ✗ API Token manquant${NC}"
        errors=$((errors + 1))
    else
        echo -e "${GREEN}  ✓ API Token configuré${NC}"
    fi
    
    if [ -z "$CF_ZONE_ID" ]; then
        echo -e "${RED}  ✗ Zone ID manquant${NC}"
        errors=$((errors + 1))
    else
        echo -e "${GREEN}  ✓ Zone ID: $CF_ZONE_ID${NC}"
    fi
    
    if [ -z "$DOMAIN" ]; then
        echo -e "${RED}  ✗ Domaine manquant${NC}"
        errors=$((errors + 1))
    else
        echo -e "${GREEN}  ✓ Domaine: $DOMAIN${NC}"
    fi
    
    if [ -z "$HOSTNAMES" ]; then
        echo -e "${RED}  ✗ Hostnames manquants${NC}"
        errors=$((errors + 1))
    else
        echo -e "${GREEN}  ✓ Hostnames: $HOSTNAMES${NC}"
    fi
    
    echo ""
    
    if [ $errors -gt 0 ]; then
        echo -e "${RED}Configuration invalide ($errors erreurs)${NC}"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# Tester la connexion API
#-------------------------------------------------------------------------------
test_api_connection() {
    echo -e "${YELLOW}Test de la connexion API Cloudflare...${NC}"
    
    RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json")
    
    SUCCESS=$(echo "$RESPONSE" | jq -r '.success')
    
    if [ "$SUCCESS" != "true" ]; then
        echo -e "${RED}✗ Échec de connexion à l'API Cloudflare${NC}"
        echo "$RESPONSE" | jq -r '.errors[]?.message' 2>/dev/null || echo "$RESPONSE"
        exit 1
    fi
    
    ZONE_NAME=$(echo "$RESPONSE" | jq -r '.result.name')
    echo -e "${GREEN}  ✓ Connecté à la zone: $ZONE_NAME${NC}"
    echo ""
}

#-------------------------------------------------------------------------------
# Générer la clé privée
#-------------------------------------------------------------------------------
generate_private_key() {
    echo -e "${YELLOW}Génération de la clé privée ($KEY_TYPE)...${NC}"
    
    mkdir -p "$CERT_DIR"
    
    KEY_FILE="$CERT_DIR/${DOMAIN}.key"
    
    if [ "$KEY_TYPE" = "ecdsa" ]; then
        openssl ecparam -genkey -name prime256v1 -out "$KEY_FILE" 2>/dev/null
    else
        openssl genrsa -out "$KEY_FILE" 2048 2>/dev/null
    fi
    
    chmod 600 "$KEY_FILE"
    echo -e "${GREEN}  ✓ Clé privée générée: $KEY_FILE${NC}"
}

#-------------------------------------------------------------------------------
# Générer le CSR
#-------------------------------------------------------------------------------
generate_csr() {
    echo -e "${YELLOW}Génération du CSR...${NC}"
    
    CSR_FILE="$CERT_DIR/${DOMAIN}.csr"
    KEY_FILE="$CERT_DIR/${DOMAIN}.key"
    
    # Créer le fichier de config OpenSSL pour le CSR
    CONFIG_FILE=$(mktemp)
    
    cat > "$CONFIG_FILE" << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext

[dn]
CN = $DOMAIN

[req_ext]
subjectAltName = @alt_names

[alt_names]
EOF
    
    # Ajouter les SANs
    IFS=',' read -ra HOSTS <<< "$HOSTNAMES"
    i=1
    for host in "${HOSTS[@]}"; do
        host=$(echo "$host" | xargs)  # trim whitespace
        echo "DNS.$i = $host" >> "$CONFIG_FILE"
        i=$((i + 1))
    done
    
    # Générer le CSR
    openssl req -new -key "$KEY_FILE" -out "$CSR_FILE" -config "$CONFIG_FILE" 2>/dev/null
    
    rm -f "$CONFIG_FILE"
    
    echo -e "${GREEN}  ✓ CSR généré: $CSR_FILE${NC}"
    
    # Lire le CSR pour l'API
    CSR_CONTENT=$(cat "$CSR_FILE")
}

#-------------------------------------------------------------------------------
# Demander le certificat à Cloudflare
#-------------------------------------------------------------------------------
request_certificate() {
    echo -e "${YELLOW}Demande du certificat Origin à Cloudflare...${NC}"
    
    # Construire le JSON des hostnames
    HOSTNAMES_JSON=$(echo "$HOSTNAMES" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$"; ""))')
    
    # Préparer la requête
    REQUEST_BODY=$(cat << EOF
{
    "hostnames": $HOSTNAMES_JSON,
    "requested_validity": $VALIDITY_DAYS,
    "request_type": "origin-rsa",
    "csr": $(echo "$CSR_CONTENT" | jq -Rs .)
}
EOF
)
    
    # Appeler l'API Origin CA
    RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/certificates" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$REQUEST_BODY")
    
    SUCCESS=$(echo "$RESPONSE" | jq -r '.success')
    
    if [ "$SUCCESS" != "true" ]; then
        echo -e "${RED}✗ Échec de la demande de certificat${NC}"
        echo "$RESPONSE" | jq -r '.errors[]?.message' 2>/dev/null || echo "$RESPONSE"
        
        # Essayer avec l'ancienne méthode (sans CSR)
        echo -e "${YELLOW}Tentative avec génération automatique...${NC}"
        request_certificate_auto
        return
    fi
    
    # Extraire le certificat
    CERTIFICATE=$(echo "$RESPONSE" | jq -r '.result.certificate')
    CERT_ID=$(echo "$RESPONSE" | jq -r '.result.id')
    EXPIRES_ON=$(echo "$RESPONSE" | jq -r '.result.expires_on')
    
    if [ -z "$CERTIFICATE" ] || [ "$CERTIFICATE" = "null" ]; then
        echo -e "${RED}✗ Certificat vide dans la réponse${NC}"
        exit 1
    fi
    
    # Sauvegarder le certificat
    CERT_FILE="$CERT_DIR/${DOMAIN}.pem"
    echo "$CERTIFICATE" > "$CERT_FILE"
    chmod 644 "$CERT_FILE"
    
    echo -e "${GREEN}  ✓ Certificat obtenu${NC}"
    echo -e "${GREEN}    ID: $CERT_ID${NC}"
    echo -e "${GREEN}    Expire: $EXPIRES_ON${NC}"
    echo -e "${GREEN}    Fichier: $CERT_FILE${NC}"
    
    # Sauvegarder l'ID pour révocation future
    echo "$CERT_ID" > "$CERT_DIR/${DOMAIN}.id"
}

#-------------------------------------------------------------------------------
# Demander le certificat (méthode alternative sans CSR)
#-------------------------------------------------------------------------------
request_certificate_auto() {
    # Construire le JSON des hostnames
    HOSTNAMES_JSON=$(echo "$HOSTNAMES" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$"; ""))')
    
    REQUEST_BODY=$(cat << EOF
{
    "hostnames": $HOSTNAMES_JSON,
    "requested_validity": $VALIDITY_DAYS,
    "request_type": "origin-rsa"
}
EOF
)
    
    RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/certificates" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$REQUEST_BODY")
    
    SUCCESS=$(echo "$RESPONSE" | jq -r '.success')
    
    if [ "$SUCCESS" != "true" ]; then
        echo -e "${RED}✗ Échec de la demande de certificat${NC}"
        echo "$RESPONSE" | jq -r '.errors[]?.message' 2>/dev/null || echo "$RESPONSE"
        exit 1
    fi
    
    # Extraire le certificat ET la clé privée
    CERTIFICATE=$(echo "$RESPONSE" | jq -r '.result.certificate')
    PRIVATE_KEY=$(echo "$RESPONSE" | jq -r '.result.private_key')
    CERT_ID=$(echo "$RESPONSE" | jq -r '.result.id')
    EXPIRES_ON=$(echo "$RESPONSE" | jq -r '.result.expires_on')
    
    # Sauvegarder
    CERT_FILE="$CERT_DIR/${DOMAIN}.pem"
    KEY_FILE="$CERT_DIR/${DOMAIN}.key"
    
    echo "$CERTIFICATE" > "$CERT_FILE"
    chmod 644 "$CERT_FILE"
    
    if [ -n "$PRIVATE_KEY" ] && [ "$PRIVATE_KEY" != "null" ]; then
        echo "$PRIVATE_KEY" > "$KEY_FILE"
        chmod 600 "$KEY_FILE"
    fi
    
    echo -e "${GREEN}  ✓ Certificat obtenu (génération auto)${NC}"
    echo -e "${GREEN}    ID: $CERT_ID${NC}"
    echo -e "${GREEN}    Expire: $EXPIRES_ON${NC}"
    
    echo "$CERT_ID" > "$CERT_DIR/${DOMAIN}.id"
}

#-------------------------------------------------------------------------------
# Télécharger le CA Root Cloudflare
#-------------------------------------------------------------------------------
download_ca_root() {
    echo -e "${YELLOW}Téléchargement du CA Root Cloudflare...${NC}"
    
    CA_FILE="$CERT_DIR/cloudflare-origin-ca.pem"
    
    # Cloudflare Origin CA - RSA Root
    curl -s "https://developers.cloudflare.com/ssl/static/origin_ca_rsa_root.pem" -o "$CA_FILE"
    
    if [ -f "$CA_FILE" ] && [ -s "$CA_FILE" ]; then
        echo -e "${GREEN}  ✓ CA Root téléchargé: $CA_FILE${NC}"
    else
        echo -e "${YELLOW}  ⚠ Impossible de télécharger le CA Root${NC}"
    fi
    
    # Créer le fullchain (cert + CA)
    FULLCHAIN_FILE="$CERT_DIR/${DOMAIN}.fullchain.pem"
    cat "$CERT_DIR/${DOMAIN}.pem" "$CA_FILE" > "$FULLCHAIN_FILE" 2>/dev/null || true
    
    if [ -f "$FULLCHAIN_FILE" ]; then
        echo -e "${GREEN}  ✓ Fullchain créé: $FULLCHAIN_FILE${NC}"
    fi
}

#-------------------------------------------------------------------------------
# Créer le fichier de configuration nginx exemple
#-------------------------------------------------------------------------------
create_nginx_example() {
    NGINX_EXAMPLE="$CERT_DIR/nginx-example.conf"
    
    cat > "$NGINX_EXAMPLE" << EOF
# Exemple de configuration Nginx avec certificat Cloudflare Origin
# Copier dans /etc/nginx/sites-available/ et adapter

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${HOSTNAMES//,/ };

    # Certificat Cloudflare Origin
    ssl_certificate     ${CERT_DIR}/${DOMAIN}.pem;
    ssl_certificate_key ${CERT_DIR}/${DOMAIN}.key;
    
    # Ou avec fullchain
    # ssl_certificate     ${CERT_DIR}/${DOMAIN}.fullchain.pem;
    # ssl_certificate_key ${CERT_DIR}/${DOMAIN}.key;

    # Configuration SSL recommandée
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;

    # Proxy vers l'application
    location / {
        proxy_pass http://127.0.0.1:8069;  # Adapter le port
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# Redirection HTTP vers HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name ${HOSTNAMES//,/ };
    return 301 https://\$host\$request_uri;
}
EOF

    echo -e "${GREEN}  ✓ Exemple nginx créé: $NGINX_EXAMPLE${NC}"
}

#-------------------------------------------------------------------------------
# Afficher le résumé
#-------------------------------------------------------------------------------
show_summary() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           ✓ CERTIFICAT INSTALLÉ AVEC SUCCÈS                    ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}Fichiers créés:${NC}"
    echo ""
    echo -e "    Certificat:    ${GREEN}${CERT_DIR}/${DOMAIN}.pem${NC}"
    echo -e "    Clé privée:    ${GREEN}${CERT_DIR}/${DOMAIN}.key${NC}"
    echo -e "    Fullchain:     ${GREEN}${CERT_DIR}/${DOMAIN}.fullchain.pem${NC}"
    echo -e "    CA Root:       ${GREEN}${CERT_DIR}/cloudflare-origin-ca.pem${NC}"
    echo -e "    Exemple nginx: ${GREEN}${CERT_DIR}/nginx-example.conf${NC}"
    echo ""
    echo -e "  ${CYAN}Informations:${NC}"
    echo ""
    echo -e "    Domaine:       ${DOMAIN}"
    echo -e "    Hostnames:     ${HOSTNAMES}"
    echo -e "    Validité:      ${VALIDITY_DAYS} jours"
    echo ""
    echo -e "${BLUE}────────────────────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${YELLOW}Utilisation avec Nginx:${NC}"
    echo ""
    echo "    ssl_certificate     ${CERT_DIR}/${DOMAIN}.pem;"
    echo "    ssl_certificate_key ${CERT_DIR}/${DOMAIN}.key;"
    echo ""
    echo -e "  ${YELLOW}Utilisation avec Docker/Traefik:${NC}"
    echo ""
    echo "    Monter le volume: -v ${CERT_DIR}:/certs:ro"
    echo ""
    echo -e "  ${YELLOW}Vérifier le certificat:${NC}"
    echo ""
    echo "    openssl x509 -in ${CERT_DIR}/${DOMAIN}.pem -text -noout"
    echo ""
}

#===============================================================================
# MAIN
#===============================================================================

parse_args "$@"

# Mode interactif si paramètres manquants
if [ -z "$CF_API_TOKEN" ] || [ -z "$CF_ZONE_ID" ] || [ -z "$DOMAIN" ]; then
    interactive_mode
fi

check_prerequisites
validate_config
test_api_connection
generate_private_key
generate_csr
request_certificate
download_ca_root
create_nginx_example
show_summary
