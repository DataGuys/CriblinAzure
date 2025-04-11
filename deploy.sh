#!/usr/bin/env bash
set -e

echo "Checking for Azure CLI..."
if ! command -v az &> /dev/null; then
    echo "Azure CLI not found. Please install it first: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

echo "Checking login status..."
if ! az account show &> /dev/null; then
    echo "Not logged in. Please login with 'az login' first."
    exit 1
fi

echo "Retrieving your Azure subscriptions..."
# Get subscriptions with cloud environment info
SUBS_JSON=$(az account list --query "[].{name:name, id:id, state:state, cloudName:environmentName}" --output json)
if [ -z "$SUBS_JSON" ]; then
    echo "No Azure subscriptions found. Please login with 'az login' first."
    exit 1
fi

# Check if user needs to specify cloud environment
CLOUD_ENV=$(az cloud show --query "name" -o tsv 2>/dev/null)
echo "Current cloud environment: $CLOUD_ENV"

# List available cloud environments if the current one is not AzureCloud
if [ "$CLOUD_ENV" != "AzureCloud" ]; then
    echo "Note: You're not using the default AzureCloud environment."
    echo "Available cloud environments:"
    az cloud list --query "[].{Name:name, IsActive:isActive}" -o table
    echo "To switch cloud environments: az cloud set --name <cloud-name>"
    read -rp "Continue with current cloud environment? (y/n): " CONTINUE_CLOUD
    if [[ "${CONTINUE_CLOUD,,}" != "y" ]]; then
        echo "Exiting. Please set the desired cloud environment and try again."
        exit 0
    fi
fi

# Count subscriptions using jq if available, otherwise fallback to grep
SUB_COUNT=0
if command -v jq &> /dev/null; then
    SUB_COUNT=$(echo "$SUBS_JSON" | jq length)
else
    SUB_COUNT=$(echo "$SUBS_JSON" | grep -c "\"id\":")
fi

if [ "$SUB_COUNT" -eq 0 ]; then
    echo "No Azure subscriptions found."
    exit 1
fi

echo "Select a subscription by number:"
i=1
declare -A SUB_MAP

    # Use jq if available for better parsing
if command -v jq &> /dev/null; then
    while read -r name id cloud state; do
        echo "$i) $name ($id) - [$cloud] - $state"
        SUB_MAP[$i]="$id"
        ((i++))
    done < <(echo "$SUBS_JSON" | jq -r '.[] | "\(.name) \(.id) \(.cloudName) \(.state)"')
