# Quick Fix: Make GitHub Container Registry Images Public

The deployment is failing because GitHub Container Registry images are **private by default**,  and the VKE cluster doesn't have credentials to pull them.

## Option 1: Make Images Public (Recommended for Open Source)

1. Go to https://github.com/igor53627?tab=packages
2. For each package:
   - Click the package name (e.g., `plinko-rabby-wallet`)
   - Click **Package settings** (bottom right)
   - Scroll to **Danger Zone**
   - Click **Change visibility**
   - Select **Public**
   - Confirm

Packages to make public:
- [ ] plinko-db-generator
- [ ] plinko-hint-generator
- [ ] plinko-update-service
- [ ] plinko-pir-server
- [ ] plinko-cdn-mock
- [ ] plinko-rabby-wallet

After making images public, redeploy:
```bash
KUBECONFIG=~/pse/k8s/pir-vke-*.yaml helm upgrade plinko-pir ./deploy/helm/plinko-pir \
  -f values-vke-simple.yaml \
  -f values-ingress-single-ip.yaml \
  -n plinko-pir \
  --wait --timeout 15m
```

## Option 2: Create ImagePullSecret (For Private Images)

```bash
# Create secret with your GitHub token
KUBECONFIG=~/pse/k8s/pir-vke-*.yaml kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=igor53627 \
  --docker-password=YOUR_GITHUB_TOKEN \
  -n plinko-pir

# Add to values-ingress-single-ip.yaml:
# global:
#   imagePullSecrets:
#     - name: ghcr-secret

# Redeploy
KUBECONFIG=~/pse/k8s/pir-vke-*.yaml helm upgrade plinko-pir ./deploy/helm/plinko-pir \
  -f values-vke-simple.yaml \
  -f values-ingress-single-ip.yaml \
  -n plinko-pir \
  --wait --timeout 15m
```

##Current Status

- ✅ BuildKit cache optimizations added
- ✅ NGINX Ingress Controller installed (45.77.227.177)
- ✅ GitHub Actions built all 6 images
- ❌ Images are private, cluster can't pull them
- ⏳ Waiting for images to be made public or imagePullSecret added
