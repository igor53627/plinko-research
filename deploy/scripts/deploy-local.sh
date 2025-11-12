#!/bin/bash
# Deploy to VKE from local machine
# Usage: ./deploy/scripts/deploy-local.sh

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Local Deployment to VKE ===${NC}"

# Set kubeconfig
export KUBECONFIG=~/pse/k8s/pir-vke-cdedc8ce-ce47-4242-bbd7-16ef74a88a99.yaml

# Verify cluster connectivity
echo -e "${BLUE}1. Verifying cluster connectivity...${NC}"
kubectl cluster-info
echo ""

# Deploy with Helm
echo -e "${BLUE}2. Deploying with Helm...${NC}"
cd "$(dirname "$0")/../helm/plinko-pir"

helm upgrade plinko-pir . \
  -f values-vke-simple.yaml \
  -f values-local-dev.yaml \
  -n plinko-pir \
  --wait \
  --timeout 10m \
  --atomic \
  --cleanup-on-fail

echo ""
echo -e "${BLUE}3. Checking deployment status...${NC}"
kubectl get pods -n plinko-pir
echo ""
kubectl get services -n plinko-pir
echo ""

echo -e "${GREEN}=== Deployment complete! ===${NC}"
echo ""
echo "Waiting for LoadBalancer IPs (this may take 2-5 minutes)..."
sleep 30

# Get LoadBalancer IPs
WALLET_IP=$(kubectl get svc rabby-wallet -n plinko-pir -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
PIR_IP=$(kubectl get svc plinko-pir-server -n plinko-pir -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
CDN_IP=$(kubectl get svc cdn-mock -n plinko-pir -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")

echo -e "${GREEN}Access URLs:${NC}"
echo "  Wallet UI:   http://${WALLET_IP}"
echo "  PIR Server:  http://${PIR_IP}:3000"
echo "  CDN:         http://${CDN_IP}:8080"
