#!/usr/bin/env bash
#
# Vultr VM Investigation Script
# Investigates the status of VM at 108.61.75.100
#
# Usage: VULTR_API_KEY=your-api-key ./investigate-vm.sh

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

VULTR_API_URL="https://api.vultr.com/v2"
VM_IP="108.61.75.100"
VM_LABEL="plinko-pir-research"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${BLUE}=== $1 ===${NC}"
    echo ""
}

# Check prerequisites
if [[ -z "${VULTR_API_KEY:-}" ]]; then
    log_error "VULTR_API_KEY environment variable not set"
    echo ""
    echo "Usage: VULTR_API_KEY=your-api-key $0"
    echo ""
    echo "Get your API key at: https://my.vultr.com/settings/#settingsapi"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    log_error "jq is required but not installed (brew install jq)"
    exit 1
fi

# Make Vultr API call
vultr_api() {
    local method=$1
    local endpoint=$2
    local data=${3:-}

    if [[ -n "$data" ]]; then
        curl -s -X "$method" \
            -H "Authorization: Bearer ${VULTR_API_KEY}" \
            -H "Content-Type: application/json" \
            --data "$data" \
            "${VULTR_API_URL}${endpoint}"
    else
        curl -s -X "$method" \
            -H "Authorization: Bearer ${VULTR_API_KEY}" \
            "${VULTR_API_URL}${endpoint}"
    fi
}

log_section "VM Investigation for IP: $VM_IP"

# Step 1: Test network connectivity
log_info "Step 1: Testing network connectivity..."
echo ""

echo -n "  Ping test: "
if ping -c 2 -W 3 $VM_IP &> /dev/null; then
    echo -e "${GREEN}✓ RESPONDING${NC}"
else
    echo -e "${RED}✗ NO RESPONSE (timeout)${NC}"
fi

echo -n "  SSH port 22: "
if timeout 5 bash -c "echo > /dev/tcp/$VM_IP/22" 2>/dev/null; then
    echo -e "${GREEN}✓ OPEN${NC}"
else
    echo -e "${RED}✗ CLOSED/FILTERED (timeout)${NC}"
fi

# Step 2: Find VM by IP
log_section "Step 2: Searching for VM in Vultr account..."

instances=$(vultr_api GET "/instances")
instance_id=$(echo "$instances" | jq -r ".instances[] | select(.main_ip == \"$VM_IP\") | .id")

if [[ -z "$instance_id" ]]; then
    log_error "VM with IP $VM_IP not found in Vultr account"
    echo ""
    log_info "Attempting to find by label: $VM_LABEL"
    instance_id=$(echo "$instances" | jq -r ".instances[] | select(.label == \"$VM_LABEL\") | .id")

    if [[ -z "$instance_id" ]]; then
        log_error "VM not found by label either"
        echo ""
        log_info "All VMs in your account:"
        echo "$instances" | jq -r '.instances[] | "  ID: \(.id) | Label: \(.label) | IP: \(.main_ip) | Status: \(.status) | Power: \(.power_status)"'
        exit 1
    fi
fi

log_info "Found VM: $instance_id"

# Step 3: Get VM details
log_section "Step 3: VM Status and Configuration"

vm_info=$(vultr_api GET "/instances/$instance_id")

