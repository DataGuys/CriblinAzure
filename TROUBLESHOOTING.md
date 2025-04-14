# Troubleshooting Guide: Cribl FIPS VM Deployment

This document provides solutions for common issues that may arise during the deployment and operation of your FIPS-compliant Cribl VM.

## Deployment Issues

### Azure Deployment Fails

**Symptoms:**
- The deployment script errors out during the Azure deployment phase
- Error messages from the Azure Resource Manager

**Troubleshooting Steps:**
1. Check quotas and limits:
   ```bash
   az vm list-usage --location eastus -o table
   ```

2. Verify subscription status:
   ```bash
   az account show
   ```

3. Check deployment errors:
   ```bash
   az deployment group show --resource-group YOUR_RESOURCE_GROUP \
     --name cribl-fips-vm-with-ssl --query properties.error
   ```

4. Verify template syntax:
   ```bash
   az deployment group validate --resource-group YOUR_RESOURCE_GROUP \
     --template-file cribl-fips-vm-with-ssl.bicep
   ```

**Common Solutions:**
- If you hit quota limits, request an increase through Azure Portal
- If your subscription is inactive, update payment information
- Check for syntax errors in the Bicep template and fix them

### Custom Script Extension Fails

**Symptoms:**
- VM is deployed but Cribl is not properly configured
- Let's Encrypt certificate is not obtained

**Troubleshooting Steps:**
1. Check extension status:
   ```bash
   az vm extension show --resource-group YOUR_RESOURCE_GROUP \
     --vm-name YOUR_VM_NAME --name CustomScript
   ```

2. SSH into the VM and check script logs:
   ```bash
   ssh azureuser@YOUR_VM_IP
   sudo cat /var/log/azure/custom-script/handler.log
   sudo cat /var/log/waagent.log
   ```

**Common Solutions:**
- Verify DNS is correctly configured for your domain
- Ensure port 80 is open for Let's Encrypt validation
- Manually run the configuration script:
  ```bash
  sudo bash /var/lib/waagent/custom-script/download/0/configure-cribl.sh
  ```

## Let's Encrypt Certificate Issues

### Certificate Acquisition Fails

**Symptoms:**
- The script runs but cannot obtain a Let's Encrypt certificate
- Error in Certbot logs

**Troubleshooting Steps:**
1. Check certificate status:
   ```bash
   sudo certbot certificates
   ```

2. View Certbot logs:
   ```bash
   sudo journalctl -u certbot
   ```

3. Verify DNS configuration:
   ```bash
   nslookup YOUR_DOMAIN_NAME
   ```

**Common Solutions:**
- Ensure DNS A record points to your VM's public IP
- Allow time for DNS propagation (up to 48 hours in some cases)
- Verify port 80 is open in the NSG and any firewalls
- Manually request a certificate:
  ```bash
  sudo certbot certonly --standalone --non-interactive \
    --agree-tos --email YOUR_EMAIL -d YOUR_DOMAIN
  ```

### Certificate Renewal Issues

**Symptoms:**
- Certificate expires after 90 days
- Renewal task fails

**Troubleshooting Steps:**
1. Check the renewal timer:
   ```bash
   sudo systemctl list-timers | grep certbot
   ```

2. Test renewal process:
   ```bash
   sudo certbot renew --dry-run
   ```

**Common Solutions:**
- Ensure the renewal cron job is properly configured:
  ```bash
  sudo cat /etc/cron.d/certbot-renew
  ```
- Manually trigger renewal:
  ```bash
  sudo certbot renew
  ```
- Update certificate paths in Cribl configuration

## Cribl Service Issues

### Cribl Service Won't Start

**Symptoms:**
- Cribl service fails to start
- Can't access Cribl UI at port 9000

**Troubleshooting Steps:**
1. Check service status:
   ```bash
   sudo systemctl status cribl
   ```

2. Examine Cribl logs:
   ```bash
   sudo cat /opt/cribl-stream/log/worker.log
   sudo cat /opt/cribl-stream/log/main.log
   ```

3. Check for port conflicts:
   ```bash
   sudo netstat -tulpn | grep 9000
   ```

**Common Solutions:**
- Restart the service:
  ```bash
  sudo systemctl restart cribl
  ```
- Check for configuration errors:
  ```bash
  sudo cat /opt/cribl-stream/local/cribl/system.yml
  ```
- Verify SSL certificate paths are correct

### Authentication Issues

**Symptoms:**
- Can't log in to Cribl UI
- Password seems incorrect

**Troubleshooting Steps:**
1. Check user configuration:
   ```bash
   sudo cat /opt/cribl-stream/local/cribl/auth/users/admin.json
   ```

2. Verify authentication settings:
   ```bash
   sudo cat /opt/cribl-stream/local/cribl/system.yml | grep auth
   ```

