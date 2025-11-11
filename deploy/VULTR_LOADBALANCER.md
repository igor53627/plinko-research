# Vultr LoadBalancer Configuration for Plinko PIR

This guide explains how to configure Vultr's LoadBalancer to provide external access to your Plinko PIR services running on VKE.

## Overview

Vultr LoadBalancer provides:
- **External IP addresses** for services
- **SSL/TLS termination** (optional)
- **Health checks** for backend pods
- **DDoS protection**
- **Automatic failover** between pods

**Documentation**: https://docs.vultr.com/products/load-balancer

---

## Prerequisites

1. Vultr VKE cluster running with Plinko PIR deployed
2. Services configured with `type: LoadBalancer` in Helm values
3. Vultr account with LoadBalancer add-on enabled

---

## Method 1: Kubernetes Service Type LoadBalancer (Recommended)

Vultr VKE automatically provisions LoadBalancers for services with `type: LoadBalancer`.

### Step 1: Update Helm Values

Edit `values-vke-simple.yaml`:

```yaml
# Enable external access for services
rabbyWallet:
  enabled: true
  service:
    type: LoadBalancer
    port: 80
    annotations:
      service.beta.kubernetes.io/vultr-loadbalancer-protocol: "tcp"
      service.beta.kubernetes.io/vultr-loadbalancer-ssl: "false"
      service.beta.kubernetes.io/vultr-loadbalancer-ssl-redirect: "false"
      # Optional: Sticky sessions
      service.beta.kubernetes.io/vultr-loadbalancer-sticky-session-enabled: "true"
      service.beta.kubernetes.io/vultr-loadbalancer-sticky-session-cookie-name: "lb_cookie"

plinkoPirServer:
  enabled: true
  service:
    type: LoadBalancer
    port: 3000
    annotations:
      service.beta.kubernetes.io/vultr-loadbalancer-protocol: "tcp"

cdnMock:
  enabled: true
  service:
    type: LoadBalancer
    port: 8080
    annotations:
      service.beta.kubernetes.io/vultr-loadbalancer-protocol: "tcp"
```

### Step 2: Deploy/Update

```bash
export KUBECONFIG=~/pse/k8s/pir-vke-*.yaml

helm upgrade plinko-pir ./deploy/helm/plinko-pir \
  -f ./deploy/helm/plinko-pir/values-vke-simple.yaml \
  -n plinko-pir \
  --wait
```

### Step 3: Get LoadBalancer IPs

Wait 2-5 minutes for Vultr to provision LoadBalancers:

```bash
kubectl get services -n plinko-pir

# Output:
# NAME                    TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)
# plinko-pir-rabby-wallet LoadBalancer   10.96.0.1       167.179.123.45  80:30080/TCP
# plinko-pir-server       LoadBalancer   10.96.0.2       167.179.123.46  3000:30000/TCP
# plinko-cdn-mock         LoadBalancer   10.96.0.3       167.179.123.47  8080:30080/TCP
```

### Step 4: Test Access

```bash
# Test Rabby Wallet UI
curl http://167.179.123.45

# Test PIR Server
curl http://167.179.123.46:3000/health

# Test CDN
curl http://167.179.123.47:8080/health
```

---

## Method 2: Manual Vultr LoadBalancer (Advanced)

For more control, create LoadBalancer manually in Vultr control panel.

### Step 1: Create LoadBalancer in Vultr

1. Go to Vultr Dashboard → Load Balancers
2. Click "Deploy New Load Balancer"
3. Select same datacenter as your VKE cluster
4. Configure:
   - **Protocol**: HTTP or TCP
   - **Port**: 80 (for HTTP) or 443 (for HTTPS)
   - **Backend Port**: Match your service port
   - **Algorithm**: Round Robin or Least Connection
   - **Health Check**: HTTP GET on `/health` endpoint

### Step 2: Add Backend Nodes

1. In LoadBalancer settings, click "Backend Instances"
2. Add your VKE cluster nodes:
   - Get node IPs: `kubectl get nodes -o wide`
   - Add each node with NodePort

### Step 3: Configure DNS (Optional)

Point your domain to LoadBalancer IP:

```bash
# Example DNS records
wallet.plinko-pir.com   A   167.179.123.45
api.plinko-pir.com      A   167.179.123.46
cdn.plinko-pir.com      A   167.179.123.47
```

---

## LoadBalancer Annotations Reference

### Common Annotations

