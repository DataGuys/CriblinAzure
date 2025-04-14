#!/bin/bash
set -e

# This script is embedded in the VM's customData and is executed at first boot
# It installs necessary dependencies and prepares the system
# The actual configuration of Cribl with Let's Encrypt will be done by the CustomScriptExtension

# Update and install dependencies
apt-get update
apt-get install -y curl tar snapd ca-certificates software-properties-common

# Ensure snap is up-to-date
snap wait system seed.loaded
snap install core
snap refresh core

# Create the script directory for the CustomScriptExtension
mkdir -p /var/lib/waagent/custom-script/download/0/
cat > /var/lib/waagent/custom-script/download/0/configure-cribl.sh << 'EOL'
#!/bin/bash
set -e

# Script variables
LOG_FILE="/var/log/cribl-deploy.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

log "Starting Cribl configuration script"

# This script will be executed by the CustomScriptExtension
# Parameters passed to this script
CRIBL_DOWNLOAD_URL=$1
CRIBL_VERSION=$2
CRIBL_MODE=$3
CRIBL_ADMIN_USERNAME=$4
CRIBL_ADMIN_PASSWORD=$5
DNS_NAME=$6
EMAIL_ADDRESS=$7
CRIBL_LICENSE_KEY=$8
CRIBL_FIPS_MODE=${9:-true}
USE_DATA_DISK=${10:-true}

log "Parameters received:"
log "- Cribl Version: $CRIBL_VERSION"
log "- Cribl Mode: $CRIBL_MODE"
log "- DNS Name: $DNS_NAME"
log "- FIPS Mode: $CRIBL_FIPS_MODE"
log "- Use Data Disk: $USE_DATA_DISK"

log "Starting Cribl configuration with Let's Encrypt SSL..."

# Install Certbot via snap (preferred method for Ubuntu 22.04)
log "Installing Certbot..."
snap install --classic certbot
ln -sf /snap/bin/certbot /usr/bin/certbot

# Create a basic web server for Let's Encrypt validation
log "Setting up Nginx for Let's Encrypt validation..."
apt-get update
apt-get install -y nginx

# Check FIPS status
log "Checking FIPS status on the system..."
FIPS_STATUS=$(cat /proc/sys/crypto/fips_enabled || echo "Unknown")
log "Current FIPS status: $FIPS_STATUS"

# If data disk is enabled, set it up
if [[ "$USE_DATA_DISK" == "true" ]]; then
    log "Setting up data disk..."
    
    # Check for the data disk
    if [ -b /dev/sdc ]; then
        log "Data disk found at /dev/sdc"
        
        # Check if disk is already formatted
        if ! blkid /dev/sdc1 &>/dev/null; then
            log "Partitioning data disk..."
            parted /dev/sdc mklabel gpt
            parted -a opt /dev/sdc mkpart primary ext4 0% 100%
            
            log "Formatting data disk..."
            mkfs.ext4 /dev/sdc1
        else
            log "Data disk is already partitioned and formatted"
        fi
        
        # Create mount point and mount
        log "Mounting data disk..."
        mkdir -p /data
        
        # Get UUID
        DATA_DISK_UUID=$(blkid -s UUID -o value /dev/sdc1)
        
        # Add to fstab if not already there
        if ! grep -q "$DATA_DISK_UUID" /etc/fstab; then
            log "Adding data disk to fstab..."
            echo "UUID=$DATA_DISK_UUID /data ext4 defaults 0 2" >> /etc/fstab
        fi
        
        # Mount the disk
        mount /data
        log "Data disk mounted at /data"
    else
        log "No data disk found at /dev/sdc, continuing without persistent storage"
    fi
fi

# Obtain Let's Encrypt certificate
log "Obtaining Let's Encrypt certificate for $DNS_NAME..."
certbot certonly --nginx --non-interactive --agree-tos --email $EMAIL_ADDRESS -d $DNS_NAME

# Stop NGINX as we'll use Cribl's web server
log "Stopping Nginx..."
systemctl stop nginx
systemctl disable nginx

# Download and install Cribl
log "Downloading Cribl $CRIBL_VERSION..."
cd /opt
curl -L ${CRIBL_DOWNLOAD_URL} -o cribl.tgz
log "Extracting Cribl..."
tar xvzf cribl.tgz
mv cribl cribl-${CRIBL_MODE}
cd cribl-${CRIBL_MODE}

# Configure Cribl mode
log "Configuring Cribl mode to ${CRIBL_MODE}..."
./bin/cribl mode-${CRIBL_MODE}

# Create Cribl admin user
log "Configuring Cribl admin user..."
# Create users directory if it doesn't exist
mkdir -p ./local/cribl/auth/users/

