#!/bin/bash
# cloudshell-install.sh - Install and setup Cribl FIPS VM from Azure Cloud Shell
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
echo -e "${BOLD}Cribl FIPS-Compliant VM Cloud Shell Installer${RESET}\n"

# Check if running in Cloud Shell
if [ -z "$CLOUDSHELL_VERSION" ]; then
    echo "${YELLOW}Warning: This script is optimized for Azure Cloud Shell.${RESET}"
    echo "You appear to be running it outside of Cloud Shell."
    read -p "Continue anyway? (y/n): " CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
fi

# Workspace directory - Cloud Shell friendly
WORKSPACE="$HOME/cribl-fips-deployment"
REPO_URL="https://github.com/DataGuys/CriblinAzure.git"
REPO_BRANCH="main"

echo "${BOLD}Setting up workspace at $WORKSPACE...${RESET}"

# Create workspace directory if it doesn't exist
if [ -d "$WORKSPACE" ]; then
    echo "${YELLOW}Workspace directory already exists.${RESET}"
    read -p "Remove existing directory and clone fresh? (y/n): " FRESHEN
    if [[ "$FRESHEN" =~ ^[Yy]$ ]]; then
        rm -rf "$WORKSPACE"
        mkdir -p "$WORKSPACE"
    fi
else
    mkdir -p "$WORKSPACE"
fi

# Clone the repository
cd "$WORKSPACE"
if [ ! -f "$WORKSPACE/deploy-cribl-fips.sh" ]; then
    echo "${BOLD}Cloning repository...${RESET}"
    git clone --branch "$REPO_BRANCH" "$REPO_URL" .
    
    if [ $? -ne 0 ]; then
        echo "${RED}Failed to clone repository.${RESET}"
        exit 1
    fi
fi

# Make scripts executable
echo "${BOLD}Making scripts executable...${RESET}"
find . -name "*.sh" -exec chmod +x {} \;

# Verify Azure CLI is installed and logged in
echo "${BOLD}Checking Azure CLI...${RESET}"
if ! command -v az &> /dev/null; then
    echo "${RED}Error: Azure CLI is not installed.${RESET}"
    echo "This is unusual for Cloud Shell. Please report this issue."
    exit 1
fi

# Check Azure CLI is logged in
if ! az account show &> /dev/null; then
    echo "${YELLOW}You are not logged in to Azure CLI.${RESET}"
    echo "Please login using: az login"
    exit 1
fi

# Display account information
SUBSCRIPTION=$(az account show --query name -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
USER=$(az account show --query user.name -o tsv)

echo "${BOLD}Azure Subscription:${RESET} $SUBSCRIPTION"
echo "${BOLD}Subscription ID:${RESET} $SUBSCRIPTION_ID"
echo "${BOLD}User:${RESET} $USER"

# Display deployment options
echo
echo "${BOLD}Deployment Options:${RESET}"
echo "  1. Run standard deployment"
echo "  2. Run deployment with Key Vault integration"
echo "  3. Run deployment and post-deployment setup"
echo "  4. Exit"
echo

read -p "Select an option [1-4]: " OPTION

case $OPTION in
    1)
        echo "${BOLD}Running standard deployment...${RESET}"
        ./deploy-cribl-fips.sh
        ;;
    2)
        echo "${BOLD}Running deployment with Key Vault integration...${RESET}"
        echo "${YELLOW}Note: This option requires managed identity support.${RESET}"
        echo "Please modify deploy-cribl-fips.sh to enable Key Vault before using this option."
        
        read -p "Continue with standard deployment instead? (y/n): " CONTINUE
        if [[ "$CONTINUE" =~ ^[Yy]$ ]]; then
            ./deploy-cribl-fips.sh
        else
            echo "Deployment cancelled."
            exit 0
        fi
        ;;
    3)
        echo "${BOLD}Running deployment and post-deployment setup...${RESET}"
        ./deploy-cribl-fips.sh
        
        echo
        echo "${BOLD}Proceeding to post-deployment setup...${RESET}"
        
        # Extract resource group and VM name from deployment output
        RESOURCE_GROUP=$(grep "Resource Group:" "${WORKSPACE}/deploy-output.txt" 2>/dev/null | awk '{print $NF}' || echo "")
        VM_NAME=$(grep "VM Name:" "${WORKSPACE}/deploy-output.txt" 2>/dev/null | awk '{print $NF}' || echo "")
        
        if [ -z "$RESOURCE_GROUP" ] || [ -z "$VM_NAME" ]; then
            echo "${YELLOW}Could not extract deployment details from output.${RESET}"
            read -p "Enter Resource Group name: " RESOURCE_GROUP
            read -p "Enter VM Name: " VM_NAME
        fi
        
        if [ -n "$RESOURCE_GROUP" ] && [ -n "$VM_NAME" ]; then
            ./post-deploy.sh "$RESOURCE_GROUP" "$VM_NAME"
        else
            echo "${RED}Missing required parameters for post-deployment setup.${RESET}"
            exit 1
        fi
        ;;
    4)
        echo "Exiting installation."
        exit 0
        ;;
    *)
        echo "${RED}Invalid option.${RESET}"
        exit 1
        ;;
esac

echo
echo "${GREEN}${BOLD}Cloud Shell installation completed!${RESET}"
echo
echo "To run additional configurations or verifications, use:"
echo "  cd $WORKSPACE"
echo "  ./post-deploy.sh <resource-group> <vm-name>"
echo
echo "For more information, refer to the documentation files:"
echo "  README.md - General overview"
echo "  CONFIGURATION.md - Configuration details"
echo "  BEST_PRACTICES.md - Best practices and recommendations"
echo "  TROUBLESHOOTING.md - Troubleshooting guide"