```yaml
annotations:
  # Protocol (tcp, udp, http, https)
  service.beta.kubernetes.io/vultr-loadbalancer-protocol: "tcp"

  # SSL/TLS configuration
  service.beta.kubernetes.io/vultr-loadbalancer-ssl: "true"
  service.beta.kubernetes.io/vultr-loadbalancer-ssl-redirect: "true"
  service.beta.kubernetes.io/vultr-loadbalancer-certificate: "cert-id-here"

  # Health check configuration
  service.beta.kubernetes.io/vultr-loadbalancer-health-check-protocol: "http"
  service.beta.kubernetes.io/vultr-loadbalancer-health-check-port: "80"
  service.beta.kubernetes.io/vultr-loadbalancer-health-check-path: "/health"
  service.beta.kubernetes.io/vultr-loadbalancer-health-check-interval: "15"
  service.beta.kubernetes.io/vultr-loadbalancer-health-check-timeout: "5"
  service.beta.kubernetes.io/vultr-loadbalancer-health-check-healthy-threshold: "3"
  service.beta.kubernetes.io/vultr-loadbalancer-health-check-unhealthy-threshold: "5"

  # Session affinity (sticky sessions)
  service.beta.kubernetes.io/vultr-loadbalancer-sticky-session-enabled: "true"
  service.beta.kubernetes.io/vultr-loadbalancer-sticky-session-cookie-name: "lb_cookie"

  # Algorithm (round_robin, least_conn, ip_hash)
  service.beta.kubernetes.io/vultr-loadbalancer-algorithm: "round_robin"

  # Proxy protocol (v1, v2, or disabled)
  service.beta.kubernetes.io/vultr-loadbalancer-proxy-protocol: "disabled"
```

### SSL/TLS Example

```yaml
# With Let's Encrypt or custom certificate
annotations:
  service.beta.kubernetes.io/vultr-loadbalancer-protocol: "https"
  service.beta.kubernetes.io/vultr-loadbalancer-ssl: "true"
  service.beta.kubernetes.io/vultr-loadbalancer-ssl-redirect: "true"
  service.beta.kubernetes.io/vultr-loadbalancer-certificate: "your-cert-id"

  # Force HTTPS redirect
  service.beta.kubernetes.io/vultr-loadbalancer-ssl-redirect: "true"
```

---

## Production Configuration Example

```yaml
# values-vke-production.yaml

# Rabby Wallet - Public HTTPS
rabbyWallet:
  enabled: true
  service:
    type: LoadBalancer
    port: 443
    annotations:
      # HTTPS with SSL
      service.beta.kubernetes.io/vultr-loadbalancer-protocol: "https"
      service.beta.kubernetes.io/vultr-loadbalancer-ssl: "true"
      service.beta.kubernetes.io/vultr-loadbalancer-ssl-redirect: "true"
      service.beta.kubernetes.io/vultr-loadbalancer-certificate: "cert-id"

      # Health checks
      service.beta.kubernetes.io/vultr-loadbalancer-health-check-protocol: "http"
      service.beta.kubernetes.io/vultr-loadbalancer-health-check-port: "80"
      service.beta.kubernetes.io/vultr-loadbalancer-health-check-path: "/"
      service.beta.kubernetes.io/vultr-loadbalancer-health-check-interval: "10"

      # Sticky sessions for wallet
      service.beta.kubernetes.io/vultr-loadbalancer-sticky-session-enabled: "true"
      service.beta.kubernetes.io/vultr-loadbalancer-sticky-session-cookie-name: "plinko_wallet_session"

# PIR Server - API endpoint
plinkoPirServer:
  enabled: true
  service:
    type: LoadBalancer
    port: 443
    annotations:
      service.beta.kubernetes.io/vultr-loadbalancer-protocol: "https"
      service.beta.kubernetes.io/vultr-loadbalancer-ssl: "true"
      service.beta.kubernetes.io/vultr-loadbalancer-certificate: "cert-id"

      # API health checks
      service.beta.kubernetes.io/vultr-loadbalancer-health-check-protocol: "http"
      service.beta.kubernetes.io/vultr-loadbalancer-health-check-port: "3000"
      service.beta.kubernetes.io/vultr-loadbalancer-health-check-path: "/health"

# CDN - Static content delivery
cdnMock:
  enabled: true
  service:
    type: LoadBalancer
    port: 443
    annotations:
      service.beta.kubernetes.io/vultr-loadbalancer-protocol: "https"
      service.beta.kubernetes.io/vultr-loadbalancer-ssl: "true"
      service.beta.kubernetes.io/vultr-loadbalancer-certificate: "cert-id"
```

