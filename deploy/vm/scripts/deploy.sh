#!/usr/bin/env bash
#
# Plinko PIR Deployment Script
# Deploys the complete Plinko PIR stack to a Docker-enabled VM
#
# Usage: ./deploy.sh [VM_IP]
#
# Environment Variables:
#   VM_IP          - VM IP address (or pass as argument)
#   SSH_USER       - SSH user (default: root)
#   SSH_KEY        - SSH private key path (optional)
#   DATA_DIR       - Data directory on VM (default: ~/plinko-pir/data)
#

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DEPLOY_DIR="$PROJECT_ROOT/deploy/vm"

SSH_USER="${SSH_USER:-root}"
SSH_KEY="${SSH_KEY:-}"
VM_IP="${1:-${VM_IP:-}}"
DATA_DIR="${DATA_DIR:-/root/plinko-pir/data}"

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

log_step() {
    echo -e "\n${BLUE}===${NC} $1 ${BLUE}===${NC}\n"
}

# Check prerequisites
check_prerequisites() {
    if [[ -z "$VM_IP" ]]; then
        # Try to load from saved info
        if [[ -f /tmp/plinko-pir-vm-info.env ]]; then
            source /tmp/plinko-pir-vm-info.env
        fi

        if [[ -z "$VM_IP" ]]; then
            log_error "VM IP address not provided"
            echo ""
            echo "Usage: $0 <VM_IP>"
            echo "   or: VM_IP=<ip> $0"
            exit 1
        fi
    fi

    if ! command -v ssh &> /dev/null; then
        log_error "ssh is required but not installed"
        exit 1
    fi

    if ! command -v rsync &> /dev/null; then
        log_error "rsync is required but not installed"
        exit 1
    fi

    log_info "Deployment Configuration:"
    log_info "  VM IP: $VM_IP"
    log_info "  SSH User: $SSH_USER"
    log_info "  Data Directory: $DATA_DIR"
    log_info "  Project Root: $PROJECT_ROOT"
}

# Build SSH command
ssh_cmd() {
    local cmd_args=()

    if [[ -n "$SSH_KEY" ]]; then
        cmd_args+=(-i "$SSH_KEY")
    fi

    cmd_args+=(-o StrictHostKeyChecking=no)
    cmd_args+=(-o UserKnownHostsFile=/dev/null)
    cmd_args+=(-o ConnectTimeout=10)

    ssh "${cmd_args[@]}" "${SSH_USER}@${VM_IP}" "$@"
}

