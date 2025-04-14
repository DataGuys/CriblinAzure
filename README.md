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

## Quick Deployment

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

## FIPS Compliance

This deployment ensures FIPS 140-2/140-3 compliance through:

- Ubuntu Pro FIPS certified operating system (22.04-lts-fips image)
- Secure password hashing using SHA-512
- Proper TLS configuration for Cribl web UI
- HTTPS-only access to UI components
- Least-privilege security groups

## Architecture

```
                  ┌──────────────────┐
                  │                  │
Internet ────────►│ Azure NSG        │
                  │                  │
                  └────────┬─────────┘
                           │
                           ▼
                  ┌──────────────────┐
                  │                  │
                  │ Ubuntu FIPS VM   │
                  │ (Cribl Stream)   │
                  │                  │
                  └──────────────────┘
```

## SSL Certificate Management

Let's Encrypt certificates are automatically:

- Obtained during deployment using Certbot
- Configured for use with Cribl Stream
- Set up for automatic renewal (twice daily checks)
- Redeployed to Cribl when renewed

## Post-Deployment

After deployment:

1. Ensure your DNS record points to the static IP provided in the deployment output
2. Access Cribl UI at https://your-domain-name:9000
3. Log in with username "admin" and the password you provided during deployment

## Customization

The Bicep template supports several parameters for customization:

- `vmSize`: VM size (default: Standard_B2ms)
- `criblVersion`: Cribl Stream version
- `criblMode`: Stream or Edge mode
- `criblAdminUsername`: Admin username (default: admin)

## Troubleshooting

### Certificate Issues

If Let's Encrypt fails to obtain a certificate:

1. Verify your DNS records are correctly pointing to the VM's public IP
2. Check the certificate logs: `sudo certbot certificates`
3. View detailed logs: `sudo journalctl -u certbot`

### Cribl Service Issues

To check Cribl service status:

```bash
sudo systemctl status cribl
```

View Cribl logs:

```bash
sudo cat /opt/cribl-stream/log/worker.log
```

## License

MIT License - See LICENSE file for details

## Support

For issues or contributions, please open an issue on GitHub.
