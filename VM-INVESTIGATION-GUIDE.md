# VM Investigation Guide - 108.61.75.100

## Current Status
**VM IS UNREACHABLE** - SSH and ping both timeout with 100% packet loss.

## Quick Investigation

### Run the Investigation Script

I've created a comprehensive investigation script that will use the Vultr API to determine what happened:

```bash
# Set your Vultr API key
export VULTR_API_KEY=your-api-key-here

# Run the investigation
./investigate-vm.sh
```

**Get your Vultr API key here:** https://my.vultr.com/settings/#settingsapi

### What the Script Does

The script will:
1. ✅ Test network connectivity (ping, SSH port)
2. ✅ Find the VM instance by IP address
3. ✅ Get detailed VM status (active/stopped/destroyed)
4. ✅ Check power state (running/stopped)
5. ✅ Review firewall configuration
6. ✅ Analyze bandwidth usage
7. ✅ Provide root cause analysis
8. ✅ Give specific remediation commands

## Manual Investigation (Without Script)

If you prefer to investigate manually:

### 1. Check All VMs in Your Account

```bash
export VULTR_API_KEY=your-api-key

curl -H "Authorization: Bearer $VULTR_API_KEY" \
  https://api.vultr.com/v2/instances | jq '.instances[] | {id, label, ip: .main_ip, status, power: .power_status}'
```

### 2. Check Specific VM by IP

```bash
# Find instance ID
INSTANCE_ID=$(curl -s -H "Authorization: Bearer $VULTR_API_KEY" \
  https://api.vultr.com/v2/instances | \
  jq -r '.instances[] | select(.main_ip == "108.61.75.100") | .id')

echo "Instance ID: $INSTANCE_ID"

# Get detailed status
curl -H "Authorization: Bearer $VULTR_API_KEY" \
  https://api.vultr.com/v2/instances/$INSTANCE_ID | jq '.instance | {status, power_status, main_ip, created: .date_created}'
```

### 3. Check Power Status

```bash
curl -H "Authorization: Bearer $VULTR_API_KEY" \
  https://api.vultr.com/v2/instances/$INSTANCE_ID | \
  jq '.instance | {status, power_status, server_status}'
```

## Possible Scenarios

### Scenario 1: VM is Stopped

**Symptoms:** API shows `power_status: "stopped"`

**Possible Causes:**
- Manual shutdown via Vultr dashboard
- API call to stop the instance
- Billing/payment issue
- Resource limit reached

**Solution:**
```bash
# Start the VM
curl -X POST -H "Authorization: Bearer $VULTR_API_KEY" \
  https://api.vultr.com/v2/instances/$INSTANCE_ID/start
```

### Scenario 2: VM is Running But Unresponsive

**Symptoms:** API shows `status: "active"` and `power_status: "running"` but SSH/ping fail

**Possible Causes:**
- OS crashed or kernel panic
- SSH service crashed
- Firewall blocking all traffic
- Network misconfiguration

**Solution:**
```bash
# Reboot the VM
curl -X POST -H "Authorization: Bearer $VULTR_API_KEY" \
  https://api.vultr.com/v2/instances/$INSTANCE_ID/reboot
```

### Scenario 3: VM was Destroyed

**Symptoms:** API returns empty or "not found"

**Possible Causes:**
- Manual deletion via dashboard
- API call to destroy instance
- Billing suspension
- Trial period ended

**Solution:**
```bash
# Re-provision a new VM
cd /Users/user/pse/plinko-pir-research/deploy/vm
export VULTR_API_KEY=your-api-key
./scripts/provision-vm.sh
```

### Scenario 4: Firewall Blocking Access

**Symptoms:** VM running but specific ports blocked

**Possible Causes:**
- Vultr firewall rules too restrictive
- VM-level firewall (ufw) blocking traffic

**Solution:**
```bash
# Check firewall group
curl -H "Authorization: Bearer $VULTR_API_KEY" \
  https://api.vultr.com/v2/instances/$INSTANCE_ID | \
  jq '.instance.firewall_group_id'

# If firewall exists, check rules
FIREWALL_ID=<from-above>
curl -H "Authorization: Bearer $VULTR_API_KEY" \
  https://api.vultr.com/v2/firewall-groups/$FIREWALL_ID/rules | jq
```

