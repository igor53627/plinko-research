# Plinko PIR - VM Deployment

Complete VM-based deployment package for Plinko PIR research system. This package provides automated provisioning, setup, and deployment to a single Ubuntu VM using Docker Compose.

## Quick Start

```bash
# 1. Provision Vultr VM
export VULTR_API_KEY=your-api-key
./scripts/provision-vm.sh

# 2. Setup VM (install Docker & Tailscale)
./scripts/setup-vm.sh <VM_IP>

# 3. Deploy Plinko PIR
./scripts/deploy.sh <VM_IP>
```

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Deployment Steps](#deployment-steps)
- [Configuration](#configuration)
- [Services](#services)
- [Monitoring & Maintenance](#monitoring--maintenance)
- [Troubleshooting](#troubleshooting)
- [Reusability](#reusability)

## Overview

This deployment package deploys the complete Plinko PIR stack to a single VM:

- **Anvil** - Simulated Ethereum blockchain (8.4M accounts)
- **DB Generator** - Extracts account balances
- **Hint Generator** - Generates PIR hints
- **Update Service** - Real-time delta updates
- **PIR Server** - Private query server (FullSet/PunctSet PIR)
- **CDN** - Serves hint.bin and deltas
- **Wallet** - User-facing UI with Privacy Mode

### Architecture

```
┌─────────────────────────────────────────────────┐
│              Ubuntu VM (4GB RAM, 2 vCPU)        │
│                                                 │
│  ┌──────────────────────────────────────────┐  │
│  │         Docker Compose Stack              │  │
│  │                                           │  │
│  │  ┌────────┐  ┌────────────┐  ┌────────┐ │  │
│  │  │ Anvil  │──│ DB Gen     │──│ Hint   │ │  │
│  │  │ :8545  │  │ (one-shot) │  │ Gen    │ │  │
│  │  └────────┘  └────────────┘  └────────┘ │  │
│  │                                           │  │
│  │  ┌────────────┐  ┌──────────┐  ┌──────┐ │  │
│  │  │ Update Svc │  │ PIR Svr  │  │ CDN  │ │  │
│  │  │            │  │ :3000    │  │ :8080│ │  │
│  │  └────────────┘  └──────────┘  └──────┘ │  │
│  │                                           │  │
│  │  ┌────────────────────────────────────┐  │  │
│  │  │   Wallet UI (:80)                  │  │  │
│  │  └────────────────────────────────────┘  │  │
│  │                                           │  │
│  │  Volume: ~/plinko-pir/data               │  │
│  │  - database.bin                          │  │
│  │  - hint.bin                              │  │
│  │  - address-mapping.bin                   │  │
│  │  - deltas/*.bin                          │  │
│  └──────────────────────────────────────────┘  │
│                                                 │
│  Optional: Tailscale for secure access          │
└─────────────────────────────────────────────────┘
```

## Prerequisites

### Local Machine

- `bash` 4.0+
- `ssh`
- `rsync`
- `curl`
- `jq` (for Vultr API)

Install on macOS:
```bash
brew install jq rsync
```

### Vultr Account

- Vultr API key ([Get API Key](https://my.vultr.com/settings/#settingsapi))
- SSH key uploaded to Vultr (optional but recommended)

### Tailscale (Optional)

- Tailscale account and auth key ([Get Auth Key](https://login.tailscale.com/admin/settings/keys))
- Provides secure VPN access to your VM

## Deployment Steps

### Step 1: Provision VM

The provision script creates an Ubuntu 22.04 VM on Vultr.

```bash
# Set your Vultr API key
export VULTR_API_KEY=your-api-key

# Optional: Customize VM configuration
export VM_REGION=ewr          # New Jersey (default)
export VM_PLAN=vc2-2c-4gb     # 2 vCPU, 4GB RAM (default)
export VM_LABEL=plinko-pir    # VM label

# Provision VM
./scripts/provision-vm.sh
```

**Available Regions:**
```bash
# List available regions
VULTR_API_KEY=xxx ./scripts/provision-vm.sh --list-regions

# Common options:
# ewr - New Jersey
# lax - Los Angeles
# fra - Frankfurt
# sin - Singapore
```

**Available Plans:**
```bash
# List available plans
VULTR_API_KEY=xxx ./scripts/provision-vm.sh --list-plans

# Recommended plans:
# vc2-2c-4gb  - 2 vCPU, 4GB RAM, 80GB SSD ($18/mo)
# vc2-4c-8gb  - 4 vCPU, 8GB RAM, 160GB SSD ($36/mo)
```

**Output:**
The script saves the VM IP address to `/tmp/plinko-pir-vm-ip.txt` for use in subsequent steps.

### Step 2: Setup VM

The setup script installs Docker, Docker Compose, and Tailscale on the VM.

```bash
# Get VM IP from previous step
VM_IP=$(cat /tmp/plinko-pir-vm-ip.txt)

# Optional: Set Tailscale auth key for automatic setup
export TAILSCALE_KEY=your-tailscale-auth-key

# Run setup
./scripts/setup-vm.sh $VM_IP
```

**What it does:**
- Installs Docker Engine and Docker Compose
- Installs Tailscale VPN
- Creates directory structure
- Installs utilities (git, htop, vim, tmux, jq)

**Time:** ~2-3 minutes

### Step 3: Deploy Plinko PIR

The deploy script transfers files and starts the Docker Compose stack.

```bash
# Get VM IP
VM_IP=$(cat /tmp/plinko-pir-vm-ip.txt)

# Deploy
./scripts/deploy.sh $VM_IP
```

**What it does:**
1. Transfers docker-compose.yml and nginx.conf
2. Creates environment configuration
3. Pulls Docker images (~5-10 min)
4. Starts services
5. Monitors initialization
6. Verifies deployment

**Initialization Timeline:**
- Anvil: ~2-5 minutes (8.4M accounts)
- DB Generation: ~3-5 minutes
- Hint Generation: ~2-3 minutes
- **Total:** ~10-15 minutes

### Step 4: Access Services

Once deployment is complete, access your services:

```bash
# Wallet UI
open http://$VM_IP

# PIR Server Health
curl http://$VM_IP:3000/health

# CDN (hint.bin)
curl http://$VM_IP:8080/hint.bin | head -c 32 | xxd

# Anvil RPC
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://$VM_IP:8545
```

## Configuration

### Environment Variables

Edit `.env` on the VM to customize:

```bash
ssh root@$VM_IP
cd ~/plinko-pir-deploy
vi .env
```

```bash
# VM Configuration
VM_IP=45.77.227.177
DATA_DIR=/root/plinko-pir/data

# Wallet Configuration
VITE_PIR_SERVER_URL=http://45.77.227.177:3000
VITE_CDN_URL=http://45.77.227.177:8080
VITE_FALLBACK_RPC=https://eth.llamarpc.com
```

After changes, restart services:
```bash
docker compose up -d --force-recreate rabby-wallet
```

### Docker Compose Configuration

The `docker-compose.yml` defines all services. Modify it for:

- Resource limits (CPU, memory)
- Port mappings
- Volume mounts
- Service replicas (for load balancing)

```bash
ssh root@$VM_IP
cd ~/plinko-pir-deploy
vi docker-compose.yml
docker compose up -d
```

## Services

### Service Details

| Service | Port | Description | Health Check |
|---------|------|-------------|--------------|
| Anvil | 8545 | Simulated Ethereum blockchain | `nc -z localhost 8545` |
| DB Generator | - | One-shot database extraction | Exits on completion |
| Hint Generator | - | One-shot hint generation | Exits on completion |
| Update Service | - | Real-time delta updates | `test -d /data/deltas` |
| PIR Server | 3000 | Private query endpoint | `curl :3000/health` |
| CDN | 8080 | Static file server | `curl :8080/health` |
| Wallet | 80 | User-facing UI | `curl :80/` |

### Service Dependencies

```
Anvil
  └─> DB Generator
        └─> Hint Generator
              ├─> Update Service
              ├─> PIR Server
              └─> CDN
                    └─> Wallet
```

### Data Persistence

All data is stored in a Docker volume mapped to `~/plinko-pir/data`:

```bash
ssh root@$VM_IP
ls -lh ~/plinko-pir/data/

# Expected files:
# database.bin        (~64MB)
# hint.bin           (~20MB)
# address-mapping.bin (~200KB)
# deltas/            (directory with delta-*.bin files)
```

## Monitoring & Maintenance

### View Logs

```bash
# All services
ssh root@$VM_IP 'cd ~/plinko-pir-deploy && docker compose logs -f'

# Specific service
ssh root@$VM_IP 'docker logs -f plinko-pir-server'

# Last 100 lines
ssh root@$VM_IP 'docker logs --tail 100 plinko-update-service'
```

### Service Status

```bash
# Check all containers
ssh root@$VM_IP 'cd ~/plinko-pir-deploy && docker compose ps'

# Check specific service
ssh root@$VM_IP 'docker ps | grep plinko-pir-server'

# Resource usage
ssh root@$VM_IP 'docker stats'
```

### Restart Services

```bash
# Restart all
ssh root@$VM_IP 'cd ~/plinko-pir-deploy && docker compose restart'

# Restart specific service
ssh root@$VM_IP 'docker restart plinko-pir-server'

# Stop all
ssh root@$VM_IP 'cd ~/plinko-pir-deploy && docker compose down'

# Start all
ssh root@$VM_IP 'cd ~/plinko-pir-deploy && docker compose up -d'
```

### Update Services

```bash
# Pull latest images
ssh root@$VM_IP 'cd ~/plinko-pir-deploy && docker compose pull'

# Recreate containers with new images
ssh root@$VM_IP 'cd ~/plinko-pir-deploy && docker compose up -d --force-recreate'
```

### Backup Data

```bash
# Create backup
ssh root@$VM_IP 'tar -czf /tmp/plinko-data-backup.tar.gz -C ~/plinko-pir/data .'

# Download backup
scp root@$VM_IP:/tmp/plinko-data-backup.tar.gz ./backups/

# Restore backup
scp ./backups/plinko-data-backup.tar.gz root@$VM_IP:/tmp/
ssh root@$VM_IP 'tar -xzf /tmp/plinko-data-backup.tar.gz -C ~/plinko-pir/data'
```

## Troubleshooting

### VM Not Accessible

```bash
# Check VM status via Vultr API
curl -H "Authorization: Bearer $VULTR_API_KEY" \
  https://api.vultr.com/v2/instances

# Check firewall rules
ssh root@$VM_IP 'ufw status'

# Disable firewall (if needed)
ssh root@$VM_IP 'ufw disable'
```

### Services Not Starting

```bash
# Check logs
ssh root@$VM_IP 'cd ~/plinko-pir-deploy && docker compose logs'

# Check disk space
ssh root@$VM_IP 'df -h'

# Check memory
ssh root@$VM_IP 'free -h'

# Restart Docker daemon
ssh root@$VM_IP 'systemctl restart docker'
```

### Initialization Failures

```bash
# Check DB generation
ssh root@$VM_IP 'docker logs plinko-db-generator'

# Check hint generation
ssh root@$VM_IP 'docker logs plinko-hint-generator'

# Re-run initialization
ssh root@$VM_IP 'cd ~/plinko-pir-deploy && docker compose restart db-generator hint-generator'
```

### Wallet Not Loading

```bash
# Check wallet logs
ssh root@$VM_IP 'docker logs plinko-rabby-wallet'

# Check nginx access logs
ssh root@$VM_IP 'docker exec plinko-rabby-wallet cat /var/log/nginx/access.log'

# Rebuild wallet (if needed)
cd services/rabby-wallet
docker build --platform linux/amd64 -t ghcr.io/igor53627/plinko-rabby-wallet:latest .
docker push ghcr.io/igor53627/plinko-rabby-wallet:latest
```

### PIR Queries Failing

```bash
# Check PIR server health
curl http://$VM_IP:3000/health

# Check PIR server logs
ssh root@$VM_IP 'docker logs -f plinko-pir-server'

# Check if hint file exists
ssh root@$VM_IP 'ls -lh ~/plinko-pir/data/hint.bin'

# Test direct PIR query
curl -X POST http://$VM_IP:3000/query/plaintext \
  -H "Content-Type: application/json" \
  -d '{"address":"0x0000000000000000000000000000000000000001"}'
```

## Reusability

This deployment package is designed to be reusable for other research applications. To adapt it:

### 1. Customize docker-compose.yml

Replace services with your own containers:

```yaml
services:
  your-service:
    image: your-registry/your-image:latest
    ports:
      - "8000:8000"
    environment:
      - CONFIG_VAR=value
    volumes:
      - your-data:/data
```

### 2. Update Provisioning Scripts

Modify `scripts/provision-vm.sh` for different VM requirements:

```bash
# Larger VM for compute-intensive apps
VM_PLAN=vc2-4c-8gb  # 4 vCPU, 8GB RAM

# Different region for latency
VM_REGION=fra  # Frankfurt
```

### 3. Customize Setup Script

Add your own dependencies in `scripts/setup-vm.sh`:

```bash
install_your_dependencies() {
    run_remote "Installing custom dependencies..." \
        "sudo apt-get install -y your-package-here"
}
```

### 4. Parameterize Configuration

Use environment variables for flexibility:

```yaml
environment:
  - SERVICE_URL=${SERVICE_URL}
  - API_KEY=${API_KEY}
```

### 5. Template Package Structure

```
deploy/vm/
├── scripts/
│   ├── provision-vm.sh      # VM provisioning (customize VM_PLAN)
│   ├── setup-vm.sh          # VM setup (add dependencies)
│   └── deploy.sh            # Deployment (update service checks)
├── config/
│   └── your-config.conf     # Service configurations
├── docker-compose.yml        # Service definitions
└── README.md                # Documentation
```

### Example: Adapt for New Project

```bash
# 1. Copy the deployment package
cp -r deploy/vm ~/my-project/deploy/

# 2. Update docker-compose.yml with your services
cd ~/my-project/deploy/vm
vi docker-compose.yml

# 3. Update deployment script
vi scripts/deploy.sh
# - Change service names
# - Update health check endpoints
# - Modify initialization monitoring

# 4. Deploy to new VM
VULTR_API_KEY=xxx ./scripts/provision-vm.sh
./scripts/setup-vm.sh <VM_IP>
./scripts/deploy.sh <VM_IP>
```

## Cost Estimation

### Vultr VM Costs

| Plan | vCPU | RAM | Disk | Monthly | Hourly |
|------|------|-----|------|---------|--------|
| vc2-2c-4gb | 2 | 4GB | 80GB | $18 | $0.024 |
| vc2-4c-8gb | 4 | 8GB | 160GB | $36 | $0.048 |
| vc2-8c-16gb | 8 | 16GB | 320GB | $72 | $0.095 |

### Additional Costs

- **Bandwidth:** 2TB included, $0.01/GB overage
- **Backups:** $1.80/mo (10% of VM cost) - optional
- **DDoS Protection:** Free basic, $10/mo advanced - optional
- **Block Storage:** $1/10GB/mo - if needed

### Tailscale Costs

- **Personal:** Free (1 user, 20 devices)
- **Premium:** $48/year/user

## License

MIT License - see LICENSE file

## Support

For issues or questions:
- GitHub Issues: https://github.com/yourusername/plinko-pir-research/issues
- Email: your-email@example.com

## References

- [Plinko PIR Paper](https://eprint.iacr.org/...)
- [Vultr API Docs](https://www.vultr.com/api/)
- [Docker Compose Docs](https://docs.docker.com/compose/)
- [Tailscale Docs](https://tailscale.com/kb/)
