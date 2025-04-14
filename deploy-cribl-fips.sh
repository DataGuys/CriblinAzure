#!/bin/bash
# deploy-cribl-fips.sh - Automated deployment script for Cribl FIPS VM with Let's Encrypt SSL
set -e

# Text formatting
BOLD=$(tput bold)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1)
RESET=$(tput sgr0)

# Display banner
cat << "EOF"
 _____      _ _     _ _        ______ _____ _____   _____   __      ____  __
/  __ \    (_) |   | (_)       |  ___|_   _|  __ \ /  ___| /  |    / /  \/  |
| /  \/ _ __| | |__ | |_ _ __  | |_    | | | |  \/ \ `--. `| |   / /| .  . |
| |    | '__| | '_ \| | | '_ \ |  _|   | | | | __   `--. \ | |  / / | |\/| |
| \__/\| |  | | |_) | | | | | || |    _| |_| |_\ \ /\__/ / | | / /  | |  | |
 \____/|_|  |_|_.__/|_|_|_| |_|\_|    \___/ \____/ \____/  |_|/_/   |_|  |_|
                                                                             
EOF
echo -e "${BOLD}Cribl FIPS-Compliant VM with Let's Encrypt SSL${RESET}\n"

# Function to validate domain name format
validate_domain() {
    if [[ ! "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi
    return 0
}

# Function to validate email format
validate_email() {
    if [[ ! "$1" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

# Function to check Azure CLI is installed
check_prerequisites() {
    echo "${BOLD}Checking prerequisites...${RESET}"
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        echo "${RED}Error: Azure CLI is not installed.${RESET}"
        echo "Please install Azure CLI from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI is logged in
    if ! az account show &> /dev/null; then
        echo "${YELLOW}You are not logged in to Azure CLI.${RESET}"
        echo "Please login using: az login"
        exit 1
    fi
    
    # Check if bicep file exists
    if [ ! -f "cribl-fips-vm-with-ssl.bicep" ]; then
        echo "${RED}Error: Required Bicep template 'cribl-fips-vm-with-ssl.bicep' not found.${RESET}"
        exit 1
    fi
    
    # Check if scripts directory and file exist
    if [ ! -d "scripts" ] || [ ! -f "scripts/custom-script.sh" ]; then
        echo "${RED}Error: Required scripts directory or file 'scripts/custom-script.sh' not found.${RESET}"
        exit 1
    fi
    
    echo "${GREEN}✓ All prerequisites met${RESET}"
}

# Configuration with defaults
RESOURCE_GROUP=""
LOCATION=""
VM_NAME="cribl-fips-vm"
ADMIN_USERNAME="azureuser"
DNS_NAME=""
EMAIL_ADDRESS=""
VM_SIZE="Standard_B2ms"
CRIBL_MODE="stream"

# Generate SSH key if it doesn't exist (or use existing)
SSH_KEY_PATH="$HOME/.ssh/id_rsa"

# Interactive configuration
configure() {
    echo "${BOLD}Deployment Configuration${RESET}"
    echo "------------------------------"
    
    # Resource Group
    read -p "Resource Group Name [cribl-fips-rg]: " RESOURCE_GROUP
    RESOURCE_GROUP=${RESOURCE_GROUP:-"cribl-fips-rg"}
    
    # Location
    echo "Available Azure Locations:"
    az account list-locations --query "[].name" -o tsv | sort | head -n 10
    echo "(Use 'az account list-locations --query \"[].name\" -o tsv' for full list)"
    read -p "Location [eastus]: " LOCATION
    LOCATION=${LOCATION:-"eastus"}
    
    # VM Name
    read -p "VM Name [$VM_NAME]: " VM_NAME_INPUT
    VM_NAME=${VM_NAME_INPUT:-$VM_NAME}
    
    # Admin Username
    read -p "Admin Username [$ADMIN_USERNAME]: " ADMIN_USERNAME_INPUT
    ADMIN_USERNAME=${ADMIN_USERNAME_INPUT:-$ADMIN_USERNAME}
    
    # VM Size
    echo "Recommended VM Sizes:"
    echo "  Standard_B2ms (2 vCPUs, 8 GB RAM) - Development"
    echo "  Standard_D4s_v3 (4 vCPUs, 16 GB RAM) - Small Production"
    echo "  Standard_D8s_v3 (8 vCPUs, 32 GB RAM) - Medium Production"
    read -p "VM Size [$VM_SIZE]: " VM_SIZE_INPUT
    VM_SIZE=${VM_SIZE_INPUT:-$VM_SIZE}
    
    # DNS Name for Let's Encrypt
    while true; do
        read -p "DNS Name for Let's Encrypt (e.g., cribl.example.com): " DNS_NAME
        if [ -z "$DNS_NAME" ]; then
            echo "${RED}Error: DNS Name is required.${RESET}"
        elif ! validate_domain "$DNS_NAME"; then
            echo "${RED}Error: Invalid domain format.${RESET}"
        else
            break
        fi
    done
    
    # Email Address for Let's Encrypt
    while true; do
        read -p "Email Address for Let's Encrypt notifications: " EMAIL_ADDRESS
        if [ -z "$EMAIL_ADDRESS" ]; then
            echo "${RED}Error: Email Address is required.${RESET}"
        elif ! validate_email "$EMAIL_ADDRESS"; then
            echo "${RED}Error: Invalid email format.${RESET}"
        else
            break
        fi
    done
    
    # Cribl Mode
    read -p "Cribl Mode (stream or edge) [$CRIBL_MODE]: " CRIBL_MODE_INPUT
    CRIBL_MODE=${CRIBL_MODE_INPUT:-$CRIBL_MODE}
    
    # SSH Key path
    read -p "SSH Key Path [$SSH_KEY_PATH]: " SSH_KEY_PATH_INPUT
    SSH_KEY_PATH=${SSH_KEY_PATH_INPUT:-$SSH_KEY_PATH}
    
    # Generate SSH key if it doesn't exist
    if [ ! -f "$SSH_KEY_PATH" ]; then
        echo "Generating SSH key at $SSH_KEY_PATH..."
        ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N ""
    fi
    SSH_PUBLIC_KEY=$(cat "$SSH_KEY_PATH.pub")
    
    # Cribl admin password
    while true; do
        read -sp "Enter Cribl Admin Password: " CRIBL_ADMIN_PASSWORD
        echo
        if [ -z "$CRIBL_ADMIN_PASSWORD" ]; then
            echo "${RED}Error: Cribl Admin Password is required.${RESET}"
        elif [ ${#CRIBL_ADMIN_PASSWORD} -lt 8 ]; then
            echo "${RED}Error: Password must be at least 8 characters.${RESET}"
        else
            read -sp "Confirm Cribl Admin Password: " CRIBL_ADMIN_PASSWORD_CONFIRM
            echo
            if [ "$CRIBL_ADMIN_PASSWORD" != "$CRIBL_ADMIN_PASSWORD_CONFIRM" ]; then
                echo "${RED}Error: Passwords do not match.${RESET}"
            else
                break
            fi
        fi
    done
    
    # Cribl license key (optional)
    read -sp "Enter Cribl License Key (optional, press Enter to skip): " CRIBL_LICENSE_KEY
    echo
    
    # Show configuration summary
    echo
    echo "${BOLD}Deployment Configuration Summary:${RESET}"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    echo "  VM Name: $VM_NAME"
    echo "  Admin Username: $ADMIN_USERNAME"
    echo "  VM Size: $VM_SIZE"
    echo "  DNS Name: $DNS_NAME"
    echo "  Cribl Mode: $CRIBL_MODE"
    echo "  SSH Key: $SSH_KEY_PATH"
    echo
    
    # Confirm deployment
    read -p "Continue with deployment? (y/n): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled."
        exit 0
    fi
}

# Deploy resources
deploy() {
    echo
    echo "${BOLD}Starting Deployment Process${RESET}"
    echo "-----------------------------"
    
    # Create resource group if it doesn't exist
    echo "Creating resource group if it doesn't exist..."
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
        echo "${GREEN}✓ Resource group created${RESET}"
    else
        echo "${GREEN}✓ Using existing resource group${RESET}"
    fi
    
    # Deploy Bicep template
    echo "Deploying Cribl FIPS VM with Let's Encrypt SSL..."
    DEPLOYMENT_START_TIME=$(date +%s)
    
    az deployment group create \
      --resource-group "$RESOURCE_GROUP" \
      --template-file cribl-fips-vm-with-ssl.bicep \
      --parameters \
        vmName="$VM_NAME" \
        adminUsername="$ADMIN_USERNAME" \
        sshPublicKey="$SSH_PUBLIC_KEY" \
        dnsName="$DNS_NAME" \
        emailAddress="$EMAIL_ADDRESS" \
        vmSize="$VM_SIZE" \
        criblMode="$CRIBL_MODE" \
        criblAdminPassword="$CRIBL_ADMIN_PASSWORD" \
        criblLicenseKey="$CRIBL_LICENSE_KEY"
    
    DEPLOYMENT_END_TIME=$(date +%s)
    DEPLOYMENT_DURATION=$((DEPLOYMENT_END_TIME - DEPLOYMENT_START_TIME))
    
    echo "${GREEN}✓ Deployment completed in $DEPLOYMENT_DURATION seconds${RESET}"
    
    # Get deployment outputs
    echo "Getting deployment outputs..."
    VM_PUBLIC_IP=$(az vm show -g "$RESOURCE_GROUP" -n "$VM_NAME" --show-details \
      --query "publicIps" -o tsv 2>/dev/null || echo "Error retrieving IP")
    
    VM_FQDN=$(az network public-ip list -g "$RESOURCE_GROUP" \
      --query "[?ipAddress=='$VM_PUBLIC_IP'].dnsSettings.fqdn" -o tsv 2>/dev/null || echo "Error retrieving FQDN")
    
    # Display deployment results
    echo
    echo "${BOLD}Deployment Results:${RESET}"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  VM Name: $VM_NAME"
    echo "  VM Public IP: $VM_PUBLIC_IP"
    echo "  VM FQDN: $VM_FQDN"
    echo "  Cribl UI URL: https://$DNS_NAME:9000"
    echo
    echo "${BOLD}${YELLOW}IMPORTANT DNS CONFIGURATION:${RESET}"
    echo "Create an A record for $DNS_NAME pointing to $VM_PUBLIC_IP"
    echo
    echo "${BOLD}Next Steps:${RESET}"
    echo "1. Configure your DNS provider to create an A record for:"
    echo "   $DNS_NAME → $VM_PUBLIC_IP"
    echo
    echo "2. Wait for DNS propagation (may take up to 24-48 hours)"
    echo
    echo "3. Access Cribl UI at: https://$DNS_NAME:9000"
    echo "   Login with: admin / [your password]"
    echo
    echo "4. Verify deployment with: ./verify-deployment.sh $RESOURCE_GROUP $VM_NAME"
    echo
    echo "${GREEN}${BOLD}Deployment complete!${RESET}"
}

# Main execution flow
check_prerequisites
configure
deploy