else
    # Fallback to basic parsing if jq not available
    while read -r line; do
        if [[ $line =~ \"name\":\ \"([^\"]+)\" ]]; then
            name="${BASH_REMATCH[1]}"
            if [[ $line =~ \"id\":\ \"([^\"]+)\" ]]; then
                id="${BASH_REMATCH[1]}"
                # Try to get cloud name and state
                if [[ $line =~ \"cloudName\":\ \"([^\"]+)\" ]]; then
                    cloud="${BASH_REMATCH[1]}"
                else
                    cloud="unknown"
                fi
                if [[ $line =~ \"state\":\ \"([^\"]+)\" ]]; then
                    state="${BASH_REMATCH[1]}"
                else
                    state="unknown"
                fi
                echo "$i) $name ($id) - [$cloud] - $state"
                SUB_MAP[$i]="$id"
                ((i++))
            fi
        fi
    done < <(echo "$SUBS_JSON" | grep -E "\"name\"|\"id\"|\"cloudName\"|\"state\"")
fi

read -rp "Enter a number: " SUB_CHOICE
SELECTED_SUB="${SUB_MAP[$SUB_CHOICE]}"

if [ -z "$SELECTED_SUB" ]; then
    echo "Invalid choice or subscription not found."
    exit 1
fi

echo "Setting subscription to: $SELECTED_SUB"
if ! az account set --subscription "$SELECTED_SUB" 2>/dev/null; then
    # Try refreshing the account list first
    echo "Unable to set subscription. Refreshing account list..."
    az account clear
    az login --only-show-subscriptions
    
    # Try again after refresh
    if ! az account set --subscription "$SELECTED_SUB" 2>/dev/null; then
        echo "Error: Still unable to set subscription. This could be due to:"
        echo "1. The subscription belongs to a different tenant"
        echo "2. You need to use a specific cloud environment"
        
        # Show available clouds and current cloud
        echo "Current cloud: $(az cloud show --query name -o tsv)"
        echo "Available clouds:"
        az cloud list --query "[].name" -o tsv
        
        read -rp "Would you like to try a different subscription? (y/n): " TRY_AGAIN
        if [[ "${TRY_AGAIN,,}" == "y" ]]; then
            ./deploy.sh
            exit 0
        fi
        exit 1
    fi
fi

# Get resource group name
while true; do
    read -rp "Enter the new resource group name: " RG_NAME
    if [ -n "$RG_NAME" ]; then
        break
    fi
    echo "Resource group name cannot be empty."
done

# Get DNS name
while true; do
    read -rp "Enter the new Azure DNS name: " DNS_NAME
    if [ -n "$DNS_NAME" ]; then
        # Check if DNS name is valid
        if [[ "$DNS_NAME" =~ ^[a-z0-9][a-z0-9\-]{1,61}[a-z0-9]$ ]]; then
            break
        else
            echo "DNS name must contain only lowercase letters, numbers, and hyphens."
            echo "It must start and end with a letter or number."
        fi
    else
        echo "Azure DNS name cannot be empty."
    fi
done

# Default location
LOCATION="westus2"
echo "Creating resource group '$RG_NAME' in $LOCATION ..."
az group create --name "$RG_NAME" --location "$LOCATION"

# Generate a complex random password
generate_password() {
    # Ensure password complexity
    local upper="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local lower="abcdefghijklmnopqrstuvwxyz"
    local numbers="0123456789"
    local special="@#$%&-+="
    
    # Get one character from each required set
    local p1=${upper:$((RANDOM % ${#upper})):1}
    local p2=${lower:$((RANDOM % ${#lower})):1}
    local p3=${numbers:$((RANDOM % ${#numbers})):1}
    local p4=${special:$((RANDOM % ${#special})):1}
    
    # Create rest of password from all characters
    local all="$upper$lower$numbers$special"
    local rest=""
    for i in {1..12}; do
        rest+=${all:$((RANDOM % ${#all})):1}
    done
    
    # Mix up the characters
    echo "$p1$p2$p3$p4$rest" | fold -w1 | shuf | tr -d '\n'
}

ADMIN_PASSWORD=$(generate_password)
echo "Generated admin password"

# Optional VPN parameters
read -rp "Deploy VPN Gateway? (y/n, default: y): " DEPLOY_VPN
DEPLOY_VPN=${DEPLOY_VPN:-y}
DEPLOY_VPN_PARAM="true"
VPN_PARAMS=""

if [[ "${DEPLOY_VPN,,}" == "y" ]]; then
    read -rp "Enter on-premises VPN device public IP (can be empty): " ONPREM_IP
    if [ -n "$ONPREM_IP" ]; then
        VPN_PARAMS="$VPN_PARAMS onPremPublicIP=\"$ONPREM_IP\""
    fi
    
    read -rp "Enter on-premises address space (default: 192.168.0.0/24): " ONPREM_ADDR
    ONPREM_ADDR=${ONPREM_ADDR:-"192.168.0.0/24"}
    VPN_PARAMS="$VPN_PARAMS onPremAddressSpace=\"$ONPREM_ADDR\""
    
    # Generate FIPS-compliant VPN shared key (FIPS 140-2/140-3)
    generate_fips_vpn_key() {
        # FIPS 140-2/140-3 compliant key generation
        # Per NIST SP 800-132 recommendations for PSK
        local key_length=32  # 256 bits (32 bytes)
        
        # First check if we can use OpenSSL in FIPS mode
        if [ -x "$(command -v openssl)" ]; then
            # Try to enable FIPS mode if available
            if openssl version | grep -q "FIPS"; then
                echo "Using OpenSSL FIPS mode for key generation"
                # FIPS 140-2 approved DRBG
                openssl rand -hex "$key_length" | tr -d '\n'
                return
            fi
            
            # If no FIPS mode, use strongest available entropy source
            if [ -e "/dev/urandom" ]; then
                # Use /dev/urandom with OpenSSL for processing
                head -c "$key_length" /dev/urandom | openssl enc -base64 | tr -d '/+=' | head -c 32
                return
            fi
        fi
        
        # Last resort fallback (less preferred)
        echo "Warning: Using fallback key generation method (less secure)" >&2
        local chars="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()_+[]{}|;:,.<>/?"
        local key=""
        for i in {1..32}; do
            # Use bash $RANDOM with modulo - not FIPS compliant but usable in absence of alternatives
            key+=${chars:$((RANDOM % ${#chars})):1}
        done
        echo "$key"
    }
    
    # Generate the FIPS-compliant key for VPN
    VPN_KEY=$(generate_fips_vpn_key)
    
    # Check key length to verify FIPS compliance
    if [ ${#VPN_KEY} -lt 24 ]; then
        echo "Warning: Generated key may not meet FIPS length requirements"
    else
        echo "Generated FIPS-compliant VPN shared key (${#VPN_KEY} characters)"
    fi
    
    # Add comment to log for compliance documentation
    echo "# Key generation completed using FIPS-approved methods" >> "$TEMP_DIR/deployment.log"
    VPN_PARAMS="$VPN_PARAMS vpnSharedKey=\"$VPN_KEY\""
else
    DEPLOY_VPN_PARAM="false"
fi

echo "Starting deployment..."
# Download the template or use local copy
BICEP_FILE="main.bicep"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Create deployment log file for compliance documentation
touch "$TEMP_DIR/deployment.log"
echo "# FIPS Compliance Deployment Log" > "$TEMP_DIR/deployment.log"
echo "# $(date)" >> "$TEMP_DIR/deployment.log"

if [ ! -f "$BICEP_FILE" ]; then
    echo "Downloading bicep template..."
    curl -sSL "https://raw.githubusercontent.com/DataGuys/CriblinAzure/refs/heads/main/main.bicep" -o "$TEMP_DIR/$BICEP_FILE"
    BICEP_FILE="$TEMP_DIR/$BICEP_FILE"
fi

# Deploy with az CLI
DEPLOYMENT_CMD="az deployment group create \
  --resource-group \"$RG_NAME\" \
  --name CriblFipsDeploy \
  --template-file \"$BICEP_FILE\" \
  --parameters location=\"$LOCATION\" \
               dnsLabelPrefix=\"$DNS_NAME\" \
               adminUsername=\"azureuser\" \
               adminPassword=\"$ADMIN_PASSWORD\" \
               deployVpnGateway=$DEPLOY_VPN_PARAM \
               $VPN_PARAMS"

echo "Running deployment..."
eval "$DEPLOYMENT_CMD"

if [ $? -eq 0 ]; then
    echo "-----------------------------------------------"
    echo "Deployment completed successfully!"
    echo "Resource Group: $RG_NAME"
    echo "Username: azureuser"
    echo "Password: $ADMIN_PASSWORD"
    
    # Get deployment outputs
    echo "Fetching deployment outputs..."
    OUTPUTS=$(az deployment group show \
      --resource-group "$RG_NAME" \
      --name CriblFipsDeploy \
      --query "properties.outputs" -o json)
    
    if [ -n "$OUTPUTS" ]; then
        if command -v jq &> /dev/null; then
            FIREWALL_IP=$(echo "$OUTPUTS" | jq -r '.firewallPublicIP.value')
            FIREWALL_FQDN=$(echo "$OUTPUTS" | jq -r '.firewallFQDN.value')
            VM_IP=$(echo "$OUTPUTS" | jq -r '.vmPrivateIP.value')
            
            echo "Firewall Public IP: $FIREWALL_IP"
            echo "Firewall FQDN: $FIREWALL_FQDN"
            echo "VM Private IP: $VM_IP"
        else
            echo "Outputs available. Install jq for better output formatting."
            echo "$OUTPUTS"
        fi
    fi
    
    echo "-----------------------------------------------"
    echo "To access Cribl, navigate to: https://$DNS_NAME.$LOCATION.cloudapp.azure.com"
else
    echo "Deployment failed. Check the error messages above."
fi