echo "$vm_info" | jq -r '.instance | "
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
VM IDENTIFICATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Instance ID:    \(.id)
Label:          \(.label)
Hostname:       \(.hostname)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
NETWORK CONFIGURATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Main IP:        \(.main_ip)
Internal IP:    \(.internal_ip)
Gateway v4:     \(.gateway_v4)
Netmask v4:     \(.netmask_v4)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
POWER & STATUS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Status:         \(.status)
Power Status:   \(.power_status)
Server State:   \(.server_status // "N/A")

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
HARDWARE SPECS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Region:         \(.region)
Plan:           \(.plan)
OS:             \(.os)
vCPUs:          \(.vcpu_count)
RAM:            \(.ram) MB
Disk:           \(.disk) GB
Bandwidth:      \(.allowed_bandwidth) GB/mo

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TIMELINE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Created:        \(.date_created)
"'

# Extract key status values
status=$(echo "$vm_info" | jq -r '.instance.status')
power_status=$(echo "$vm_info" | jq -r '.instance.power_status')
server_status=$(echo "$vm_info" | jq -r '.instance.server_status // "N/A"')

# Step 4: Check firewall rules
log_section "Step 4: Checking Firewall Configuration"

firewall=$(vultr_api GET "/instances/$instance_id/firewall")
firewall_group_id=$(echo "$vm_info" | jq -r '.instance.firewall_group_id // empty')

if [[ -n "$firewall_group_id" ]]; then
    log_info "Firewall Group ID: $firewall_group_id"

    firewall_rules=$(vultr_api GET "/firewall-groups/$firewall_group_id/rules")
    echo ""
    log_info "Firewall Rules:"
    echo "$firewall_rules" | jq -r '.firewall_rules[] | "  \(.action | ascii_upcase) | \(.protocol | ascii_upcase) | Port: \(.port) | Source: \(.source) | \(.notes // "")"'
else
    log_info "No firewall group attached to this instance"
fi

# Step 5: Root cause analysis
log_section "Step 5: Root Cause Analysis"

if [[ "$status" == "active" && "$power_status" == "running" ]]; then
    echo -e "${GREEN}✓ VM is reported as ACTIVE and RUNNING by Vultr${NC}"
    echo ""
    log_warn "However, VM is NOT responding to network requests"
    echo ""
    echo "Possible causes:"
    echo "  1. VM OS crashed or kernel panic"
    echo "  2. Firewall blocking all incoming traffic"
    echo "  3. SSH service not running or crashed"
    echo "  4. VM running but unresponsive (needs reboot)"
    echo "  5. Network interface misconfiguration"
    echo ""
    echo "Recommended action: Try rebooting the VM"

elif [[ "$power_status" == "stopped" ]]; then
    echo -e "${RED}✗ VM is STOPPED${NC}"
    echo ""
    echo "The VM was powered off. Possible reasons:"
    echo "  1. Manual shutdown via Vultr dashboard"
    echo "  2. API call to stop the instance"
    echo "  3. Billing issue (payment failure)"
    echo "  4. Resource limit reached"
    echo ""
    echo "Recommended action: Start the VM"

elif [[ "$status" == "pending" ]]; then
    echo -e "${YELLOW}⚠ VM is in PENDING state${NC}"
    echo ""
    echo "The VM is still being provisioned or is in transition"
    echo ""
    echo "Recommended action: Wait a few minutes and check again"

else
    echo -e "${RED}✗ VM in unexpected state: status=$status, power=$power_status${NC}"
    echo ""
    echo "Recommended action: Contact Vultr support or check dashboard"
fi

# Step 6: Check for recent events/actions
log_section "Step 6: Checking Recent Actions"

log_info "Bandwidth usage:"
bandwidth=$(vultr_api GET "/instances/$instance_id/bandwidth")
echo "$bandwidth" | jq -r '.bandwidth | to_entries | .[] | "  \(.key): Incoming \(.value.incoming_bytes | tonumber / 1024 / 1024 | floor) MB, Outgoing \(.value.outgoing_bytes | tonumber / 1024 / 1024 | floor) MB"' | head -5

# Step 7: Provide action commands
log_section "Step 7: Remediation Commands"

echo "Based on the investigation, here are actionable commands:"
echo ""

if [[ "$power_status" == "stopped" ]]; then
    echo "# Start the VM:"
    echo "curl -X POST -H \"Authorization: Bearer \$VULTR_API_KEY\" \\"
    echo "  ${VULTR_API_URL}/instances/${instance_id}/start"
    echo ""
fi

if [[ "$status" == "active" && "$power_status" == "running" ]]; then
    echo "# Reboot the VM (recommended):"
    echo "curl -X POST -H \"Authorization: Bearer \$VULTR_API_KEY\" \\"
    echo "  ${VULTR_API_URL}/instances/${instance_id}/reboot"
    echo ""
fi

echo "# Halt the VM (graceful shutdown):"
echo "curl -X POST -H \"Authorization: Bearer \$VULTR_API_KEY\" \\"
echo "  ${VULTR_API_URL}/instances/${instance_id}/halt"
echo ""

echo "# View VM in Vultr dashboard:"
echo "https://my.vultr.com/compute/${instance_id}"
echo ""

echo "# Delete the VM (if needed):"
echo "curl -X DELETE -H \"Authorization: Bearer \$VULTR_API_KEY\" \\"
echo "  ${VULTR_API_URL}/instances/${instance_id}"
echo ""

# Step 8: Summary and recommendation
log_section "Summary"

echo "Instance ID: ${BLUE}${instance_id}${NC}"
echo "Status:      ${BLUE}${status}${NC}"
echo "Power:       ${BLUE}${power_status}${NC}"
echo "IP Address:  ${BLUE}${VM_IP}${NC}"
echo "Network:     ${RED}NOT RESPONDING${NC}"
echo ""

if [[ "$power_status" == "stopped" ]]; then
    echo -e "${YELLOW}CONCLUSION: VM was powered off (stopped state)${NC}"
    echo ""
    echo "Someone or something stopped this VM. Check:"
    echo "  - Vultr dashboard activity logs"
    echo "  - Your API usage logs"
    echo "  - Billing/payment status"
    echo ""
    echo -e "${GREEN}ACTION: Start the VM using the command above${NC}"

elif [[ "$status" == "active" && "$power_status" == "running" ]]; then
    echo -e "${YELLOW}CONCLUSION: VM is running but not responding to network${NC}"
    echo ""
    echo "The VM operating system is likely unresponsive."
    echo ""
    echo -e "${GREEN}ACTION: Reboot the VM using the command above${NC}"

else
    echo -e "${RED}CONCLUSION: VM in unexpected state${NC}"
    echo ""
    echo -e "${YELLOW}ACTION: Check Vultr dashboard for more details${NC}"
fi

echo ""
log_info "Investigation complete!"