**Common Solutions:**
- Reset the admin password:
  ```bash
  cd /opt/cribl-stream
  sudo ./bin/cribl users reset admin
  ```
- Update the admin user configuration file with a new password hash

## Network Issues

### Can't Access Cribl UI

**Symptoms:**
- Unable to connect to https://YOUR_DOMAIN:9000
- Connection timeout or refused

**Troubleshooting Steps:**
1. Check if Cribl service is running:
   ```bash
   sudo systemctl status cribl
   ```

2. Verify NSG rules:
   ```bash
   az network nsg rule list --resource-group YOUR_RESOURCE_GROUP \
     --nsg-name YOUR_NSG_NAME -o table
   ```

3. Check local firewall on VM:
   ```bash
   sudo iptables -L
   ```

4. Test connectivity:
   ```bash
   curl -k https://localhost:9000
   ```

**Common Solutions:**
- Ensure port 9000 is open in the NSG
- Verify Cribl is properly configured to listen on 0.0.0.0
- Check certificate configuration in system.yml

### SSL Certificate Warnings

**Symptoms:**
- Browser shows certificate warnings
- Invalid certificate errors

**Troubleshooting Steps:**
1. Verify certificate path:
   ```bash
   sudo ls -l /opt/cribl-stream/local/cribl/certificates/
   ```

2. Check certificate validity:
   ```bash
   sudo openssl x509 -in /opt/cribl-stream/local/cribl/certificates/cribl.crt -text -noout
   ```

3. Verify Cribl configuration:
   ```bash
   sudo cat /opt/cribl-stream/local/cribl/system.yml | grep ssl
   ```

**Common Solutions:**
- Ensure DNS name matches the certificate's Common Name
- Update certificate paths in Cribl configuration
- Manually copy Let's Encrypt certificates:
  ```bash
  sudo cp /etc/letsencrypt/live/YOUR_DOMAIN/fullchain.pem /opt/cribl-stream/local/cribl/certificates/cribl.crt
  sudo cp /etc/letsencrypt/live/YOUR_DOMAIN/privkey.pem /opt/cribl-stream/local/cribl/certificates/cribl.key
  ```

## FIPS Compliance Issues

### Verifying FIPS Mode

**Symptoms:**
- Need to verify if the system is running in FIPS mode
- Compliance audit requirements

**Troubleshooting Steps:**
1. Check Ubuntu FIPS status:
   ```bash
   cat /proc/sys/crypto/fips_enabled
   ```
   (Should return 1 if FIPS is enabled)

2. Verify FIPS policy:
   ```bash
   sudo update-crypto-policies --show
   ```

3. Check OpenSSL FIPS status:
   ```bash
   openssl md5 /dev/null
   ```
   (Should give an error about disabled algorithms if in FIPS mode)

**Common Solutions:**
- Ensure VM is using the correct Ubuntu Pro FIPS image
- Verify Cribl is configured to use FIPS-compliant cryptographic settings

## Data Persistence Issues

### Data Loss After VM Restart

**Symptoms:**
- Cribl configuration or data is lost after VM restart
- Changes don't persist

**Troubleshooting Steps:**
1. Check Cribl data directories:
   ```bash
   ls -la /opt/cribl-stream/data
   ls -la /opt/cribl-stream/local
   ```

2. Verify file permissions:
   ```bash
   sudo find /opt/cribl-stream -type f -exec stat -c "%U:%G %a %n" {} \;
   ```

**Common Solutions:**
- Configure a data disk for persistent storage:
  ```bash
  sudo parted /dev/sdc mklabel gpt
  sudo parted -a opt /dev/sdc mkpart primary ext4 0% 100%
  sudo mkfs.ext4 /dev/sdc1
  sudo mkdir -p /data
  sudo mount /dev/sdc1 /data
  sudo cp -rp /opt/cribl-stream/data /data/
  sudo cp -rp /opt/cribl-stream/local /data/
  ```
  
- Update fstab for auto-mount:
  ```bash
  echo "UUID=$(blkid -s UUID -o value /dev/sdc1) /data ext4 defaults 0 2" | sudo tee -a /etc/fstab
  ```

- Symlink Cribl directories:
  ```bash
  sudo mv /opt/cribl-stream/data /opt/cribl-stream/data.old
  sudo mv /opt/cribl-stream/local /opt/cribl-stream/local.old
  sudo ln -s /data/data /opt/cribl-stream/data
  sudo ln -s /data/local /opt/cribl-stream/local
  ```

## Additional Resources

- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [Cribl Stream Documentation](https://docs.cribl.io/)
- [Ubuntu Pro FIPS Documentation](https://ubuntu.com/security/fips)
- [Azure VM Troubleshooting](https://docs.microsoft.com/en-us/azure/virtual-machines/troubleshooting/)

If you continue to experience issues after trying these troubleshooting steps, please open an issue on GitHub or contact your support resources.
