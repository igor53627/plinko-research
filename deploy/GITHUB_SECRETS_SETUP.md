# GitHub Secrets Setup for VKE Deployment

This guide explains how to configure GitHub Secrets for automated CI/CD deployment to Vultr VKE.

## Required GitHub Secret

Only **ONE** secret is required for GitHub Actions:

### VKE_KUBECONFIG

**Purpose**: Kubernetes configuration file for accessing your VKE cluster

**Location**: `~/pse/k8s/pir-vke-kubeconfig-base64.txt` (already created)

**How to add**:

1. **Copy the base64-encoded kubeconfig**:
   ```bash
   cat ~/pse/k8s/pir-vke-kubeconfig-base64.txt
   ```

2. **Add to GitHub**:
   - Go to your repository: https://github.com/igor53627/plinko-pir-research
   - Click **Settings** → **Secrets and variables** → **Actions**
   - Click **New repository secret**
   - Name: `VKE_KUBECONFIG`
   - Value: Paste the entire base64 string from step 1
   - Click **Add secret**

**Security**: This secret contains your cluster credentials. Never commit it to the repository.

---

## Docker Registry: GitHub Container Registry (ghcr.io)

**No additional secrets needed!**

The workflow automatically uses:
- **Registry**: `ghcr.io/igor53627` (GitHub Container Registry)
- **Username**: `${{ github.actor }}` (automatically provided)
- **Password**: `${{ secrets.GITHUB_TOKEN }}` (automatically provided by GitHub)

Docker images will be pushed to:
```
ghcr.io/igor53627/plinko-db-generator:latest
ghcr.io/igor53627/plinko-hint-generator:latest
ghcr.io/igor53627/plinko-update-service:latest
ghcr.io/igor53627/plinko-pir-server:latest
ghcr.io/igor53627/plinko-cdn-mock:latest
ghcr.io/igor53627/plinko-rabby-wallet:latest
```

---

## Verification

After adding the secret, verify the GitHub Actions workflow:

1. Go to **Actions** tab in your repository
2. Click **Deploy to Vultr VKE** workflow
3. Click **Run workflow** → **Run workflow**
4. Monitor the deployment progress

The workflow will:
1. ✅ Build Docker images and push to ghcr.io
2. ✅ Deploy to your VKE cluster using the kubeconfig
3. ✅ Verify deployment and get LoadBalancer IPs
4. ✅ Run health checks
5. ✅ Generate deployment summary

---

## Troubleshooting

### Secret Not Working

```bash
# Test kubeconfig locally first
export KUBECONFIG=~/pse/k8s/pir-vke-cdedc8ce-ce47-4242-bbd7-16ef74a88a99.yaml
kubectl get nodes

# If that works, regenerate base64
base64 -i ~/pse/k8s/pir-vke-cdedc8ce-ce47-4242-bbd7-16ef74a88a99.yaml \
  -o ~/pse/k8s/pir-vke-kubeconfig-base64.txt
```

### GitHub Actions Failing

Check the workflow logs:
1. Go to **Actions** tab
2. Click on the failed run
3. Expand the failing step to see error details

Common issues:
- **"Invalid kubeconfig"**: Secret not set correctly
- **"Permission denied"**: GitHub token needs packages:write permission (should be automatic)
- **"No space left"**: GitHub runner out of disk space (retry)

---

## Security Best Practices

1. ✅ **Never commit kubeconfig** - Already in `.gitignore`
2. ✅ **Rotate secrets periodically** - Update VKE kubeconfig every 90 days
3. ✅ **Use least privilege** - Kubeconfig has namespace-scoped permissions
4. ✅ **Monitor access** - Check GitHub Actions logs regularly
5. ✅ **Backup secrets** - Keep encrypted backup of kubeconfig locally

---

## Optional: Enable Package Visibility

Make Docker images public or private:

1. Go to https://github.com/igor53627?tab=packages
2. Click on a package (e.g., `plinko-db-generator`)
3. Click **Package settings**
4. Under **Danger Zone**, choose visibility:
   - **Public**: Anyone can pull images (recommended for open source)
   - **Private**: Only you and collaborators can pull (default)

For public images, update Helm values:
```yaml
# No imagePullSecrets needed for public images
global:
  imagePullSecrets: []
```

For private images, create imagePullSecret in cluster:
```bash
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=igor53627 \
  --docker-password=$GITHUB_TOKEN \
  -n plinko-pir
```

---

## Summary

**Required GitHub Secrets**: 1
- ✅ `VKE_KUBECONFIG` - Created at `~/pse/k8s/pir-vke-kubeconfig-base64.txt`

**Docker Registry**: GitHub Container Registry (ghcr.io)
- ✅ No additional secrets needed
- ✅ Automatic authentication via `GITHUB_TOKEN`

**Next Steps**:
1. Add `VKE_KUBECONFIG` secret to GitHub
2. Trigger GitHub Actions workflow
3. Monitor deployment
4. Access services via LoadBalancer IPs
