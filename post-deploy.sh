#!/bin/bash
# post-deploy.sh - Configure additional components after Cribl FIPS VM deployment
set -e

# Text formatting
BOLD=$(tput bold)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1)
RESET=$(tput sgr0)

# Display banner
echo "${BOLD}Cribl FIPS VM Post-Deployment Setup${RESET}"
echo "-----------------------------------"

# Configuration
RESOURCE_GROUP=${1:-""}
VM_NAME=${2:-""}
LOCATION=${3:-""}

# Check if required parameters are provided
if [ -z "$RESOURCE_GROUP" ] || [ -z "$VM_NAME" ]; then
    echo "${YELLOW}Usage: $0 <resource-group> <vm-name> [location]${RESET}"
    echo "Example: $0 cribl-fips-rg cribl-fips-vm eastus"
    
    # Try to get from recent deployment
    echo "${YELLOW}Attempting to retrieve parameters from most recent deployment...${RESET}"
    
    LATEST_DEPLOYMENT=$(az deployment group list --query "[?contains(name, 'cribl')].name | [0]" -o tsv 2>/dev/null)
    if [ -n "$LATEST_DEPLOYMENT" ]; then
        RESOURCE_GROUP=$(az group list --query "[?contains(name, 'cribl')].name | [0]" -o tsv)
        VM_NAME=$(az deployment group show --name "$LATEST_DEPLOYMENT" --resource-group "$RESOURCE_GROUP" --query "properties.parameters.vmName.value" -o tsv 2>/dev/null)
        
        if [ -n "$RESOURCE_GROUP" ] && [ -n "$VM_NAME" ]; then
            echo "${GREEN}Found deployment parameters:${RESET}"
            echo "  Resource Group: $RESOURCE_GROUP"
            echo "  VM Name: $VM_NAME"
        else
            echo "${RED}Could not retrieve deployment parameters.${RESET}"
            exit 1
        fi
    else
        echo "${RED}No recent deployments found.${RESET}"
        exit 1
    fi
fi

# Get location if not provided
if [ -z "$LOCATION" ]; then
    LOCATION=$(az group show --name "$RESOURCE_GROUP" --query "location" -o tsv)
fi

echo
echo "${BOLD}Deployment Parameters:${RESET}"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  VM Name: $VM_NAME"
echo "  Location: $LOCATION"
echo

# Menu of post-deployment options
echo "${BOLD}Available Post-Deployment Options:${RESET}"
echo "  1. Verify Deployment"
echo "  2. Setup Monitoring"
echo "  3. Setup Backup"
echo "  4. All of the above"
echo "  5. Exit"
echo

read -p "Select an option [1-5]: " OPTION

case $OPTION in
    1)
        echo "${BOLD}Verifying Deployment...${RESET}"
        ./verify-deployment.sh "$RESOURCE_GROUP" "$VM_NAME"
        ;;
    2)
        echo "${BOLD}Setting Up Monitoring...${RESET}"
        ./setup-monitoring.sh "$RESOURCE_GROUP" "$VM_NAME" "cribl-logs-workspace" "$LOCATION"
        ;;
    3)
        echo "${BOLD}Setting Up Backup...${RESET}"
        ./setup-backup.sh "$RESOURCE_GROUP" "$VM_NAME" "cribl-backup-vault" "DailyPolicy" "$LOCATION"
        ;;
    4)
        echo "${BOLD}Running All Post-Deployment Tasks...${RESET}"
        
        echo "${YELLOW}Step 1: Verifying Deployment${RESET}"
        ./verify-deployment.sh "$RESOURCE_GROUP" "$VM_NAME"
        
        echo
        echo "${YELLOW}Step 2: Setting Up Monitoring${RESET}"
        ./setup-monitoring.sh "$RESOURCE_GROUP" "$VM_NAME" "cribl-logs-workspace" "$LOCATION"
        
        echo
        echo "${YELLOW}Step 3: Setting Up Backup${RESET}"
        ./setup-backup.sh "$RESOURCE_GROUP" "$VM_NAME" "cribl-backup-vault" "DailyPolicy" "$LOCATION"
        
        echo
        echo "${GREEN}${BOLD}All post-deployment tasks completed!${RESET}"
        ;;
    5)
        echo "Exiting post-deployment setup."
        exit 0
        ;;
    *)
        echo "${RED}Invalid option.${RESET}"
        exit 1
        ;;
esac

echo
echo "${GREEN}${BOLD}Post-deployment setup complete!${RESET}"
echo "For more information on best practices and advanced configurations,"
echo "please refer to the BEST_PRACTICES.md document."
