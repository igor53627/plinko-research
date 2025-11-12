#!/usr/bin/env bash
#
# VM Setup Script
# Installs Docker, Docker Compose, and Tailscale on Ubuntu VM
#
# Usage: ./setup-vm.sh [VM_IP]
#
# Environment Variables:
#   VM_IP               - VM IP address (or pass as argument)
#   TAILSCALE_KEY       - Tailscale auth key (optional)
#   SSH_USER            - SSH user (default: root)
#   SSH_KEY             - SSH private key path (optional)
#

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SSH_USER="${SSH_USER:-root}"
SSH_KEY="${SSH_KEY:-}"
VM_IP="${1:-${VM_IP:-}}"

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
    if [[ -z "$VM_IP" ]]; then
        log_error "VM IP address not provided"
        echo ""
        echo "Usage: $0 <VM_IP>"
        echo "   or: VM_IP=<ip> $0"
        echo ""
        echo "You can find your VM IP in /tmp/plinko-pir-vm-ip.txt"
        exit 1
    fi

    if ! command -v ssh &> /dev/null; then
        log_error "ssh is required but not installed"
        exit 1
    fi

    log_info "VM IP: $VM_IP"
    log_info "SSH User: $SSH_USER"
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

# Wait for VM SSH to be ready
wait_for_ssh() {
    log_info "Waiting for SSH to be ready..."
    local max_wait=120
    local elapsed=0

    while [[ $elapsed -lt $max_wait ]]; do
        if ssh_cmd "echo 'SSH Ready'" &> /dev/null; then
            log_info "SSH connection established!"
            return 0
        fi

        echo -ne "\r  Attempting connection... ${elapsed}s"
        sleep 5
        elapsed=$((elapsed + 5))
    done

    echo ""
    log_error "SSH did not become available within ${max_wait}s"
    return 1
}

# Run remote command with output
run_remote() {
    local description=$1
    shift
    log_info "$description"
    ssh_cmd "$@"
}

# Install Docker
install_docker() {
    log_info "=== Installing Docker ==="

    run_remote "Updating package index..." "sudo apt-get update -qq"

    run_remote "Installing prerequisites..." \
        "sudo apt-get install -y -qq ca-certificates curl gnupg lsb-release"

    run_remote "Adding Docker GPG key..." \
        "sudo mkdir -p /etc/apt/keyrings && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg"

    run_remote "Adding Docker repository..." \
        "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null"

    run_remote "Updating package index (Docker)..." "sudo apt-get update -qq"

    run_remote "Installing Docker Engine..." \
        "sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"

    run_remote "Starting Docker service..." \
        "sudo systemctl start docker && sudo systemctl enable docker"

    run_remote "Adding user to docker group..." \
        "sudo usermod -aG docker ${SSH_USER} || true"

    log_info "Docker installed successfully"

    # Verify installation
    local docker_version=$(ssh_cmd "docker --version")
    log_info "Docker version: $docker_version"
}

# Install Tailscale
install_tailscale() {
    log_info "=== Installing Tailscale ==="

    run_remote "Adding Tailscale GPG key..." \
        "curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg > /dev/null"

    run_remote "Adding Tailscale repository..." \
        "echo \"deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu jammy main\" | sudo tee /etc/apt/sources.list.d/tailscale.list > /dev/null"

    run_remote "Updating package index (Tailscale)..." "sudo apt-get update -qq"

    run_remote "Installing Tailscale..." \
        "sudo apt-get install -y -qq tailscale"

    log_info "Tailscale installed successfully"

    # Start Tailscale
    if [[ -n "${TAILSCALE_KEY:-}" ]]; then
        log_info "Authenticating Tailscale with auth key..."
        run_remote "Starting Tailscale with auth key..." \
            "sudo tailscale up --authkey=${TAILSCALE_KEY} --ssh"
        log_info "Tailscale authenticated and connected"
    else
        log_warn "No TAILSCALE_KEY provided"
        log_info "Starting Tailscale (manual auth required)..."
        run_remote "Starting Tailscale..." "sudo tailscale up --ssh" || true
        echo ""
        log_warn "Please authenticate Tailscale manually:"
        echo "  1. SSH into the VM: ssh ${SSH_USER}@${VM_IP}"
        echo "  2. Run: sudo tailscale up --ssh"
        echo "  3. Follow the authentication URL"
        echo ""
    fi
}

# Install additional utilities
install_utilities() {
    log_info "=== Installing Additional Utilities ==="

    run_remote "Installing utilities..." \
        "sudo apt-get install -y -qq git htop vim tmux jq net-tools"

    log_info "Utilities installed successfully"
}

# Create directory structure
create_directories() {
    log_info "=== Creating Directory Structure ==="

    run_remote "Creating plinko-pir directories..." \
        "mkdir -p ~/plinko-pir/{data,config,logs} && mkdir -p ~/plinko-pir/data/deltas"

    log_info "Directory structure created"
}

# Display system information
display_system_info() {
    log_info "=== System Information ==="

    log_info "OS Information:"
    ssh_cmd "lsb_release -a 2>/dev/null | grep -v 'No LSB modules'"

    echo ""
    log_info "System Resources:"
    ssh_cmd "echo \"CPU: \$(nproc) cores\" && echo \"RAM: \$(free -h | grep Mem | awk '{print \$2}')\" && echo \"Disk: \$(df -h / | tail -1 | awk '{print \$2}')\""

    echo ""
    log_info "Docker Version:"
    ssh_cmd "docker --version && docker compose version"

    echo ""
    log_info "Tailscale Status:"
    ssh_cmd "sudo tailscale status --peers=false" || log_warn "Tailscale not authenticated yet"
}

# Main execution
main() {
    log_info "=== Plinko PIR VM Setup ==="
    echo ""

    check_prerequisites

    # Wait for SSH
    wait_for_ssh
    echo ""

    # Install components
    install_docker
    echo ""

    install_tailscale
    echo ""

    install_utilities
    echo ""

    create_directories
    echo ""

    display_system_info
    echo ""

    log_info "=== Setup Complete ==="
    echo ""
    echo "VM is now ready for Plinko PIR deployment!"
    echo ""
    echo "Next steps:"
    echo "  1. If Tailscale requires manual auth, complete that first"
    echo "  2. Deploy Plinko PIR: ./deploy/vm/scripts/deploy.sh $VM_IP"
    echo ""
    echo "SSH into VM:"
    echo "  ssh ${SSH_USER}@${VM_IP}"
    echo ""

    # Save VM info for deployment script
    cat > /tmp/plinko-pir-vm-info.env <<EOF
VM_IP=$VM_IP
SSH_USER=$SSH_USER
EOF
    log_info "VM info saved to: /tmp/plinko-pir-vm-info.env"
}

main "$@"
