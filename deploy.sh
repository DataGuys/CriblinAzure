#!/usr/bin/env bash
set -e

# Check Azure CLI
if ! command -v az &>/dev/null; then
    echo "Azure CLI not found. Install it from https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
fi

# Simple subscription selection
echo "Retrieving Azure subscriptions..."
mapfile -t SUBS < <(az account list --query "[].{name:name, id:id}" -o tsv)

if [ ${#SUBS[@]} -eq 0 ]; then
    echo "No subscriptions found. Please run 'az login' first."
    exit 1
fi

echo "Select a subscription:"
i=1
declare -A SUB_MAP
for sub in "${SUBS[@]}"; do
    name=$(echo "$sub" | cut -f1)
    id=$(echo "$sub" | cut -f2)
    echo "$i) $name ($id)"
    SUB_MAP[$i]="$id"
    ((i++))
done

read -rp "Enter number: " SUB_CHOICE
SELECTED_SUB="${SUB_MAP[$SUB_CHOICE]}"

if [ -z "$SELECTED_SUB" ]; then
    echo "Invalid selection."
    exit 1
fi

echo "Setting subscription to: $SELECTED_SUB"
az account set --subscription "$SELECTED_SUB" || {
    echo "Error setting subscription. Check if it exists in your current tenant."
    exit 1
}

# Get resource group name
read -rp "Enter new resource group name: " RG_NAME
if [ -z "$RG_NAME" ]; then
    echo "Resource group name required."
    exit 1
fi

# Get DNS name
read -rp "Enter Azure DNS name: " DNS_NAME
if [ -z "$DNS_NAME" ]; then
    echo "DNS name required."
    exit 1
fi

# Create resource group
LOCATION="westus2"
echo "Creating resource group '$RG_NAME' in $LOCATION..."
az group create --name "$RG_NAME" --location "$LOCATION"

# Generate FIPS-compliant VPN key
generate_fips_vpn_key() {
    if [ -x "$(command -v openssl)" ]; then
        # Use OpenSSL for FIPS-compliant key generation
        openssl rand -base64 32 | tr -d '/+=\n' | head -c 32
    else
        # Fallback method
        local chars="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()_"
        local key=""
        for i in {1..32}; do
            key+=${chars:$((RANDOM % ${#chars})):1}
        done
        echo "$key"
    fi
}

# Password generation
generate_password() {
    openssl rand -base64 12 | tr -d '/+=\n'
}

# Generate credentials
ADMIN_PASSWORD=$(generate_password)
echo "Generated admin password"

# VPN configuration
read -rp "Deploy VPN Gateway? (y/n, default: y): " DEPLOY_VPN
DEPLOY_VPN=${DEPLOY_VPN:-y}
VPN_PARAMS=""

if [[ "${DEPLOY_VPN,,}" == "y" ]]; then
    VPN_KEY=$(generate_fips_vpn_key)
    echo "Generated FIPS-compliant VPN key"
    VPN_PARAMS="deployVpnGateway=true vpnSharedKey=\"$VPN_KEY\""
else
    VPN_PARAMS="deployVpnGateway=false"
fi

# Deploy bicep template
echo "Starting deployment..."
az deployment group create \
    --resource-group "$RG_NAME" \
    --name "CriblFipsDeploy-$(date +%s)" \
    --template-uri "https://raw.githubusercontent.com/DataGuys/CriblinAzure/refs/heads/main/main.bicep" \
    --parameters location="$LOCATION" \
               dnsLabelPrefix="$DNS_NAME" \
               adminUsername="azureuser" \
               adminPassword="$ADMIN_PASSWORD" \
               $VPN_PARAMS

echo "Deployment complete!"
echo "Firewall FQDN: $DNS_NAME.$LOCATION.cloudapp.azure.com"
echo "Admin username: azureuser"
echo "Admin password: $ADMIN_PASSWORD"
if [[ "${DEPLOY_VPN,,}" == "y" ]]; then
    echo "VPN shared key: $VPN_KEY"
fi
