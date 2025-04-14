#!/bin/bash
set -e

# Configuration
RESOURCE_GROUP="cribl-fips-rg"
LOCATION="eastus"
VM_NAME="cribl-fips-vm"
ADMIN_USERNAME="azureuser"
DNS_NAME="your-cribl-instance.example.com"   # Replace with your actual domain
EMAIL_ADDRESS="your-email@example.com"       # Replace with your actual email

# Generate SSH key if it doesn't exist
SSH_KEY_PATH="$HOME/.ssh/id_rsa"
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "Generating SSH key..."
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N ""
fi
SSH_PUBLIC_KEY=$(cat "$SSH_KEY_PATH.pub")

# Prompt for Cribl admin password
read -sp "Enter Cribl admin password: " CRIBL_ADMIN_PASSWORD
echo

# Prompt for Cribl license key (optional)
read -sp "Enter Cribl license key (optional, press Enter to skip): " CRIBL_LICENSE_KEY
echo

# Create resource group if it doesn't exist
echo "Creating resource group if it doesn't exist..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION"

# Create scripts directory
mkdir -p scripts

# Copy custom script to scripts directory
# Ensure this file exists in the current directory
cp custom-script.sh scripts/

# Deploy Bicep template
echo "Deploying Cribl FIPS VM with Let's Encrypt SSL..."
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file cribl-fips-vm-with-ssl.bicep \
  --parameters \
    vmName="$VM_NAME" \
    adminUsername="$ADMIN_USERNAME" \
    sshPublicKey="$SSH_PUBLIC_KEY" \
    dnsName="$DNS_NAME" \
    emailAddress="$EMAIL_ADDRESS" \
    criblAdminPassword="$CRIBL_ADMIN_PASSWORD" \
    criblLicenseKey="$CRIBL_LICENSE_KEY"

# Get deployment outputs
echo "Getting deployment outputs..."
VM_PUBLIC_IP=$(az deployment group show \
  --resource-group "$RESOURCE_GROUP" \
  --name "cribl-fips-vm-with-ssl" \
  --query "properties.outputs.publicIPAddress.value" \
  --output tsv)

VM_FQDN=$(az deployment group show \
  --resource-group "$RESOURCE_GROUP" \
  --name "cribl-fips-vm-with-ssl" \
  --query "properties.outputs.fqdn.value" \
  --output tsv)

CRIBL_UI_URL=$(az deployment group show \
  --resource-group "$RESOURCE_GROUP" \
  --name "cribl-fips-vm-with-ssl" \
  --query "properties.outputs.criblUIUrl.value" \
  --output tsv)

echo "Deployment complete!"
echo "VM Public IP: $VM_PUBLIC_IP"
echo "VM FQDN: $VM_FQDN"
echo "Cribl UI URL: $CRIBL_UI_URL"
echo ""
echo "IMPORTANT: Make sure your DNS record for $DNS_NAME points to $VM_PUBLIC_IP"
echo "You can access the Cribl UI at: https://$DNS_NAME:9000"
echo "Login with username: admin and the password you provided"
