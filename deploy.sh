#!/usr/bin/env bash

# Prompt for subscription
read -rp "Enter your Azure subscription ID or name: " SUB_ID

# Prompt for resource group
read -rp "Enter the new resource group name: " RG_NAME

# Set the subscription
az account set --subscription "$SUB_ID"

# Create the resource group (adjust the location if desired)
az group create --name "$RG_NAME" --location westus2

# Deploy the Bicep template
az deployment group create \
  --resource-group "$RG_NAME" \
  --name CriblFipsDeploy \
  --template-uri "https://raw.githubusercontent.com/DataGuys/CriblinAzure/refs/heads/main/main.bicep" \
  --parameters location=westus2 \
               dnsLabelPrefix=mycriblfipslabel \
               adminUsername=azureuser \
               adminPassword='SuperSecurePassword'
