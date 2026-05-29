#!/bin/bash
#
# NPM Recovery Script - Recreates Nginx Proxy Manager proxy hosts
# Usage: ./recovery.sh [command]
#
# Commands:
#   login              - Login to NPM API and store session
#   list               - List all proxy hosts
#   create <domain>   - Create a single proxy host
#   delete <domain>  - Delete a proxy host by domain
#   recreate          - Recreate all proxy hosts (default)
#
# Note: Using -u to catch unset variables but handling arrays carefully
set -Eeo pipefail

#==============================================================================
# CONFIGURATION - Customize these variables
#==============================================================================

# SSH configuration for Proxmox container access
NPM_SSH_KEY_PATH="${NPM_SSH_KEY_PATH:-${HOME}/.ssh/homelab_key}"
NPM_SSH_HOST="${NPM_SSH_HOST:-192.168.1.134}"
NPM_SSH_PORT="${NPM_SSH_PORT:-22}"
NPM_SSH_USER="${NPM_SSH_USER:-root}"
NPM_CONTAINER_ID="${NPM_CONTAINER_ID:-101}"

# NPM API credentials (change these!)
NPM_API_URL="${NPM_API_URL:-http://localhost:81}"
NPM_API_USER="${NPM_API_USER:-hasbringer1007@gmail.com}"
NPM_API_PASS="${NPM_API_PASS:-}"

# DuckDNS configuration
DUBNSDNS_DOMAIN="${DUCKDNS_DOMAIN:-hp136}"
SSL_CERT_ID="${SSL_CERT_ID:-3}"  # Wildcard *.hp136.duckdns.org

# Logging
LOG_FILE="${LOG_FILE:-/var/log/npm-recovery.log}"

#==============================================================================
# DERIVED VARIABLES (do not edit)
#==============================================================================

# Full domain suffix for DuckDNS
DOMAIN_SUFFIX="${DUBNSDNS_DOMAIN}.duckdns.org"
BASE_HOST="192.168.1"

#==============================================================================
# PROXY HOSTS DEFINITION
#==============================================================================

# Format: subdomain -> "ip:port[:websocket]"
# Using indirect reference to build associative array compatible with all bash versions
PROXY_HOSTS="arcane:192.168.1.142:3552 bazarr:192.168.1.142:6767 deluge:192.168.1.142:8112 frigate:192.168.1.142:5000 lidarr:192.168.1.142:8686 npm:192.168.1.142:81 vw:192.168.1.142:8080 ha:192.168.1.100:8123:websocket agh:192.168.1.2:80 jelly:192.168.1.142:8096 rad:192.168.1.142:7878 son:192.168.1.142:8989 prowlarr:192.168.1.142:9696 qbit:192.168.1.142:8081"

# Validate proxy hosts are defined
if [[ -z "$PROXY_HOSTS" ]]; then
    echo "ERROR: No proxy hosts defined" >&2
    exit 1
fi

# Function to get proxy host value by subdomain
get_proxy_host() {
    local subdomain="$1"
    local old_ifs="$IFS"
    IFS=' '
    for entry in $PROXY_HOSTS; do
        if [[ "$entry" == "${subdomain}"* ]]; then
            IFS=':'
            read -r key host port ws <<< "$entry"
            if [[ "$key" == "$subdomain" ]]; then
                IFS="$old_ifs"
                echo "${host}:${port}${ws:+:$ws}"
                return 0
            fi
        fi
    done
    IFS="$old_ifs"
    return 1
}

# Function to list all subdomains
list_subdomains() {
    local old_ifs="$IFS"
    IFS=' '
    for entry in $PROXY_HOSTS; do
        IFS=':'
        read -r key host port ws <<< "$entry"
        echo "$key"
    done
    IFS="$old_ifs"
}

#==============================================================================
# LOGGING FUNCTIONS
#==============================================================================

log_info() {
    local msg="$1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $msg"
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $msg" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

log_warn() {
    local msg="$1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $msg" >&2
}

log_error() {
    local msg="$1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $msg" >&2
}

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        local msg="$1"
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] DEBUG: $msg" >&2
    fi
}

#==============================================================================
# DEPENDENCY CHECKING
#==============================================================================