## Timeline Context

From your deployment documentation:
- **VM IP:** 108.61.75.100
- **Label:** plinko-pir-research
- **Purpose:** Plinko PIR deployment with real Ethereum data
- **Last Known State:** Accessible earlier, running Plinko PIR services
- **Issue Started:** When trying to deploy real Ethereum database files

## Action Plan

### Step 1: Run Investigation
```bash
export VULTR_API_KEY=your-api-key
./investigate-vm.sh
```

### Step 2: Take Action Based on Results

**If VM is stopped:**
- Start it using API command
- Wait 2-3 minutes for boot
- Test SSH access
- Restart Docker services

**If VM is running but unresponsive:**
- Reboot via API
- Wait 3-5 minutes
- Test SSH access
- Check Docker service status

**If VM was destroyed:**
- Provision new VM
- Run setup script
- Re-deploy Plinko PIR stack
- Copy real Ethereum data

### Step 3: Restore Deployment

Once VM is accessible:

```bash
# Test SSH
ssh root@108.61.75.100

# Check Docker services
docker ps

# Restart if needed
cd /root/plinko-pir-deploy
docker compose down
docker compose up -d

# Deploy real Ethereum data (if needed)
# From local machine:
scp -r data/*.bin root@108.61.75.100:/root/plinko-pir-deploy/data/
scp deploy/vm/docker-compose-static.yml root@108.61.75.100:/root/plinko-pir-deploy/

# On VM:
ssh root@108.61.75.100
cd /root/plinko-pir-deploy
docker compose -f docker-compose-static.yml up -d
```

## Useful Vultr API Commands

### View VM in Dashboard
```bash
echo "https://my.vultr.com/compute/$INSTANCE_ID"
```

### Halt VM (Graceful Shutdown)
```bash
curl -X POST -H "Authorization: Bearer $VULTR_API_KEY" \
  https://api.vultr.com/v2/instances/$INSTANCE_ID/halt
```

### Force Reboot
```bash
curl -X POST -H "Authorization: Bearer $VULTR_API_KEY" \
  https://api.vultr.com/v2/instances/$INSTANCE_ID/reboot
```

### Check Bandwidth Usage
```bash
curl -H "Authorization: Bearer $VULTR_API_KEY" \
  https://api.vultr.com/v2/instances/$INSTANCE_ID/bandwidth | jq
```

### Delete VM (Permanent)
```bash
curl -X DELETE -H "Authorization: Bearer $VULTR_API_KEY" \
  https://api.vultr.com/v2/instances/$INSTANCE_ID
```

## Prevention

To prevent this in the future:

1. **Enable Backups** ($1.80/mo)
   ```bash
   curl -X PATCH -H "Authorization: Bearer $VULTR_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"backups": "enabled"}' \
     https://api.vultr.com/v2/instances/$INSTANCE_ID
   ```

2. **Set up Monitoring**
   - Use Vultr's monitoring dashboard
   - Set up external uptime monitoring (e.g., UptimeRobot)

3. **Document VM Management**
   - Save instance ID
   - Keep API key secure
   - Document deployment state

4. **Regular Backups**
   ```bash
   # Create snapshot
   curl -X POST -H "Authorization: Bearer $VULTR_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"description": "plinko-pir-backup"}' \
     https://api.vultr.com/v2/instances/$INSTANCE_ID/snapshot
   ```

## Files

- **Investigation Script:** `/Users/user/pse/plinko-pir-research/investigate-vm.sh`
- **VM IP:** Saved in `/tmp/plinko-pir-vm-ip.txt`
- **Deployment Config:** `/Users/user/pse/plinko-pir-research/deploy/vm/`
- **Real Data Files:** `/Users/user/pse/plinko-pir-research/data/database.bin` and `address-mapping.bin`

## Next Steps

1. **Run the investigation script** to get the exact status
2. **Take remediation action** based on the script's recommendations
3. **Restore deployment** once VM is accessible
4. **Update documentation** with findings

---

**Created:** November 12, 2025
**VM IP:** 108.61.75.100
**Issue:** SSH connection timeout, unreachable
**Status:** Investigation pending (awaiting Vultr API key)
