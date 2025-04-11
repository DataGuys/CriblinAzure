# CriblinAzure

FIPS-compliant Cribl Stream deployment for Azure with secure networking.

## Overview

This project deploys a FIPS-compliant Cribl Stream environment on Azure with:
- Ubuntu Pro FIPS 22.04 VM
- Azure Firewall for secure ingress/egress
- Network security groups with least-privilege access
- Optional site-to-site VPN gateway
- FIPS-compliant configuration throughout

## Quick Deployment

```bash
curl -sSL "https://raw.githubusercontent.com/DataGuys/CriblinAzure/refs/heads/main/deploy.sh" -o deploy.sh && chmod +x deploy.sh && ./deploy.sh
```

## Prerequisites

- Azure CLI installed and configured
- Active Azure subscription
- Bash shell environment
- OpenSSL for FIPS-compliant key generation

## Deployment Options

The deployment script allows configuration of:
- Resource group name and location
- DNS name for public access
- VM admin credentials (auto-generated secure password)
- VPN gateway with FIPS-compliant shared key
- On-premises network settings

## FIPS Compliance

This deployment ensures FIPS 140-2/140-3 compliance through:
- Ubuntu Pro FIPS certified operating system
- FIPS-compliant VPN key generation (uses NIST SP 800-132 recommendations)
- Cribl Stream running in FIPS mode
- TLS-secured communications

## Architecture

```
Internet → Azure Firewall → Ubuntu FIPS VM (Cribl Stream)
                         ↑
                         ↓
On-premises Network ← VPN Gateway
```

## Post-Deployment

After deployment:
1. Access Cribl via the Firewall FQDN (https://<dns-name>.<region>.cloudapp.azure.com)
2. Default ports: 443 (HTTPS), 6514 (Syslog over TLS)
3. For VPN configuration, use the generated FIPS-compliant shared key

## License

MIT License - See LICENSE file for details

## Support

For issues or contributions, please open an issue on GitHub.