# Create admin user with password
cat > ./local/cribl/auth/users/${CRIBL_ADMIN_USERNAME}.json << EOF
{
  "id": "${CRIBL_ADMIN_USERNAME}",
  "username": "${CRIBL_ADMIN_USERNAME}",
  "first": "FIPS",
  "last": "Admin",
  "email": "${EMAIL_ADDRESS}",
  "password": "$(echo -n ${CRIBL_ADMIN_PASSWORD} | sha512sum | awk '{print $1}')",
  "roles": ["admin"]
}
EOF

# Configure Cribl to use Let's Encrypt certificates
log "Configuring SSL for Cribl..."
mkdir -p ./local/cribl/certificates

# Copy Let's Encrypt certificates to Cribl
cp /etc/letsencrypt/live/${DNS_NAME}/fullchain.pem ./local/cribl/certificates/cribl.crt
cp /etc/letsencrypt/live/${DNS_NAME}/privkey.pem ./local/cribl/certificates/cribl.key

# Set up Cribl directories on data disk if available
if [[ "$USE_DATA_DISK" == "true" ]] && [ -d "/data" ]; then
    log "Setting up Cribl directories on data disk..."
    
    # Create directories on data disk
    mkdir -p /data/cribl/data
    mkdir -p /data/cribl/local
    
    # Copy existing data
    cp -rp ./data/* /data/cribl/data/ || true
    cp -rp ./local/* /data/cribl/local/ || true
    
    # Create symlinks
    log "Creating symlinks to data disk..."
    rm -rf ./data
    rm -rf ./local
    ln -s /data/cribl/data ./data
    ln -s /data/cribl/local ./local
fi

# Configure FIPS mode if enabled
FIPS_CONFIG=""
if [[ "$CRIBL_FIPS_MODE" == "true" ]]; then
    log "Enabling FIPS mode for Cribl..."
    FIPS_CONFIG="crypto:
  fipsMode: true"
fi

# Update Cribl system settings for SSL and FIPS
cat > ./local/cribl/system.yml << EOF
distributed:
  mode: ${CRIBL_MODE}
api:
  host: 0.0.0.0
  port: 9000
  disabled: false
  ssl:
    disabled: false
    privKeyPath: $PWD/local/cribl/certificates/cribl.key
    certPath: $PWD/local/cribl/certificates/cribl.crt
auth:
  type: native
  timeout: 1440
$FIPS_CONFIG
EOF

# Set up auto-renewal for Let's Encrypt certificates
log "Setting up auto-renewal for Let's Encrypt certificates..."
cat > /etc/cron.d/certbot-renew << EOF
0 0,12 * * * root certbot renew --quiet --deploy-hook "cp /etc/letsencrypt/live/${DNS_NAME}/fullchain.pem /opt/cribl-${CRIBL_MODE}/local/cribl/certificates/cribl.crt && cp /etc/letsencrypt/live/${DNS_NAME}/privkey.pem /opt/cribl-${CRIBL_MODE}/local/cribl/certificates/cribl.key && systemctl restart cribl"
EOF

# Optional: Add license key
if [ ! -z "${CRIBL_LICENSE_KEY}" ]; then
  log "Adding Cribl license key..."
  ./bin/cribl license add ${CRIBL_LICENSE_KEY}
fi

# Create systemd service for Cribl
log "Creating systemd service for Cribl..."
cat > /etc/systemd/system/cribl.service << EOF
[Unit]
Description=Cribl ${CRIBL_MODE^}
After=network.target

[Service]
Type=forking
User=root
WorkingDirectory=/opt/cribl-${CRIBL_MODE}
ExecStart=/opt/cribl-${CRIBL_MODE}/bin/cribl start
ExecStop=/opt/cribl-${CRIBL_MODE}/bin/cribl stop
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Enable and start Cribl service
log "Enabling and starting Cribl service..."
systemctl daemon-reload
systemctl enable cribl
systemctl start cribl

# Wait for service to start
sleep 5

# Verify Cribl is running
log "Verifying Cribl service status..."
systemctl status cribl --no-pager

log "Cribl ${CRIBL_MODE^} with Let's Encrypt SSL has been configured successfully!"
log "Access the Cribl UI at: https://${DNS_NAME}:9000"
log "FIPS mode: ${CRIBL_FIPS_MODE}"
log "Data persistence: ${USE_DATA_DISK}"
EOL

# Make the script executable
chmod +x /var/lib/waagent/custom-script/download/0/configure-cribl.sh

echo "First-boot script completed. VM is ready for the CustomScriptExtension."
