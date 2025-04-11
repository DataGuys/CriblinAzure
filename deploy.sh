#!/usr/bin/env bash
set -e

echo "Retrieving your Azure subscriptions..."
# Retrieve subscriptions
mapfile -t SUBS < <(az account list --query "[].{Name:name, ID:id}" -o tsv)

if [ "${#SUBS[@]}" -eq 0 ]; then
  echo "No Azure subscriptions found. Please log in via 'az login' first."
  exit 1
fi

echo "Select a subscription by number:"
i=1
declare -A SUB_MAP
for sub in "${SUBS[@]}"; do
  # Each 'sub' line is "Name\tID"
  name=$(echo "$sub" | cut -f1)
  id=$(echo "$sub" | cut -f2)
  echo "$i) $name ($id)"
  SUB_MAP[$i]="$id"
  ((i++))
done

read -rp "Enter a number: " SUB_CHOICE
SELECTED_SUB="${SUB_MAP[$SUB_CHOICE]}"

if [ -z "$SELECTED_SUB" ]; then
  echo "Invalid choice or subscription not found."
  exit 1
fi

echo "Setting subscription to: $SELECTED_SUB"
az account set --subscription "$SELECTED_SUB"

read -rp "Enter the new resource group name: " RG_NAME
if [ -z "$RG_NAME" ]; then
  echo "Resource group name cannot be empty."
  exit 1
fi

read -rp "Enter the new Azure DNS name: " DNS_NAME
if [ -z "$DNS_NAME" ]; then
  echo "Azure DNS name cannot be empty."
  exit 1
fi

LOCATION="westus2"
echo "Creating resource group '$RG_NAME' in $LOCATION ..."
az group create --name "$RG_NAME" --location "$LOCATION"

# Generate a complex random password (16 chars, ensuring uppercase, lowercase, digit, special).
generate_password() {
  # Simpler implementation using built-in tools
  local chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@#$%&-+='
  local password=""
  
  # Generate a 16-character password
  for ((i=0; i<16; i++)); do
    password+="${chars:RANDOM%${#chars}:1}"
  done
  
  # Ensure complexity requirements by adding specific character types
  password="${password:0:12}A1@z"
  
  echo "$password"
}

ADMIN_PASSWORD=$(generate_password)
echo "Generated adminPassword: $ADMIN_PASSWORD"

echo "Starting deployment..."
az deployment group create \
  --resource-group "$RG_NAME" \
  --name CriblFipsDeploy \
  --template-uri "https://raw.githubusercontent.com/DataGuys/CriblinAzure/refs/heads/main/main.bicep" \
  --parameters location="$LOCATION" \
               dnsLabelPrefix="$DNS_NAME" \
               adminUsername="azureuser" \
               adminPassword="$ADMIN_PASSWORD"

echo "Deployment completed."