---

## Verification Steps

### 1. Check LoadBalancer Provisioning

```bash
# Watch service status
kubectl get services -n plinko-pir -w

# Check LoadBalancer events
kubectl describe service plinko-pir-rabby-wallet -n plinko-pir
```

### 2. Test External Access

```bash
# Get external IPs
WALLET_IP=$(kubectl get svc plinko-pir-rabby-wallet -n plinko-pir -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
PIR_IP=$(kubectl get svc plinko-pir-server -n plinko-pir -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
CDN_IP=$(kubectl get svc plinko-cdn-mock -n plinko-pir -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Test connectivity
curl -I http://$WALLET_IP
curl http://$PIR_IP:3000/health
curl -I http://$CDN_IP:8080/health
```

### 3. Check Health Status in Vultr Dashboard

1. Go to Vultr Dashboard → Load Balancers
2. Click on your LoadBalancer
3. Check "Health Status" tab
4. Verify all backend instances are "Healthy"

---

## Troubleshooting

### LoadBalancer Stuck in "Pending"

```bash
# Check events
kubectl describe service <service-name> -n plinko-pir

# Common causes:
# 1. No LoadBalancer quota available (check Vultr limits)
# 2. Invalid annotations
# 3. Service selector doesn't match pods
```

**Solution**:
1. Verify Vultr account has LoadBalancer add-on enabled
2. Check service selector: `kubectl get pods -n plinko-pir --show-labels`
3. Review annotations for typos

### Health Checks Failing

```bash
# Check pod logs
kubectl logs -l app=rabby-wallet -n plinko-pir

# Test health endpoint directly
kubectl port-forward svc/plinko-pir-rabby-wallet 8080:80 -n plinko-pir
curl http://localhost:8080/health
```

**Solution**:
- Ensure health check path exists
- Verify health check port matches container port
- Check if pod is ready: `kubectl get pods -n plinko-pir`

### SSL Certificate Issues

```bash
# Get certificate ID from Vultr
vultr-cli certificate list

# Update annotation
kubectl annotate service plinko-pir-rabby-wallet \
  service.beta.kubernetes.io/vultr-loadbalancer-certificate="new-cert-id" \
  --overwrite \
  -n plinko-pir
```

### Connection Timeout

```bash
# Check security groups/firewall
kubectl get service plinko-pir-rabby-wallet -n plinko-pir -o yaml

# Verify LoadBalancer is routing to correct NodePort
kubectl get endpoints plinko-pir-rabby-wallet -n plinko-pir
```

---

## Cost Considerations

**Vultr LoadBalancer Pricing** (as of 2024):
- $10/month per LoadBalancer
- 100 Mbps bandwidth included
- Additional bandwidth: $0.01/GB

**Cost Estimate for Plinko PIR**:
- 3 LoadBalancers (wallet, PIR server, CDN) = $30/month
- Expected bandwidth: ~500 GB/month = $5/month
- **Total**: ~$35/month

**Optimization**:
- Use single LoadBalancer with path-based routing (Ingress controller)
- Reduces cost to $10/month

---

## Advanced: Ingress Controller (Cost Optimization)

For production, consider using a single LoadBalancer with Ingress:

### Install Ingress-NGINX

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer
```

### Configure Ingress

```yaml
# ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: plinko-pir-ingress
  namespace: plinko-pir
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: wallet.plinko-pir.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: plinko-pir-rabby-wallet
            port:
              number: 80

  - host: api.plinko-pir.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: plinko-pir-server
            port:
              number: 3000

  - host: cdn.plinko-pir.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: plinko-cdn-mock
            port:
              number: 8080
```

**Result**: Single LoadBalancer serving all domains = $10/month savings

---

## Next Steps

1. **Configure LoadBalancer** using Method 1 (Kubernetes annotations)
2. **Test external access** from outside the cluster
3. **Set up DNS** (optional) for production domains
4. **Enable SSL/TLS** with Let's Encrypt or Vultr certificates
5. **Monitor health** via Vultr dashboard
6. **Consider Ingress controller** for cost optimization

---

**References**:
- [Vultr LoadBalancer Docs](https://docs.vultr.com/products/load-balancer)
- [Vultr VKE Documentation](https://docs.vultr.com/vultr-kubernetes-engine)
- [Kubernetes Service LoadBalancer](https://kubernetes.io/docs/concepts/services-networking/service/#loadbalancer)
