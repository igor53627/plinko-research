#!/usr/bin/env bash
#
# Vultr VM Provisioning Script
# Provisions an Ubuntu VM on Vultr for Plinko PIR deployment
#
# Usage: ./provision-vm.sh [OPTIONS]
#
# Environment Variables:
#   VULTR_API_KEY       - Vultr API key (required)
#   VM_REGION           - Vultr region ID (default: ewr - New Jersey)
#   VM_PLAN             - Vultr plan ID (default: vc2-2c-4gb)
#   VM_OS_ID            - OS ID (default: 1743 - Ubuntu 22.04 x64)
#   VM_LABEL            - VM label (default: plinko-pir-research)
#   SSH_KEY_ID          - Vultr SSH key ID (optional)
#

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default configuration
VULTR_API_URL="https://api.vultr.com/v2"
VM_REGION="${VM_REGION:-ewr}"          # New Jersey
VM_PLAN="${VM_PLAN:-vc2-2c-4gb}"       # 2 vCPU, 4GB RAM, 80GB SSD
VM_OS_ID="${VM_OS_ID:-1743}"           # Ubuntu 22.04 x64
VM_LABEL="${VM_LABEL:-plinko-pir-research}"
VM_HOSTNAME="${VM_HOSTNAME:-plinko-pir}"
VM_TAG="${VM_TAG:-plinko-pir}"
ENABLE_IPV6="${ENABLE_IPV6:-false}"
ENABLE_BACKUPS="${ENABLE_BACKUPS:-false}"
DDOS_PROTECTION="${DDOS_PROTECTION:-false}"

# Logging
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    if [[ -z "${VULTR_API_KEY:-}" ]]; then
        log_error "VULTR_API_KEY environment variable not set"
        echo ""
        echo "Usage: VULTR_API_KEY=your-api-key $0"
        exit 1
    fi

    if ! command -v curl &> /dev/null; then
        log_error "curl is required but not installed"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed (brew install jq)"
        exit 1
    fi
}

# Make Vultr API call
vultr_api() {
    local method=$1
    local endpoint=$2
    local data=${3:-}

    if [[ -n "$data" ]]; then
        curl -s -X "$method" \
            -H "Authorization: Bearer ${VULTR_API_KEY}" \
            -H "Content-Type: application/json" \
            --data "$data" \
            "${VULTR_API_URL}${endpoint}"
    else
        curl -s -X "$method" \
            -H "Authorization: Bearer ${VULTR_API_KEY}" \
            "${VULTR_API_URL}${endpoint}"
    fi
}

# List available regions
list_regions() {
    log_info "Available Vultr regions:"
    vultr_api GET "/regions" | jq -r '.regions[] | "\(.id)\t\(.city)\t\(.country)"' | column -t
}

# List available plans
list_plans() {
    log_info "Available Vultr plans:"
    vultr_api GET "/plans" | jq -r '.plans[] | select(.type == "vc2") | "\(.id)\t\(.vcpu_count) vCPU\t\(.ram) MB\t\(.disk) GB\t$\(.monthly_cost)/mo"' | column -t
}

# List available OS images
list_os() {
    log_info "Available Ubuntu images:"
    vultr_api GET "/os" | jq -r '.os[] | select(.family == "ubuntu") | "\(.id)\t\(.name)"' | column -t
}

# Check if VM already exists
check_existing_vm() {
    local label=$1
    local existing=$(vultr_api GET "/instances" | jq -r ".instances[] | select(.label == \"$label\") | .id")

    if [[ -n "$existing" ]]; then
        log_warn "VM with label '$label' already exists (ID: $existing)"
        echo "$existing"
        return 0
    fi
    return 1
}

# Create VM instance
create_vm() {
    log_info "Creating Vultr VM..."
    log_info "  Region: $VM_REGION"
    log_info "  Plan: $VM_PLAN"
    log_info "  OS: Ubuntu 22.04 (ID: $VM_OS_ID)"
    log_info "  Label: $VM_LABEL"

    # Build JSON payload
    local payload=$(cat <<EOF
{
    "region": "$VM_REGION",
    "plan": "$VM_PLAN",
    "os_id": $VM_OS_ID,
    "label": "$VM_LABEL",
    "hostname": "$VM_HOSTNAME",
    "tag": "$VM_TAG",
    "enable_ipv6": $ENABLE_IPV6,
    "backups": "$ENABLE_BACKUPS",
    "ddos_protection": $DDOS_PROTECTION
}
EOF
)

    # Add SSH key if provided
    if [[ -n "${SSH_KEY_ID:-}" ]]; then
        payload=$(echo "$payload" | jq --arg key "$SSH_KEY_ID" '. + {sshkey_id: [$key]}')
    fi

    # Create instance
    local response=$(vultr_api POST "/instances" "$payload")
    local instance_id=$(echo "$response" | jq -r '.instance.id // empty')

    if [[ -z "$instance_id" ]]; then
        log_error "Failed to create VM:"
        echo "$response" | jq .
        exit 1
    fi

    log_info "VM created successfully (ID: $instance_id)"
    echo "$instance_id"
}

