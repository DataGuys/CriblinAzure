#!/bin/bash
# verify-deployment.sh - Verify Cribl FIPS VM deployment and perform health checks
set -e

# Text formatting
BOLD=$(tput bold)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1)
RESET=$(tput sgr0)

# Configuration - these should match your deployment
RESOURCE_GROUP=${1:-"cribl-fips-rg"}
VM_NAME=${2:-"cribl-fips-vm"}

# Display header
echo "${BOLD}Cribl FIPS VM Deployment Verification${RESET}"
echo "------------------------------------"
echo

# Verify the resource group exists
echo "${BOLD}Checking Resource Group...${RESET}"
if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
    echo "${GREEN}✓ Resource Group '$RESOURCE_GROUP' exists${RESET}"
else
    echo "${RED}✗ Resource Group '$RESOURCE_GROUP' does not exist${RESET}"
    exit 1
fi

# Get VM status
echo
echo "${BOLD}Checking VM Status...${RESET}"
VM_STATUS=$(az vm show -g "$RESOURCE_GROUP" -n "$VM_NAME" --query "powerState" -o tsv 2>/dev/null || echo "NotFound")

if [ "$VM_STATUS" == "NotFound" ]; then
    echo "${RED}✗ VM '$VM_NAME' does not exist in resource group '$RESOURCE_GROUP'${RESET}"
    exit 1
elif [ "$VM_STATUS" == "VM running" ]; then
    echo "${GREEN}✓ VM '$VM_NAME' is running${RESET}"
else
    echo "${YELLOW}! VM '$VM_NAME' is not running (Status: $VM_STATUS)${RESET}"
    echo "  Consider starting it with: az vm start -g $RESOURCE_GROUP -n $VM_NAME"
fi

# Get Public IP
echo
echo "${BOLD}Retrieving VM Network Information...${RESET}"
PUBLIC_IP=$(az vm show -g "$RESOURCE_GROUP" -n "$VM_NAME" --show-details \
    --query "publicIps" -o tsv 2>/dev/null || echo "NotFound")

if [ "$PUBLIC_IP" == "NotFound" ] || [ -z "$PUBLIC_IP" ]; then
    echo "${YELLOW}! Could not retrieve public IP address${RESET}"
else
    echo "${GREEN}✓ VM Public IP: $PUBLIC_IP${RESET}"
    
    # Check DNS Name
    DNS_NAME=$(az network public-ip list -g "$RESOURCE_GROUP" \
        --query "[?ipAddress=='$PUBLIC_IP'].dnsSettings.fqdn" -o tsv)
    
    if [ -z "$DNS_NAME" ]; then
        echo "${YELLOW}! No DNS name configured for this IP${RESET}"
    else
        echo "${GREEN}✓ VM DNS Name: $DNS_NAME${RESET}"
    fi
    
    # Check connectivity
    echo
    echo "${BOLD}Testing Network Connectivity...${RESET}"
    
    # SSH Port
    echo -n "Testing SSH (port 22): "
    if timeout 5 bash -c "</dev/tcp/$PUBLIC_IP/22" &>/dev/null; then
        echo "${GREEN}✓ Open${RESET}"
    else
        echo "${RED}✗ Closed or filtered${RESET}"
    fi
    
    # HTTP Port
    echo -n "Testing HTTP (port 80): "
    if timeout 5 bash -c "</dev/tcp/$PUBLIC_IP/80" &>/dev/null; then
        echo "${GREEN}✓ Open${RESET}"
    else
        echo "${RED}✗ Closed or filtered${RESET}"
    fi
    
    # HTTPS Port
    echo -n "Testing HTTPS (port 443): "
    if timeout 5 bash -c "</dev/tcp/$PUBLIC_IP/443" &>/dev/null; then
        echo "${GREEN}✓ Open${RESET}"
    else
        echo "${RED}✗ Closed or filtered${RESET}"
    fi
    
    # Cribl UI Port
    echo -n "Testing Cribl UI (port 9000): "
    if timeout 5 bash -c "</dev/tcp/$PUBLIC_IP/9000" &>/dev/null; then
        echo "${GREEN}✓ Open${RESET}"
    else
        echo "${RED}✗ Closed or filtered${RESET}"
    fi
fi

# Output SSH command
echo
echo "${BOLD}SSH Access Command:${RESET}"
echo "ssh azureuser@$PUBLIC_IP"

# Let's Encrypt SSL Checker
echo
echo "${BOLD}SSL Certificate Checker${RESET}"
echo "To verify your Let's Encrypt certificate is properly installed,"
echo "run the following command once your DNS is configured:"
echo
echo "  curl -Ivs https://YOUR-DOMAIN-NAME:9000 2>&1 | grep 'Let'"
echo
echo "You should see output containing 'Let's Encrypt' if successful."

# Display final message
echo
echo "${BOLD}Next Steps:${RESET}"
echo "1. Ensure your custom domain DNS points to: $PUBLIC_IP"
echo "2. Access the Cribl UI at: https://YOUR-DOMAIN-NAME:9000"
echo "3. If you encounter issues, check the VM logs:"
echo "   ssh azureuser@$PUBLIC_IP 'sudo journalctl -u cribl'"
echo
echo "${GREEN}${BOLD}Verification complete!${RESET}"
