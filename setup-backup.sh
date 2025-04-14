#!/bin/bash
# setup-backup.sh - Configure Azure Backup for Cribl FIPS VM
set -e

# Text formatting
BOLD=$(tput bold)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1)
RESET=$(tput sgr0)

# Display banner
echo "${BOLD}Cribl FIPS VM Backup Setup${RESET}"
echo "--------------------------"

# Configuration
RESOURCE_GROUP=${1:-"cribl-fips-rg"}
VM_NAME=${2:-"cribl-fips-vm"}
VAULT_NAME=${3:-"cribl-backup-vault"}
BACKUP_POLICY=${4:-"DailyPolicy"}
LOCATION=${5:-"eastus"}

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

echo "${BOLD}Creating Recovery Services Vault...${RESET}"
# Create Recovery Services vault if it doesn't exist
if ! az backup vault show --resource-group "$RESOURCE_GROUP" --name "$VAULT_NAME" &> /dev/null; then
    az backup vault create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VAULT_NAME" \
        --location "$LOCATION"
    echo "${GREEN}✓ Recovery Services vault created${RESET}"
else
    echo "${GREEN}✓ Using existing Recovery Services vault${RESET}"
fi

echo "${BOLD}Creating Backup Policy...${RESET}"
# Create backup policy if it doesn't exist
if ! az backup policy show --resource-group "$RESOURCE_GROUP" --vault-name "$VAULT_NAME" --name "$BACKUP_POLICY" &> /dev/null; then
    az backup policy create \
        --resource-group "$RESOURCE_GROUP" \
        --vault-name "$VAULT_NAME" \
        --name "$BACKUP_POLICY" \
        --policy '{"name":"DailyPolicy","properties":{"backupManagementType":"AzureIaasVM","schedulePolicy":{"schedulePolicyType":"SimpleSchedulePolicy","scheduleRunFrequency":"Daily","scheduleRunTimes":["2021-01-01T02:00:00Z"],"scheduleWeeklyFrequency":0},"retentionPolicy":{"retentionPolicyType":"LongTermRetentionPolicy","dailySchedule":{"retentionTimes":["2021-01-01T02:00:00Z"],"retentionDuration":{"count":30,"durationType":"Days"}},"weeklySchedule":{"daysOfTheWeek":["Sunday"],"retentionTimes":["2021-01-01T02:00:00Z"],"retentionDuration":{"count":4,"durationType":"Weeks"}},"monthlySchedule":{"retentionScheduleFormatType":"Daily","retentionScheduleDaily":{"daysOfTheMonth":[{"date":1,"isLast":false}]},"retentionTimes":["2021-01-01T02:00:00Z"],"retentionDuration":{"count":6,"durationType":"Months"}},"yearlySchedule":{"retentionScheduleFormatType":"Daily","retentionScheduleDaily":{"daysOfTheMonth":[{"date":1,"isLast":false}]},"retentionTimes":["2021-01-01T02:00:00Z"],"monthsOfYear":["January"],"retentionDuration":{"count":1,"durationType":"Years"}}}}}'
    echo "${GREEN}✓ Backup policy created${RESET}"
else
    echo "${GREEN}✓ Using existing backup policy${RESET}"
fi

echo "${BOLD}Enabling backup for VM...${RESET}"
# Enable backup for VM
VM_ID=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" --query "id" -o tsv)

# Check if VM is already protected
PROTECTED_ITEM=$(az backup protection check-vm --resource-group "$RESOURCE_GROUP" --vault-name "$VAULT_NAME" --vm "$VM_ID" --query "properties.protectionStatus" -o tsv 2>/dev/null || echo "NotProtected")

if [[ "$PROTECTED_ITEM" == "NotProtected" ]]; then
    az backup protection enable-for-vm \
        --resource-group "$RESOURCE_GROUP" \
        --vault-name "$VAULT_NAME" \
        --vm "$VM_ID" \
        --policy-name "$BACKUP_POLICY"
    echo "${GREEN}✓ Backup enabled for VM${RESET}"
else
    echo "${GREEN}✓ VM is already protected by backup${RESET}"
fi

echo "${BOLD}Triggering initial backup...${RESET}"
# Trigger initial backup
CONTAINER_NAME=$(az backup container list \
    --resource-group "$RESOURCE_GROUP" \
    --vault-name "$VAULT_NAME" \
    --backup-management-type AzureIaasVM \
    --query "[0].name" -o tsv)

ITEM_NAME=$(az backup item list \
    --resource-group "$RESOURCE_GROUP" \
    --vault-name "$VAULT_NAME" \
    --container-name "$CONTAINER_NAME" \
    --backup-management-type AzureIaasVM \
    --query "[0].name" -o tsv)

az backup protection backup-now \
    --resource-group "$RESOURCE_GROUP" \
    --vault-name "$VAULT_NAME" \
    --container-name "$CONTAINER_NAME" \
    --item-name "$ITEM_NAME" \
    --retain-until "$(date -d '30 days' '+%Y-%m-%d')"

echo "${GREEN}✓ Initial backup triggered${RESET}"

echo
echo "${BOLD}Backup setup complete!${RESET}"
echo
echo "Recovery Services Vault: ${VAULT_NAME}"
echo "Backup Policy: ${BACKUP_POLICY}"
echo
echo "Daily backups will run at 2:00 AM UTC"
echo "Retention: 30 days daily, 4 weeks, 6 months, 1 year"
echo
echo "You can monitor backups in the Azure Portal:"
echo "https://portal.azure.com/#blade/Microsoft_Azure_RecoveryServices_Backup/BackupCenter/VaultDashboards"
echo
echo "${GREEN}${BOLD}Backup setup complete!${RESET}"