check_dependencies() {
    local -a missing_deps=()
    local -a required_cmds=("ssh" "curl" "jq")

    for dep in "${required_cmds[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing_deps[*]}"
        return 1
    fi

    return 0
}

#==============================================================================
# VALIDATION FUNCTIONS
#==============================================================================

validate_domain() {
    local domain="$1"

    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*(\.[a-zA-Z0-9][a-zA-Z0-9-]*)*$ ]]; then
        log_error "Invalid domain format: $domain"
        return 1
    fi

    return 0
}

validate_port() {
    local port="$1"

    if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        log_error "Invalid port number: $port"
        return 1
    fi

    return 0
}

#==============================================================================
# SSH HELPER FUNCTIONS
#==============================================================================

# Execute command inside NPM container via SSH
ssh_exec() {
    local cmd="$1"
    local timeout="${2:-30}"

    if [[ ! -f "$NPM_SSH_KEY_PATH" ]]; then
        log_error "SSH key not found: $NPM_SSH_KEY_PATH"
        log_error "Set NPM_SSH_KEY_PATH or create: $NPM_SSH_KEY_PATH"
        return 1
    fi

    # Try direct SSH first if SSH daemon is running on host
    if timeout "$timeout" ssh -o StrictHostKeyChecking=no \
        -o ConnectTimeout="$timeout" \
        -i "$NPM_SSH_KEY_PATH" \
        -p "$NPM_SSH_PORT" \
        "${NPM_SSH_USER}@${NPM_SSH_HOST}" \
        "$cmd" 2>/dev/null; then
        return 0
    fi

    # Fallback: Execute via Proxmox container exec
    log_debug "Using Proxmox container exec for: $cmd"
    pvesh get "/nodes/localhost/qemu/${NPM_CONTAINER_ID}/status/current" &>/dev/null || {
        log_error "Container not accessible: $NPM_CONTAINER_ID"
        return 1
    }

    # Use pct exec to run command in container
    if command -v pct &>/dev/null; then
        pct exec "$NPM_CONTAINER_ID" -- "$cmd"
    else
        log_error "Cannot access container and pct not available"
        return 1
    fi
}

#==============================================================================
# NPM API FUNCTIONS
#==============================================================================

# Login to NPM API and get JWT token
npm_login() {
    log_info "Logging into NPM API..."

    local response
    response=$(curl -s -X POST "${NPM_API_URL}/api/tokens" \
        -H "Content-Type: application/json" \
        -d "{\"identity\":\"${NPM_API_USER}\",\"scope\":\"user\",\"secret\":\"${NPM_API_PASS}\"}" \
    ) || {
        log_error "Failed to connect to NPM API"
        return 1
    }

    local token
    token=$(echo "$response" | jq -r '.token // empty')

    if [[ -z "$token" || "$token" == "null" ]]; then
        log_error "Login failed. Check credentials."
        log_debug "Response: $response"
        return 1
    fi

    # Store token
    NPM_TOKEN="$token"
    export NPM_TOKEN
    log_info "Login successful"
    echo "$token"
    return 0
}

# Get NPM API headers with token
npm_headers() {
    local token="${1:-${NPM_TOKEN:-}}"

    if [[ -z "$token" ]]; then
        log_error "No NPM token available. Run login first."
        return 1
    fi

    echo "-H \"Authorization: Bearer $token\" -H \"Content-Type: application/json\""
}

# List all proxy hosts
npm_list_proxy_hosts() {
    local token="${1:-${NPM_TOKEN:-}}"

    if [[ -z "$token" ]]; then
        log_error "No NPM token. Run login first."
        return 1
    fi

    curl -s -X GET "${NPM_API_URL}/api/nginx/proxy-hosts" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" | jq -r '.[] | "\(.id) \(.domain_names[0])"' 2>/dev/null || {
        log_error "Failed to list proxy hosts"
        return 1
    }

    return 0
}

