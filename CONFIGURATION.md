# Cribl FIPS VM Configuration Guide

This document provides detailed information about configuring your FIPS-compliant Cribl VM deployment.

## Bicep Template Parameters

The Bicep template supports the following parameters for customization:

| Parameter | Description | Default Value |
|-----------|-------------|---------------|
| `vmName` | Name of the Virtual Machine | `cribl-fips-vm` |
| `adminUsername` | Admin username for the VM | `azureuser` |
| `sshPublicKey` | SSH public key for authentication | (Required) |
| `location` | Azure region for all resources | Resource group location |
| `vnetName` | Virtual Network Name | `criblVNet` |
| `subnetName` | Subnet Name | `criblSubnet` |
| `publicIpName` | Public IP Name | `criblPublicIP` |
| `nicName` | Network Interface Name | `criblNIC` |
| `nsgName` | Network Security Group Name | `criblNSG` |
| `vmSize` | VM Size | `Standard_B2ms` |
| `criblDownloadUrl` | Cribl Download URL | Latest 4.3.1 URL |
| `criblVersion` | Cribl Version | `4.3.1` |
| `criblBuild` | Cribl Build | `12f82b6a` |
| `criblArch` | Cribl Architecture | `linux-x64` |
| `criblMode` | Cribl Mode (stream or edge) | `stream` |
| `criblAdminPassword` | Cribl Admin Password | (Required) |
| `criblAdminUsername` | Cribl Admin Username | `admin` |
| `criblLicenseKey` | Cribl License Key | (Optional) |
| `dnsName` | DNS Name for Let's Encrypt SSL | (Required) |
| `emailAddress` | Email for Let's Encrypt SSL | (Required) |
| `criblFipsMode` | Enable FIPS mode for Cribl | `true` |
| `addDataDisk` | Add data disk for Cribl persistence | `true` |
| `dataDiskSizeGB` | Data disk size in GB | `128` |
| `configScriptUri` | URI for the configuration script | Repository URL |

## VM Sizing Recommendations

Choose a VM size based on your expected workload:

| Workload | Recommended Size | Description |
|----------|------------------|-------------|
| Development/Testing | `Standard_B2ms` | 2 vCPUs, 8 GB RAM |
| Small Production | `Standard_D4s_v3` | 4 vCPUs, 16 GB RAM |
| Medium Production | `Standard_D8s_v3` | 8 vCPUs, 32 GB RAM |
| High Volume | `Standard_E16s_v3` | 16 vCPUs, 128 GB RAM |

## Network Security Configuration

The deployment creates a Network Security Group with the following rules:

| Rule Name | Port | Protocol | Source | Purpose |
|-----------|------|----------|--------|---------|
| AllowSSH | 22 | TCP | * | SSH access to VM |
| AllowHTTP | 80 | TCP | * | Let's Encrypt verification |
| AllowHTTPS | 443 | TCP | * | HTTPS access |
| AllowCriblUI | 9000 | TCP | * | Cribl Web UI |

**Security Recommendations:**
- For production environments, restrict the source IP ranges for SSH access
- Consider using Azure Bastion for more secure VM management
- Add additional rules if you plan to use Cribl for ingesting logs via other ports

## Let's Encrypt SSL Configuration

The deployment automatically:

1. Installs Certbot for certificate management
2. Obtains a certificate for your specified domain
3. Configures Cribl to use this certificate
4. Sets up automatic certificate renewal

**Requirements:**
- You must have a valid domain name (e.g., cribl.example.com)
- You must be able to update DNS records to point to the VM's public IP
- The DNS must be properly configured before the script tries to obtain the certificate

## Cribl Configuration

The Cribl instance is configured with:

- FIPS-compliant mode enabled
- Admin user with secure password handling
- System service for automatic startup
- SSL certificates from Let's Encrypt

## Advanced Configuration

### Custom Cribl Configuration

To apply custom Cribl configuration, you can SSH into the VM and modify files in:
```
/opt/cribl-stream/local/cribl/
```

### Network Configuration

To modify network settings after deployment:

1. Update NSG rules through Azure Portal or CLI
2. If changing the domain name, you'll need to:
   - Update DNS records
   - Generate a new Let's Encrypt certificate
   - Update the Cribl configuration

### Data Persistence

For production environments, consider:

1. Adding a data disk for Cribl data
2. Setting up regular backups of Cribl configuration
3. Implementing a high-availability configuration

## Troubleshooting

### Certificate Issues

If Let's Encrypt certificate acquisition fails:

```bash
# Check certificate status
sudo certbot certificates

# View Certbot logs
sudo journalctl -u certbot

# Manually trigger certificate renewal
sudo certbot renew --dry-run
```

### Cribl Service Issues

If Cribl isn't starting properly:

```bash
# Check service status
sudo systemctl status cribl

# View Cribl logs
sudo cat /opt/cribl-stream/log/worker.log

# Restart the service
sudo systemctl restart cribl
```

## Upgrading Cribl

To upgrade Cribl to a newer version:

1. SSH into the VM
2. Download the new version:
   ```bash
   cd /opt
   curl -L https://cdn.cribl.io/dl/cribl-[NEW_VERSION]-[NEW_BUILD]-linux-x64.tgz -o cribl-new.tgz
   ```
3. Stop Cribl service:
   ```bash
   sudo systemctl stop cribl
   ```
4. Back up current installation:
   ```bash
   cp -r /opt/cribl-stream /opt/cribl-stream-backup
   ```
5. Extract new version:
   ```bash
   tar xvzf cribl-new.tgz
   ```
6. Copy configuration:
   ```bash
   cp -r /opt/cribl-stream-backup/local /opt/cribl/
   ```
7. Update symbolic link:
   ```bash
   rm /opt/cribl-stream
   ln -s /opt/cribl /opt/cribl-stream
   ```
8. Start service:
   ```bash
   sudo systemctl start cribl
   ```

## Security Best Practices

For enhanced security:

1. Implement Azure Private Link for secure network connectivity
2. Use Azure Key Vault for secrets management
3. Enable Azure Security Center for threat protection
4. Implement regular security patching schedule
5. Use Azure Monitor for monitoring and alerting
