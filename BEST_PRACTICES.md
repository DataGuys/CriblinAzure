# Cribl FIPS VM Deployment Best Practices

This document provides guidelines and best practices for deploying and operating the FIPS-compliant Cribl VM in various scenarios.

## Deployment Patterns

### Development/Testing Environment

For non-production environments, consider these configurations:

- **VM Size**: `Standard_B2ms` (2 vCPUs, 8 GB RAM)
- **Storage**: Standard HDD (locally redundant)
- **Network**: Default NSG with access limited to your development network
- **Backup**: Weekly backups with 14-day retention
- **High Availability**: Not required

```bash
./deploy-cribl-fips.sh \
  --resource-group cribl-dev-rg \
  --vm-size Standard_B2ms \
  --no-data-disk \
  --dev-mode
```

### Small Production Environment

For small production environments (up to ~100 GB/day):

- **VM Size**: `Standard_D4s_v3` (4 vCPUs, 16 GB RAM)
- **Storage**: Premium SSD with 256 GB data disk
- **Network**: Custom NSG with IP restrictions for admin access
- **Backup**: Daily backups with 30-day retention
- **High Availability**: Consider Azure Availability Sets

```bash
./deploy-cribl-fips.sh \
  --resource-group cribl-prod-rg \
  --vm-size Standard_D4s_v3 \
  --data-disk-size 256 \
  --admin-source-ip 10.0.0.0/24
```

### Enterprise Production Environment

For large production environments (100+ GB/day):

- **VM Size**: `Standard_E16s_v3` (16 vCPUs, 128 GB RAM) or larger
- **Storage**: Premium SSD with 1 TB+ data disk
- **Network**: Private network with Azure Private Link
- **Backup**: Daily backups with 90-day retention
- **High Availability**: Use VM Scale Sets or multiple instances with load balancing

```bash
./deploy-cribl-fips.sh \
  --resource-group cribl-enterprise-rg \
  --vm-size Standard_E16s_v3 \
  --data-disk-size 1024 \
  --private-network \
  --key-vault-integration
```

## Security Hardening

### Network Security

1. **Restrict SSH Access**:
   - Limit SSH access to specific IP ranges
   - Consider using Azure Bastion for secure SSH access
   - Implement Just-In-Time access using Azure Security Center

2. **Implement Network Segmentation**:
   - Place the VM in a dedicated subnet
   - Use NSGs to control traffic between subnets
   - Consider using Azure Firewall for additional protection

3. **Use Private Endpoints**:
   - For production environments, use Azure Private Link
   - Connect to Azure services without exposing traffic to the internet

### FIPS Compliance

1. **Verify FIPS Mode**:
   - Confirm FIPS mode is enabled in the OS: `cat /proc/sys/crypto/fips_enabled`
   - Verify Cribl is using FIPS-compliant cryptographic modules

2. **Compliance Documentation**:
   - Document the FIPS-compliant components in your deployment
   - Include cryptographic boundary diagrams for audits
   - Maintain records of FIPS validation certificates

3. **Regular Validation**:
   - Periodically verify FIPS compliance with automated tests
   - Check for any new components that might affect compliance

## Performance Optimization

### VM Sizing Guidelines

| Data Volume | VM Size Recommendation | CPU | Memory | Disk |
|-------------|------------------------|-----|--------|------|
| < 50 GB/day | Standard_D4s_v3        | 4   | 16 GB  | 256 GB |
| 50-200 GB/day | Standard_D8s_v3      | 8   | 32 GB  | 512 GB |
| 200-500 GB/day | Standard_E8s_v3     | 8   | 64 GB  | 1 TB |
| 500+ GB/day | Standard_E16s_v3       | 16  | 128 GB | 2 TB |

### Storage Configuration

1. **Data Disk Striping**:
   - For high throughput, consider using multiple data disks in a RAID 0 configuration
   - Example setup in `/etc/opt/cribl-config.sh`:

```bash
#!/bin/bash
# Set up disk striping for high throughput
apt-get install -y mdadm
mdadm --create /dev/md0 --level=0 --raid-devices=4 /dev/sdc /dev/sdd /dev/sde /dev/sdf
mkfs.ext4 /dev/md0
mount /dev/md0 /data
```

2. **Disk Caching Settings**:
   - Enable read/write caching for optimal performance
   - Configure Azure VM disk caching parameters:

```bash
az vm update \
  --resource-group cribl-prod-rg \
  --name cribl-fips-vm \
  --set storageProfile.dataDisks[0].caching=ReadWrite
```

### Memory Management

1. **Java Heap Sizing**:
   - Configure appropriate heap sizes for Cribl
   - Add to `/opt/cribl-stream/default/cribl/cribl.yml`:

```yaml
system:
  javaHeapSize: 16g
```

2. **OS Settings**:
   - Adjust swappiness for better memory management:

