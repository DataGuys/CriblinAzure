# CriblinAzure

FIPS-compliant Cribl Stream deployment for Azure with automated Let's Encrypt SSL certificate provisioning.

## Overview

This project deploys a turnkey FIPS-compliant Cribl Stream environment on Azure with:

- Ubuntu Pro FIPS 22.04 VM
- Automatic Let's Encrypt SSL certificate provisioning and renewal
- Proper FIPS-compliant configuration throughout
- Network security groups with properly configured access
- Systemd service for reliable operation
- Static IP for reliable DNS and certificate validation
- Key Vault integration for secret management (optional)
- Azure Monitor integration (optional)
- Azure Backup support (optional)

## Architecture

![Cribl FIPS VM Architecture](./architecture.png)

## Quick Deployment

### Option 1: Azure Cloud Shell (Recommended)

For the easiest deployment experience, use Azure Cloud Shell:

```bash
# Run this one-liner in Azure Cloud Shell
curl -sL https://raw.githubusercontent.com/DataGuys/CriblinAzure/main/cloudshell-install.sh | bash
```

This will:
1. Clone the repository
2. Set up the environment
3. Walk you through deployment options
4. Configure additional components as needed

### Option 2: Standard Deployment

```bash
# Clone the repository
git clone https://github.com/DataGuys/CriblinAzure.git
cd CriblinAzure

# Make the deployment script executable
chmod +x deploy-cribl-fips.sh

# Run the deployment script
./deploy-cribl-fips.sh
```

## Prerequisites

- Azure CLI installed and configured
- Active Azure subscription
- Bash shell environment
- A domain name with DNS control (for Let's Encrypt validation)
- SSH public key or ability to generate one during deployment

## Deployment Options

The deployment script allows configuration of:

- Resource group name and location
- VM name and size
- Admin username
- DNS name for Let's Encrypt SSL certificate
- Email address for Let's Encrypt notifications
- Cribl admin password
- Optional Cribl license key

## Post-Deployment Setup

After deploying the VM, you can run additional setup tasks:

```bash
# Run the post-deployment script for monitoring and backup setup
./post-deploy.sh <resource-group> <vm-name>
```

This script provides options to:
1. Verify your deployment
2. Configure monitoring with Azure Monitor
3. Set up automated backups
4. All of the above

## FIPS Compliance

This deployment ensures FIPS 140-2/140-3 compliance through:

- Ubuntu Pro FIPS certified operating system (22.04-lts-fips image)
- Secure password hashing using SHA-512
- Proper TLS configuration for Cribl web UI
- HTTPS-only access to UI components
- Least-privilege security groups

## SSL Certificate Management

Let's Encrypt certificates are automatically:

- Obtained during deployment using Certbot
- Configured for use with Cribl Stream
- Set up for automatic renewal (twice daily checks)
- Redeployed to Cribl when renewed

## After Deployment

After deployment:

1. Ensure your DNS record points to the static IP provided in the deployment output
2. Access Cribl UI at https://your-domain-name:9000
3. Log in with username "admin" and the password you provided during deployment

## Alternative Deployment Methods

### Terraform

For teams using Terraform instead of Bicep:

```bash
# Initialize Terraform
terraform init

# Plan the deployment
terraform plan -out tfplan

# Apply the deployment
terraform apply tfplan
```

## Documentation

- **[CONFIGURATION.md](./CONFIGURATION.md)** - Detailed configuration options
- **[BEST_PRACTICES.md](./BEST_PRACTICES.md)** - Deployment patterns and best practices
- **[TROUBLESHOOTING.md](./TROUBLESHOOTING.md)** - Solutions for common issues

## License

MIT License - See LICENSE file for details

## Support

For issues or contributions, please open an issue on GitHub.
