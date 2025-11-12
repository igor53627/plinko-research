#!/bin/bash
# Build and push Docker images locally to GitHub Container Registry
# Usage: ./deploy/scripts/build-and-push-local.sh

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Local Docker Build and Push ===${NC}"

# Get GitHub username
GITHUB_USER=$(git config user.name | tr '[:upper:]' '[:lower:]')
REGISTRY="ghcr.io/${GITHUB_USER}"

echo -e "${BLUE}Registry: ${REGISTRY}${NC}"
echo ""

# Login to GitHub Container Registry
echo -e "${BLUE}1. Logging in to GitHub Container Registry...${NC}"
echo "   Run: docker login ghcr.io"
echo "   Username: ${GITHUB_USER}"
echo "   Password: Your GitHub Personal Access Token (with write:packages scope)"
echo ""
read -p "Press Enter after you've logged in..."

# Build and push each service
SERVICES=(
  "db-generator:plinko-db-generator"
  "plinko-hint-generator:plinko-hint-generator"
  "plinko-update-service:plinko-update-service"
  "plinko-pir-server:plinko-pir-server"
  "cdn-mock:plinko-cdn-mock"
  "rabby-wallet:plinko-rabby-wallet"
)

for SERVICE_PAIR in "${SERVICES[@]}"; do
  IFS=':' read -r DIR NAME <<< "$SERVICE_PAIR"

  echo -e "${BLUE}2. Building ${NAME}...${NC}"
  docker build \
    --platform linux/amd64 \
    -t ${REGISTRY}/${NAME}:latest \
    -t ${REGISTRY}/${NAME}:local \
    ./services/${DIR}

  echo -e "${BLUE}3. Pushing ${NAME}...${NC}"
  docker push ${REGISTRY}/${NAME}:latest
  docker push ${REGISTRY}/${NAME}:local

  echo -e "${GREEN}✓ ${NAME} complete${NC}"
  echo ""
done

echo -e "${GREEN}=== All images built and pushed! ===${NC}"
echo ""
echo "Next steps:"
echo "1. Update values file to enable services"
echo "2. Deploy with Helm: ./deploy/scripts/deploy-local.sh"