```bash
echo "vm.swappiness=10" >> /etc/sysctl.conf
sysctl -p
```

## High Availability

### Multi-Region Deployment

For mission-critical deployments, consider a multi-region setup:

1. **Primary/Secondary Regions**:
   - Deploy VMs in two separate Azure regions
   - Use Azure Traffic Manager for DNS-based routing

2. **Data Replication**:
   - Configure Cribl replication between regions
   - Use Azure Storage with geo-redundancy for persistent data

3. **Automated Failover**:
   - Implement health checks to detect failures
   - Automate failover using Azure Automation runbooks

### Load Balancing

For high-throughput environments:

1. **Azure Load Balancer**:
   - Set up Azure Load Balancer in HA ports mode
   - Configure health probes for each Cribl instance

2. **Cribl Worker Groups**:
   - Configure Cribl in distributed mode with multiple workers
   - Balance incoming traffic across worker nodes

## Operational Excellence

### Monitoring Strategy

Implement comprehensive monitoring using:

1. **Azure Monitor**:
   - VM metrics (CPU, memory, disk, network)
   - Application logs from Cribl
   - Custom metrics from Cribl's internal statistics

2. **Alerting**:
   - Critical alerts: Service availability, data pipeline failures
   - Warning alerts: High resource utilization, certificate expiration
   - Informational alerts: Configuration changes, backup status

3. **Dashboards**:
   - Create custom dashboards for different stakeholders
   - Include key performance indicators and SLA metrics

### Backup and Recovery

1. **Backup Strategy**:
   - System state: VM snapshots via Azure Backup
   - Configuration: Cribl configuration export to Azure Storage
   - Data: Regular backups of persistent storage

2. **Disaster Recovery Testing**:
   - Regularly test recovery procedures
   - Document recovery time objectives (RTO) and point objectives (RPO)
   - Simulate different failure scenarios

### Update Management

1. **Patching Approach**:
   - OS updates: Use Azure Update Management
   - Cribl updates: Follow the upgrade guidance in CONFIGURATION.md
   - Schedule maintenance windows with minimal impact

2. **Version Control**:
   - Maintain Cribl configurations in a Git repository
   - Use infrastructure as code for all components
   - Document changes with clear commit messages

## Cost Optimization

### Resource Sizing

1. **Right-sizing VMs**:
   - Monitor actual utilization and adjust VM size accordingly
   - Consider B-series VMs for development/testing

2. **Storage Optimization**:
   - Use tiered storage for logs (hot/cool/archive)
   - Implement data lifecycle management

### Reserved Instances

For long-term deployments, consider:

1. **Azure Reserved VM Instances**:
   - Purchase 1-year or 3-year reservations for significant savings
   - Match reservation to your committed usage

2. **Hybrid Benefit**:
   - If applicable, use Azure Hybrid Benefit to save on licensing costs

### Automation for Cost Control

1. **Auto-shutdown for Non-Production**:
   - Schedule shutdown of development/testing VMs during off-hours
   - Use Azure Automation to implement schedules

2. **Scaling Based on Demand**:
   - Implement auto-scaling for variable workloads
   - Scale down during periods of low activity

## Compliance and Governance

### Documentation Requirements

Maintain the following documentation for compliance:

1. **System Security Plan**:
   - Architecture diagrams
   - Data flow documentation
   - Security controls implemented

2. **Compliance Matrices**:
   - FIPS 140-2/140-3 compliance evidence
   - Additional frameworks (FedRAMP, HIPAA, etc.) if applicable

3. **Audit Logs**:
   - Enable Azure Activity Logs
   - Implement log retention policies based on compliance requirements

### Azure Policy

Implement Azure Policy to enforce:

1. **Resource Tagging**:
   - Require mandatory tags (environment, owner, cost center)
   - Automate tag inheritance

2. **Compliance Controls**:
   - Enforce encryption settings
   - Require secure network configurations
   - Audit security settings

## Troubleshooting Common Issues

See the detailed TROUBLESHOOTING.md document for specific issues and solutions. Common categories include:

1. **Deployment Failures**:
   - Resource provisioning issues
   - Template validation errors
   - Permission problems

2. **Certificate Issues**:
   - Let's Encrypt validation failures
   - Certificate renewal problems
   - SSL configuration errors

3. **Performance Problems**:
   - Resource contention
   - Disk I/O bottlenecks
   - Network latency issues

4. **FIPS Compliance**:
   - Validation errors
   - Cryptographic module issues
   - Configuration discrepancies

## Additional Resources

- [Cribl Documentation](https://docs.cribl.io/)
- [Azure FIPS Compliance](https://docs.microsoft.com/en-us/azure/compliance/offerings/offering-fips-140-2)
- [Azure Security Best Practices](https://docs.microsoft.com/en-us/azure/security/fundamentals/best-practices-and-patterns)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
