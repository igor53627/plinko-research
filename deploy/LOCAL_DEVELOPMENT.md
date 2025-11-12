# Local Development Workflow

This guide explains how to build, test, and deploy Docker images locally before using GitHub Actions.

## Workflow Overview

```
Local Development → Test on VKE → Commit → GitHub Actions (automated)
```

## Prerequisites

1. **Docker** installed and running
2. **kubectl** configured with VKE cluster
3. **Helm** installed
4. **GitHub Personal Access Token** with `write:packages` scope

### Create GitHub Token

1. Go to https://github.com/settings/tokens
2. Click "Generate new token (classic)"
3. Select scopes: `write:packages`, `read:packages`, `delete:packages`
4. Generate and copy token

## Step 1: Build and Push Images Locally

```bash
# Login to GitHub Container Registry
docker login ghcr.io
# Username: your-github-username
# Password: [paste your Personal Access Token]

# Build and push all images
./deploy/scripts/build-and-push-local.sh
```

This will:
- Build 6 Docker images for linux/amd64
- Tag them as `latest` and `local`
- Push to `ghcr.io/your-username/`

**Build time**: ~5-10 minutes (first build), ~2-3 minutes (with cache)

## Step 2: Deploy to VKE

```bash
# Deploy all services with LoadBalancers
./deploy/scripts/deploy-local.sh
```

This will:
- Deploy all services (enabled via values-local-dev.yaml)
- Expose Wallet UI, PIR Server, and CDN via LoadBalancer
- Wait for pods to be ready
- Display LoadBalancer IPs

**Deploy time**: ~3-5 minutes

## Step 3: Test Your Changes

### Access Services

After deployment completes, you'll see:

```
Access URLs:
  Wallet UI:   http://192.248.xxx.xxx
  PIR Server:  http://192.248.xxx.xxx:3000
  CDN:         http://192.248.xxx.xxx:8080
```

### Test Wallet UI

1. Open Wallet UI in browser
2. Enable "Privacy Mode" toggle
3. Click "Query Balance"
4. Verify PIR decoding visualization appears

### Check Logs

```bash
# View specific service logs
kubectl logs -l app=rabby-wallet -n plinko-pir
kubectl logs -l app=plinko-pir-server -n plinko-pir

# Watch all pods
kubectl get pods -n plinko-pir -w
```

### Port Forward (alternative to LoadBalancer)

```bash
# Access services locally without LoadBalancer
kubectl port-forward -n plinko-pir service/rabby-wallet 8080:80
kubectl port-forward -n plinko-pir service/plinko-pir-server 3000:3000
```

## Step 4: Iterate on Changes

### Make Code Changes

```bash
# Edit your service code
vim services/rabby-wallet/src/App.tsx

# Rebuild only changed service
docker build \
  --platform linux/amd64 \
  -t ghcr.io/your-username/plinko-rabby-wallet:latest \
  ./services/rabby-wallet

# Push updated image
docker push ghcr.io/your-username/plinko-rabby-wallet:latest

# Restart pods to pull new image
kubectl rollout restart deployment rabby-wallet -n plinko-pir

# Watch rollout status
kubectl rollout status deployment rabby-wallet -n plinko-pir
```

### Quick Deploy Single Service

```bash
# Update specific service without rebuilding all
helm upgrade plinko-pir ./deploy/helm/plinko-pir \
  -f ./deploy/helm/plinko-pir/values-vke-simple.yaml \
  -f ./deploy/helm/plinko-pir/values-local-dev.yaml \
  --set rabbyWallet.image.tag=latest \
  -n plinko-pir \
  --wait
```

## Step 5: Switch to GitHub Actions

Once everything works locally:

### 1. Commit Your Changes

```bash
git add .
git commit -m "feat: Add Plinko PIR services with LoadBalancer"
git push origin main
```

### 2. GitHub Actions Will

- Build all 6 images
- Push to ghcr.io
- Deploy to VKE cluster
- Run health checks
- Report status

### 3. Monitor Workflow

```bash
# Watch GitHub Actions
gh run watch

# Or visit:
# https://github.com/your-username/plinko-pir-research/actions
```

## Troubleshooting

### Images Not Pulling

```bash
# Verify image exists in registry
docker pull ghcr.io/your-username/plinko-rabby-wallet:latest

# Check pod events
kubectl describe pod <pod-name> -n plinko-pir
```

### LoadBalancer Stuck Pending

```bash
# Check service status
kubectl describe service rabby-wallet -n plinko-pir

# Verify Vultr LoadBalancer quota
# Dashboard → Load Balancers
```

### Pod Crash Loop

```bash
# Check logs
kubectl logs <pod-name> -n plinko-pir --previous

# Check resource limits
kubectl describe pod <pod-name> -n plinko-pir
```

### Image Pull Forbidden

```bash
# For private images, create imagePullSecret
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=your-username \
  --docker-password=YOUR_GITHUB_TOKEN \
  -n plinko-pir

# Update values-local-dev.yaml:
global:
  imagePullSecrets:
    - name: ghcr-secret
```

## Best Practices

### 1. Use Local Tags

```bash
# Tag local builds separately from GitHub Actions
docker tag image:latest image:local-dev-$(date +%Y%m%d)
```

### 2. Test Before Push

```bash
# Always test locally before pushing to GitHub
./deploy/scripts/build-and-push-local.sh
./deploy/scripts/deploy-local.sh
# Test thoroughly
git push origin main
```

### 3. Keep Branches Separate

```bash
# Use feature branches for development
git checkout -b feature/wallet-ui-improvements
# Make changes, test locally
git push origin feature/wallet-ui-improvements
# GitHub Actions will build and deploy to staging
```

### 4. Clean Up Old Images

```bash
# Remove local images
docker image prune -a

# GitHub Container Registry cleanup:
# Settings → Packages → plinko-rabby-wallet → Package settings
```

## Local vs GitHub Actions Comparison

| Feature | Local Build | GitHub Actions |
|---------|-------------|----------------|
| Build time | 2-3 min (cached) | 5-7 min (runner) |
| Cache | Local Docker cache | GitHub Actions cache |
| Deployment | Manual script | Automated on push |
| Testing | Manual verification | Automated health checks |
| Rollback | `helm rollback` | Automatic on failure |
| Use case | Development/testing | Production deploys |

## Next Steps

- Configure staging environment (separate namespace)
- Add smoke tests to deployment script
- Set up blue-green deployments
- Add Prometheus monitoring

---

**Quick Reference:**

```bash
# Full development cycle
./deploy/scripts/build-and-push-local.sh  # Build & push
./deploy/scripts/deploy-local.sh          # Deploy to VKE
curl http://<loadbalancer-ip>             # Test
git commit && git push                    # Automated deploy
```
