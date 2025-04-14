#!/bin/bash
# setup-monitoring.sh - Configure Azure Monitor and Log Analytics for Cribl FIPS VM
set -e

# Text formatting
BOLD=$(tput bold)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1)
RESET=$(tput sgr0)

# Display banner
echo "${BOLD}Cribl FIPS VM Monitoring Setup${RESET}"
echo "------------------------------"

# Configuration
RESOURCE_GROUP=${1:-"cribl-fips-rg"}
VM_NAME=${2:-"cribl-fips-vm"}
WORKSPACE_NAME=${3:-"cribl-logs-workspace"}
LOCATION=${4:-"eastus"}

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "${RED}Error: Azure CLI is not installed.${RESET}"
    exit 1
fi

# Check if logged in
if ! az account show &> /dev/null; then
    echo "${YELLOW}You need to login to Azure CLI first.${RESET}"
    az login
fi

echo "${BOLD}Creating Log Analytics Workspace...${RESET}"
# Create Log Analytics workspace if it doesn't exist
if ! az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$WORKSPACE_NAME" &> /dev/null; then
    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$WORKSPACE_NAME" \
        --location "$LOCATION" \
        --sku PerGB2018
    echo "${GREEN}✓ Log Analytics workspace created${RESET}"
else
    echo "${GREEN}✓ Using existing Log Analytics workspace${RESET}"
fi

# Get workspace ID and key
WORKSPACE_ID=$(az monitor log-analytics workspace show \
    --resource-group "$RESOURCE_GROUP" \
    --workspace-name "$WORKSPACE_NAME" \
    --query "customerId" -o tsv)

WORKSPACE_KEY=$(az monitor log-analytics workspace get-shared-keys \
    --resource-group "$RESOURCE_GROUP" \
    --workspace-name "$WORKSPACE_NAME" \
    --query "primarySharedKey" -o tsv)

echo "${BOLD}Enabling VM insights...${RESET}"
# Enable VM insights
az vm extension set \
    --resource-group "$RESOURCE_GROUP" \
    --vm-name "$VM_NAME" \
    --name OmsAgentForLinux \
    --publisher Microsoft.EnterpriseCloud.Monitoring \
    --version 1.14 \
    --protected-settings "{\"workspaceKey\":\"$WORKSPACE_KEY\"}" \
    --settings "{\"workspaceId\":\"$WORKSPACE_ID\", \"stopOnMultipleConnections\":\"false\"}"

echo "${GREEN}✓ VM insights enabled${RESET}"

echo "${BOLD}Enabling diagnostic settings...${RESET}"
# Enable diagnostic settings
VM_ID=$(az vm show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --query "id" -o tsv)

az monitor diagnostic-settings create \
    --resource "$VM_ID" \
    --name "${VM_NAME}-diagnostics" \
    --workspace "$WORKSPACE_ID" \
    --metrics '[{"category": "AllMetrics", "enabled": true, "retentionPolicy": {"days": 30, "enabled": true}}]'

echo "${GREEN}✓ Diagnostic settings enabled${RESET}"

echo "${BOLD}Creating custom Cribl log collection...${RESET}"
# Create custom Cribl log collection
SSH_COMMAND="sudo mkdir -p /etc/opt/microsoft/omsagent/${WORKSPACE_ID}/conf/omsagent.d"
ssh azureuser@$(az vm show -g "$RESOURCE_GROUP" -n "$VM_NAME" --show-details --query "publicIps" -o tsv) "$SSH_COMMAND"

# Create custom log configuration file
cat > cribl_logs.conf << EOF
<source>
  type tail
  path /opt/cribl-stream/log/worker.log
  pos_file /var/opt/microsoft/omsagent/${WORKSPACE_ID}/state/cribl_worker.pos
  tag oms.cribl.worker
  format none
</source>

<source>
  type tail
  path /opt/cribl-stream/log/main.log
  pos_file /var/opt/microsoft/omsagent/${WORKSPACE_ID}/state/cribl_main.pos
  tag oms.cribl.main
  format none
</source>

<filter oms.cribl.**>
  type filter_syslog
</filter>
EOF

# Copy configuration file to VM
VM_IP=$(az vm show -g "$RESOURCE_GROUP" -n "$VM_NAME" --show-details --query "publicIps" -o tsv)
scp cribl_logs.conf azureuser@${VM_IP}:/tmp/cribl_logs.conf
ssh azureuser@${VM_IP} "sudo mv /tmp/cribl_logs.conf /etc/opt/microsoft/omsagent/${WORKSPACE_ID}/conf/omsagent.d/ && sudo chown omsagent:omiusers /etc/opt/microsoft/omsagent/${WORKSPACE_ID}/conf/omsagent.d/cribl_logs.conf && sudo systemctl restart omsagent"

echo "${GREEN}✓ Custom log collection configured${RESET}"

echo "${BOLD}Creating alerts...${RESET}"
# Create basic CPU and memory alerts
az monitor metrics alert create \
    --name "${VM_NAME}-high-cpu" \
    --resource-group "$RESOURCE_GROUP" \
    --scopes "$VM_ID" \
    --condition "avg Percentage CPU > 80" \
    --window-size 5m \
    --evaluation-frequency 1m \
    --description "Alert when CPU exceeds 80% for 5 minutes"

az monitor metrics alert create \
    --name "${VM_NAME}-high-memory" \
    --resource-group "$RESOURCE_GROUP" \
    --scopes "$VM_ID" \
    --condition "avg Available Memory Bytes < 1073741824" \
    --window-size 5m \
    --evaluation-frequency 1m \
    --description "Alert when available memory is less than 1GB for 5 minutes"

echo "${GREEN}✓ Alerts created${RESET}"

echo
echo "${BOLD}Setup complete!${RESET}"
echo
echo "Log Analytics Workspace: ${WORKSPACE_NAME}"
echo "Workspace ID: ${WORKSPACE_ID}"
echo
echo "You can view logs and metrics in the Azure Portal:"
echo "https://portal.azure.com/#blade/Microsoft_Azure_Monitoring/AzureMonitoringBrowseBlade/overview"
echo
echo "Custom queries to try:"
echo "  Cribl Worker Logs:"
echo "    Cribl_CL | where LogType_s == \"worker\""
echo "  Cribl Main Logs:"
echo "    Cribl_CL | where LogType_s == \"main\""
echo
echo "${GREEN}${BOLD}Monitoring setup complete!${RESET}"