# Create a proxy host
npm_create_proxy_host() {
    local subdomain="$1"
    local target_host="$2"
    local target_port="$3"
    local websocket="${4:-false}"
    local token="${5:-${NPM_TOKEN:-}}"

    # Validate inputs
    [[ -n "$subdomain" ]] || { log_error "subdomain required"; return 1; }
    [[ -n "$target_host" ]] || { log_error "target_host required"; return 1; }
    [[ -n "$target_port" ]] || { log_error "target_port required"; return 1; }
    [[ -n "$token" ]] || { log_error "token required"; return 1; }

    local full_domain="${subdomain}.${DOMAIN_SUFFIX}"

    log_info "Creating proxy host: ${full_domain} -> ${target_host}:${target_port}"

    # Convert websocket flag from string to boolean
    local ws_flag="false"
    if [[ "${websocket}" == "true" ]]; then
        ws_flag="true"
    fi

    # Prepare nginx study configuration
    local proxy_body
    local nginx_config
    nginx_config=$(cat <<EOF
{
  "domain_names": ["${full_domain}"],
  "forward_scheme": "http",
  "forward_host": "${target_host}",
  "forward_port": ${target_port},
  "access_list_id": 0,
  "certificate_id": ${SSL_CERT_ID},
  "ssl_forced": true,
  "http2_support": true,
  "hsts_enabled": false,
  "hsts_subdomains": false,
  "block_exploits": true,
  "allow_websocket_upgrade": ${ws_flag},
  "enabled": true,
  "advanced_config": ""
}
EOF
)

    # Check if proxy host already exists
    local existing
    existing=$(curl -s -X GET "${NPM_API_URL}/api/nginx/proxy-hosts" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" | jq -r ".[] | select(.domain_names[0] == \"${full_domain}\") | .id" 2>/dev/null || echo "")

    if [[ -n "$existing" && "$existing" != "null" ]]; then
        log_warn "Proxy host already exists: ${full_domain} (ID: $existing)"
        log_info "Updating existing proxy host..."

        # Update existing proxy host
        curl -s -X PUT "${NPM_API_URL}/api/nginx/proxy-hosts/${existing}" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -d "$nginx_config" || {
            log_error "Failed to update proxy host"
            return 1
        }

        log_info "Updated proxy host: ${full_domain}"
        return 0
    fi

    # Create new proxy host
    local response
    response=$(curl -s -X POST "${NPM_API_URL}/api/nginx/proxy-hosts" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$nginx_config"
    ) || {
        log_error "Failed to create proxy host"
        log_debug "Response: $response"
        return 1
    }

    local result_id
    result_id=$(echo "$response" | jq -r '.id // empty')

    if [[ -z "$result_id" || "$result_id" == "null" ]]; then
        log_error "Failed to create proxy host: ${full_domain}"
        log_debug "Response: $response"
        return 1
    fi

    log_info "Created proxy host: ${full_domain} (ID: $result_id)"
    return 0
}

# Delete a proxy host by domain
npm_delete_proxy_host() {
    local domain="$1"
    local token="${2:-${NPM_TOKEN:-}}"

    [[ -n "$domain" ]] || { log_error "domain required"; return 1; }
    [[ -n "$token" ]] || { log_error "token required"; return 1; }

    # Find proxy host by domain
    local host_id
    host_id=$(curl -s -X GET "${NPM_API_URL}/api/nginx/proxy-hosts" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" | jq -r ".[] | select(.domain_names[0] == \"${domain}\") | .id" 2>/dev/null || echo "")

    if [[ -z "$host_id" || "$host_id" == "null" ]]; then
        log_warn "Proxy host not found: $domain"
        return 0
    fi

    log_info "Deleting proxy host: $domain (ID: $host_id)"

    curl -s -X DELETE "${NPM_API_URL}/api/nginx/proxy-hosts/${host_id}" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" || {
        log_error "Failed to delete proxy host: $domain"
        return 1
    }

    log_info "Deleted proxy host: $domain"
    return 0
}

# Recreate all proxy hosts
npm_recreate_all() {
    log_info "Starting recreation of all proxy hosts..."

    # Login first
    local token
    token=$(npm_login) || return 1

    # Delete existing proxy hosts with our domain suffix
    log_info "Cleaning up existing proxy hosts..."

    for subdomain in $(list_subdomains); do
        local full_domain="${subdomain}.${DOMAIN_SUFFIX}"
        npm_delete_proxy_host "$full_domain" "$token" || true
    done

    # Create all proxy hosts
    log_info "Creating proxy hosts..."

    for subdomain in $(list_subdomains); do
        local target
        target=$(get_proxy_host "$subdomain")
        local target_host target_port websocket

        # Parse target (format: "ip:port" or "ip:port:websocket")
        IFS=':' read -r target_host target_port websocket <<< "$target"

        # Handle websocket flag
        local ws_flag="false"
        if [[ "$websocket" == "websocket" ]]; then
            ws_flag="true"
        fi

        npm_create_proxy_host "$subdomain" "$target_host" "$target_port" "$ws_flag" "$token" || {
            log_error "Failed to create proxy host: ${subdomain}"
            continue
        }

        log_info "Configured: ${subdomain}.${DOMAIN_SUFFIX} -> ${target_host}:${target_port}"
    done

    log_info "Recreation complete!"
    return 0
}

#==============================================================================
# MAIN EXECUTION
#==============================================================================

usage() {
    cat <<EOF
NPM Recovery Script - Recreates Nginx Proxy Manager proxy hosts

Usage: $(basename "$0") [command]

Commands:
    login              Login to NPM API and store session
    list               List all proxy hosts
    create <domain>   Create a single proxy host (requires subdomain)
    delete <domain>  Delete a proxy host by domain
    recreate          Recreate all proxy hosts (default)

Environment Variables:
    NPM_SSH_KEY_PATH      SSH private key path
    NPM_SSH_HOST         Proxmox/NPM host IP
    NPM_SSH_PORT         SSH port
    NPM_SSH_USER        SSH username
    NPM_CONTAINER_ID     Proxmox container ID
    NPM_API_URL         NPM API URL
    NPM_API_USER       NPM admin email
    NPM_API_PASS       NPM admin password
    DUCKDNS_DOMAIN    DuckDNS subdomain
    SSL_CERT_ID        SSL certificate ID

Examples:
    $(basename "$0") login
    $(basename "$0") list
    $(basename "$0") recreate

EOF
    exit "${1:-0}"
}

# Main
main() {
    local cmd="${1:-recreate}"
    local arg="${2:-}"

    check_dependencies || exit 1

    case "$cmd" in
        login)
            npm_login
            ;;
        list)
            # Show locally configured proxy hosts (no API required)
            echo "=== Configured Proxy Hosts ==="
            echo ""
            for subdomain in $(list_subdomains); do
                local target
                target=$(get_proxy_host "$subdomain")
                local host port ws
                IFS=':' read -r host port ws <<< "$target"
                echo "  ${subdomain}.${DOMAIN_SUFFIX} -> ${host}:${port}${ws:+ ($ws)}"
            done
            echo ""
            echo "Total: $(list_subdomains | wc -l) proxy hosts"
            echo ""
            echo "To verify against NPM API, run: ./recovery.sh login && ./recovery.sh list"
            ;;
        create)
            if [[ -z "$arg" ]]; then
                log_error "Subdomain required: $(basename "$0") create <subdomain>"
                exit 1
            fi

            if [[ -z "${NPM_TOKEN:-}" ]]; then
                NPM_TOKEN=$(npm_login) || exit 1
            fi

            # Check if subdomain exists using get_proxy_host function
            local target
            if target=$(get_proxy_host "$arg"); then
                local host port ws
                IFS=':' read -r host port ws <<< "$target"
                local ws_flag="false"
                if [[ "$ws" == "websocket" ]]; then
                    ws_flag="true"
                fi
                npm_create_proxy_host "$arg" "$host" "$port" "$ws_flag" "$NPM_TOKEN"
            else
                log_error "Unknown subdomain: $arg"
                log_error "Valid subdomains: $(list_subdomains | tr '\n' ' ')"
                exit 1
            fi
            ;;
        delete)
            if [[ -z "$arg" ]]; then
                log_error "Domain required: $(basename "$0") delete <domain>"
                exit 1
            fi

            if [[ -z "${NPM_TOKEN:-}" ]]; then
                NPM_TOKEN=$(npm_login) || exit 1
            fi

            npm_delete_proxy_host "$arg" "$NPM_TOKEN"
            ;;
        recreate)
            npm_recreate_all
            ;;
        -h|--help)
            usage 0
            ;;
        *)
            log_error "Unknown command: $cmd"
            usage 1
            ;;
    esac
}

main "$@"