# Build rsync command
rsync_cmd() {
    local rsync_args=()

    if [[ -n "$SSH_KEY" ]]; then
        rsync_args+=(-e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null")
    else
        rsync_args+=(-e "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null")
    fi

    rsync -avz --progress "${rsync_args[@]}" "$@"
}

# Transfer deployment files to VM
transfer_files() {
    log_step "Transferring Deployment Files"

    log_info "Creating remote directories..."
    ssh_cmd "mkdir -p ~/plinko-pir-deploy"

    log_info "Copying docker-compose.yml..."
    rsync_cmd "$DEPLOY_DIR/docker-compose.yml" "${SSH_USER}@${VM_IP}:~/plinko-pir-deploy/"

    log_info "Copying nginx configuration..."
    rsync_cmd "$DEPLOY_DIR/config/nginx.conf" "${SSH_USER}@${VM_IP}:~/plinko-pir-deploy/"

    log_info "Files transferred successfully"
}

# Create environment file
create_env_file() {
    log_step "Creating Environment Configuration"

    local env_content=$(cat <<EOF
# Plinko PIR Environment Configuration
VM_IP=$VM_IP
DATA_DIR=$DATA_DIR
SSH_USER=$SSH_USER
VITE_PIR_SERVER_URL=http://$VM_IP:3000
VITE_CDN_URL=http://$VM_IP:8080
VITE_FALLBACK_RPC=https://eth.llamarpc.com
EOF
)

    echo "$env_content" | ssh_cmd "cat > ~/plinko-pir-deploy/.env"
    log_info "Environment file created"

    echo ""
    log_info "Environment configuration:"
    echo "$env_content" | sed 's/^/  /'
    echo ""
}

# Pull Docker images
pull_images() {
    log_step "Pulling Docker Images"

    log_info "This may take 5-10 minutes depending on network speed..."

    ssh_cmd "cd ~/plinko-pir-deploy && docker compose pull" || {
        log_error "Failed to pull Docker images"
        exit 1
    }

    log_info "All images pulled successfully"
}

# Start services
start_services() {
    log_step "Starting Services"

    log_info "Starting Docker Compose stack..."
    ssh_cmd "cd ~/plinko-pir-deploy && docker compose up -d"

    log_info "Services started successfully"
}

# Monitor initialization
monitor_initialization() {
    log_step "Monitoring Initialization"

    log_info "Waiting for Anvil to initialize (8.4M accounts)..."
    log_warn "This can take 2-5 minutes..."

    local max_wait=300
    local elapsed=0

    while [[ $elapsed -lt $max_wait ]]; do
        if ssh_cmd "docker logs plinko-eth-mock 2>&1 | grep -q 'Listening on'" &> /dev/null; then
            echo ""
            log_info "Anvil is ready!"
            break
        fi
        echo -ne "\r  Waiting... ${elapsed}s elapsed"
        sleep 5
        elapsed=$((elapsed + 5))
    done

    if [[ $elapsed -ge $max_wait ]]; then
        echo ""
        log_warn "Anvil initialization taking longer than expected"
        log_info "Check logs: ssh $SSH_USER@$VM_IP 'docker logs -f plinko-eth-mock'"
    fi

    echo ""
    log_info "Waiting for DB generation to complete..."
    log_warn "This can take 3-5 minutes..."

    while ssh_cmd "docker ps -a | grep plinko-db-generator | grep -q 'Up\|Restarting'" &> /dev/null; do
        echo -ne "\r  DB generation in progress..."
        sleep 5
    done

    if ssh_cmd "docker ps -a | grep plinko-db-generator | grep -q 'Exited (0)'" &> /dev/null; then
        echo ""
        log_info "DB generation completed successfully"
    else
        echo ""
        log_error "DB generation may have failed"
        log_info "Check logs: ssh $SSH_USER@$VM_IP 'docker logs plinko-db-generator'"
    fi

    echo ""
    log_info "Waiting for Hint generation to complete..."
    log_warn "This can take 2-3 minutes..."

    while ssh_cmd "docker ps -a | grep plinko-hint-generator | grep -q 'Up\|Restarting'" &> /dev/null; do
        echo -ne "\r  Hint generation in progress..."
        sleep 5
    done

    if ssh_cmd "docker ps -a | grep plinko-hint-generator | grep -q 'Exited (0)'" &> /dev/null; then
        echo ""
        log_info "Hint generation completed successfully"
    else
        echo ""
        log_error "Hint generation may have failed"
        log_info "Check logs: ssh $SSH_USER@$VM_IP 'docker logs plinko-hint-generator'"
    fi
}

# Verify deployment
verify_deployment() {
    log_step "Verifying Deployment"

    log_info "Checking service health..."
    echo ""

    # Check PIR Server
    if curl -sf "http://$VM_IP:3000/health" &> /dev/null; then
        log_info "✓ PIR Server: http://$VM_IP:3000/health"
    else
        log_warn "✗ PIR Server: Not responding"
    fi

    # Check CDN
    if curl -sf "http://$VM_IP:8080/health" &> /dev/null; then
        log_info "✓ CDN: http://$VM_IP:8080/health"
    else
        log_warn "✗ CDN: Not responding"
    fi

    # Check Wallet
    if curl -sf "http://$VM_IP/" &> /dev/null; then
        log_info "✓ Wallet UI: http://$VM_IP/"
    else
        log_warn "✗ Wallet UI: Not responding"
    fi

    # Check Anvil
    if curl -sf -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "http://$VM_IP:8545" &> /dev/null; then
        log_info "✓ Anvil RPC: http://$VM_IP:8545"
    else
        log_warn "✗ Anvil RPC: Not responding"
    fi

    echo ""
    log_info "Container Status:"
    ssh_cmd "cd ~/plinko-pir-deploy && docker compose ps"
}

# Display final instructions
display_instructions() {
    log_step "Deployment Complete!"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_info "Plinko PIR is now running!"
    echo ""
    echo "Access Points:"
    echo "  Wallet UI:    http://$VM_IP"
    echo "  PIR Server:   http://$VM_IP:3000/health"
    echo "  CDN:          http://$VM_IP:8080/hint.bin"
    echo "  Anvil RPC:    http://$VM_IP:8545"
    echo ""
    echo "SSH into VM:"
    echo "  ssh $SSH_USER@$VM_IP"
    echo ""
    echo "View Logs:"
    echo "  ssh $SSH_USER@$VM_IP 'cd ~/plinko-pir-deploy && docker compose logs -f'"
    echo "  ssh $SSH_USER@$VM_IP 'docker logs -f plinko-pir-server'"
    echo "  ssh $SSH_USER@$VM_IP 'docker logs -f plinko-update-service'"
    echo ""
    echo "Restart Services:"
    echo "  ssh $SSH_USER@$VM_IP 'cd ~/plinko-pir-deploy && docker compose restart'"
    echo ""
    echo "Stop Services:"
    echo "  ssh $SSH_USER@$VM_IP 'cd ~/plinko-pir-deploy && docker compose down'"
    echo ""
    echo "Test Privacy Mode:"
    echo "  1. Open http://$VM_IP in your browser"
    echo "  2. Enable 'Privacy Mode' toggle"
    echo "  3. Click 'Query Balance'"
    echo "  4. Watch the Plinko PIR decoding visualization!"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Main execution
main() {
    log_step "Plinko PIR Deployment"

    check_prerequisites
    echo ""

    transfer_files
    create_env_file
    pull_images
    start_services
    monitor_initialization
    verify_deployment
    display_instructions

    log_info "Deployment completed successfully!"
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            cat <<EOF
Plinko PIR Deployment Script

Usage: $0 [OPTIONS] [VM_IP]

Options:
    --help          Show this help message

Environment Variables:
    VM_IP           VM IP address (or pass as first argument)
    SSH_USER        SSH user (default: root)
    SSH_KEY         SSH private key path (optional)
    DATA_DIR        Data directory on VM (default: ~/plinko-pir/data)

Examples:
    # Deploy to VM
    $0 45.77.227.177

    # Deploy with custom SSH user
    SSH_USER=ubuntu $0 45.77.227.177

    # Deploy with SSH key
    SSH_KEY=~/.ssh/vultr_rsa $0 45.77.227.177

EOF
            exit 0
            ;;
        *)
            VM_IP=$1
            shift
            ;;
    esac
done

main
