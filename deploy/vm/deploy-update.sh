#!/bin/bash
# =============================================================================
# Plinko PIR - Deploy Configuration Updates to VM
# =============================================================================
# Updates:
# - Nginx reverse proxy for CDN and PIR server
# - Removes public exposure of internal services
# - Only wallet (port 80) remains publicly accessible
#

set -e

VM_IP="${VM_IP:-108.61.75.100}"
VM_USER="root"
DEPLOY_DIR="/root/plinko-pir-deploy"

echo "════════════════════════════════════════════════════════"
echo "  Plinko PIR - Configuration Update Deployment"
echo "════════════════════════════════════════════════════════"
echo ""
echo "Target VM: ${VM_USER}@${VM_IP}"
echo "Deploy Directory: ${DEPLOY_DIR}"
echo ""

# Check SSH connectivity
echo "→ Testing SSH connectivity..."
if ! ssh -o ConnectTimeout=5 ${VM_USER}@${VM_IP} "echo 'Connected'" > /dev/null 2>&1; then
    echo "❌ Error: Cannot connect to VM at ${VM_IP}"
    echo "   Please check SSH access and VM_IP environment variable"
    exit 1
fi
echo "✓ SSH connection successful"
echo ""

# Transfer updated files
echo "→ Transferring updated configuration files..."

# Create services directory on VM if it doesn't exist
ssh ${VM_USER}@${VM_IP} "mkdir -p ${DEPLOY_DIR}/services/rabby-wallet"

# Copy docker-compose.yml
echo "  • docker-compose.yml"
scp docker-compose.yml ${VM_USER}@${VM_IP}:${DEPLOY_DIR}/

# Copy wallet nginx config
echo "  • rabby-wallet nginx.conf"
scp ../../services/rabby-wallet/nginx.conf ${VM_USER}@${VM_IP}:${DEPLOY_DIR}/services/rabby-wallet/

echo "✓ Files transferred"
echo ""

# Stop existing services
echo "→ Stopping existing services..."
ssh ${VM_USER}@${VM_IP} "cd ${DEPLOY_DIR} && docker compose down"
echo "✓ Services stopped"
echo ""

# Start updated services
echo "→ Starting services with new configuration..."
ssh ${VM_USER}@${VM_IP} "cd ${DEPLOY_DIR} && docker compose up -d"
echo "✓ Services started"
echo ""

# Wait for services to be ready
echo "→ Waiting for services to initialize (30s)..."
sleep 30

# Check service status
echo "→ Checking service status..."
ssh ${VM_USER}@${VM_IP} "cd ${DEPLOY_DIR} && docker compose ps"
echo ""

# Verify wallet is accessible
echo "→ Verifying wallet accessibility..."
if curl -s -f -o /dev/null http://${VM_IP}; then
    echo "✓ Wallet UI: http://${VM_IP} (HTTP 200)"
else
    echo "⚠️  Wallet UI: http://${VM_IP} (Not ready yet)"
fi

# Verify PIR server is NOT publicly accessible
echo "→ Verifying security (PIR server should NOT be accessible)..."
if curl -s -f -o /dev/null http://${VM_IP}:3000/health 2>/dev/null; then
    echo "⚠️  WARNING: PIR Server still publicly accessible on port 3000!"
else
    echo "✓ PIR Server: Not publicly accessible (secured)"
fi

# Verify CDN is NOT publicly accessible
echo "→ Verifying security (CDN should NOT be accessible)..."
if curl -s -f -o /dev/null http://${VM_IP}:8080/hint.bin 2>/dev/null; then
    echo "⚠️  WARNING: CDN still publicly accessible on port 8080!"
else
    echo "✓ CDN: Not publicly accessible (secured)"
fi

# Verify Anvil is NOT publicly accessible
echo "→ Verifying security (Anvil should NOT be accessible)..."
if curl -s -f -o /dev/null http://${VM_IP}:8545 2>/dev/null; then
    echo "⚠️  WARNING: Anvil still publicly accessible on port 8545!"
else
    echo "✓ Anvil: Not publicly accessible (secured)"
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo "  ✅ Deployment Complete!"
echo "════════════════════════════════════════════════════════"
echo ""
echo "Next Steps:"
echo "1. Open http://${VM_IP} in your browser"
echo "2. Hard refresh (Ctrl+Shift+R / Cmd+Shift+R)"
echo "3. Enable Privacy Mode toggle"
echo "4. Click 'Query Balance'"
echo ""
echo "Expected Results:"
echo "  • Hint size: ~64 MB (not 0.0 MB)"
echo "  • Private query: Success (not 405 error)"
echo "  • Only port 80 accessible from internet"
echo ""
echo "Troubleshooting:"
echo "  View logs: ssh ${VM_USER}@${VM_IP} 'cd ${DEPLOY_DIR} && docker compose logs -f'"
echo ""