# Wait for VM to be ready
wait_for_vm() {
    local instance_id=$1
    local max_wait=300  # 5 minutes
    local elapsed=0

    log_info "Waiting for VM to be ready..."

    while [[ $elapsed -lt $max_wait ]]; do
        local status=$(vultr_api GET "/instances/$instance_id" | jq -r '.instance.status')
        local power_status=$(vultr_api GET "/instances/$instance_id" | jq -r '.instance.power_status')

        if [[ "$status" == "active" && "$power_status" == "running" ]]; then
            log_info "VM is ready!"
            return 0
        fi

        echo -ne "\r  Status: $status | Power: $power_status | Elapsed: ${elapsed}s"
        sleep 5
        elapsed=$((elapsed + 5))
    done

    echo ""
    log_error "VM did not become ready within ${max_wait}s"
    return 1
}

# Get VM information
get_vm_info() {
    local instance_id=$1

    log_info "VM Information:"
    vultr_api GET "/instances/$instance_id" | jq -r '.instance | "
ID:         \(.id)
Label:      \(.label)
Region:     \(.region)
Plan:       \(.plan)
OS:         \(.os)
Status:     \(.status)
Power:      \(.power_status)
Main IP:    \(.main_ip)
Internal IP:\(.internal_ip)
RAM:        \(.ram) MB
vCPUs:      \(.vcpu_count)
Disk:       \(.disk) GB
Bandwidth:  \(.allowed_bandwidth) GB/mo
Created:    \(.date_created)
"'

    # Extract IP address
    local main_ip=$(vultr_api GET "/instances/$instance_id" | jq -r '.instance.main_ip')
    echo ""
    log_info "VM IP Address: $main_ip"
    echo "$main_ip" > /tmp/plinko-pir-vm-ip.txt
    log_info "IP address saved to: /tmp/plinko-pir-vm-ip.txt"
}

# Main execution
main() {
    log_info "=== Vultr VM Provisioning for Plinko PIR ==="
    echo ""

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --list-regions)
                list_regions
                exit 0
                ;;
            --list-plans)
                list_plans
                exit 0
                ;;
            --list-os)
                list_os
                exit 0
                ;;
            --help)
                cat <<EOF
Vultr VM Provisioning Script

Usage: $0 [OPTIONS]

Options:
    --list-regions      List available Vultr regions
    --list-plans        List available Vultr plans
    --list-os           List available Ubuntu images
    --help              Show this help message

Environment Variables:
    VULTR_API_KEY       Vultr API key (required)
    VM_REGION           Vultr region ID (default: ewr - New Jersey)
    VM_PLAN             Vultr plan ID (default: vc2-2c-4gb - 2vCPU, 4GB RAM)
    VM_OS_ID            OS ID (default: 1743 - Ubuntu 22.04 x64)
    VM_LABEL            VM label (default: plinko-pir-research)
    VM_HOSTNAME         VM hostname (default: plinko-pir)
    SSH_KEY_ID          Vultr SSH key ID (optional)
    ENABLE_IPV6         Enable IPv6 (default: false)
    ENABLE_BACKUPS      Enable automatic backups (default: false)
    DDOS_PROTECTION     Enable DDoS protection (default: false)

Examples:
    # List available options
    VULTR_API_KEY=xxx $0 --list-regions
    VULTR_API_KEY=xxx $0 --list-plans

    # Provision VM with defaults
    VULTR_API_KEY=xxx $0

    # Provision VM in specific region
    VULTR_API_KEY=xxx VM_REGION=sjc $0

    # Provision larger VM
    VULTR_API_KEY=xxx VM_PLAN=vc2-4c-8gb $0

EOF
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
        shift
    done

    check_prerequisites

    # Check for existing VM
    if existing_id=$(check_existing_vm "$VM_LABEL"); then
        log_warn "Using existing VM"
        instance_id="$existing_id"
    else
        # Create new VM
        instance_id=$(create_vm)
    fi

    # Wait for VM to be ready
    wait_for_vm "$instance_id"
    echo ""

    # Display VM information
    get_vm_info "$instance_id"

    echo ""
    log_info "=== Next Steps ==="
    echo ""
    echo "1. Wait ~2 minutes for VM to fully initialize"
    echo "2. Run setup script to install Docker and Tailscale:"
    echo "   ./deploy/vm/scripts/setup-vm.sh"
    echo ""
    echo "3. Deploy Plinko PIR containers:"
    echo "   ./deploy/vm/scripts/deploy.sh"
    echo ""
}

main "$@"
