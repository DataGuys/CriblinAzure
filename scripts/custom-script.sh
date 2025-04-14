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

echo "Starting Cribl configuration with Let's Encrypt SSL..."

# Install Certbot via snap (preferred method for Ubuntu 22.04)
snap install --classic certbot
ln -sf /snap/bin/certbot /usr/bin/certbot

# Create a basic web server for Let's Encrypt validation
apt-get update
apt-get install -y nginx

# Obtain Let's Encrypt certificate
echo "Obtaining Let's Encrypt certificate for $DNS_NAME..."
certbot certonly --nginx --non-interactive --agree-tos --email $EMAIL_ADDRESS -d $DNS_NAME

# Stop NGINX as we'll use Cribl's web server
systemctl stop nginx
systemctl disable nginx

# Download and install Cribl
echo "Installing Cribl ${CRIBL_VERSION}..."
cd /opt
curl -L ${CRIBL_DOWNLOAD_URL} -o cribl.tgz
tar xvzf cribl.tgz
mv cribl cribl-${CRIBL_MODE}
cd cribl-${CRIBL_MODE}

# Configure Cribl mode
echo "Configuring Cribl mode to ${CRIBL_MODE}..."
./bin/cribl mode-${CRIBL_MODE}

# Create Cribl admin user
echo "Configuring Cribl admin user..."
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
echo "Configuring SSL for Cribl..."
mkdir -p ./local/cribl/certificates

# Copy Let's Encrypt certificates to Cribl
cp /etc/letsencrypt/live/${DNS_NAME}/fullchain.pem ./local/cribl/certificates/cribl.crt
cp /etc/letsencrypt/live/${DNS_NAME}/privkey.pem ./local/cribl/certificates/cribl.key

# Update Cribl system settings for SSL
cat > ./local/cribl/system.yml << EOF
distributed:
  mode: ${CRIBL_MODE}
api:
  host: 0.0.0.0
  port: 9000
  disabled : false
  ssl:
    disabled: false
    privKeyPath: $PWD/local/cribl/certificates/cribl.key
    certPath: $PWD/local/cribl/certificates/cribl.crt
auth:
  type: native
  timeout: 1440
EOF

# Set up auto-renewal for Let's Encrypt certificates
echo "Setting up auto-renewal for Let's Encrypt certificates..."
cat > /etc/cron.d/certbot-renew << EOF
0 0,12 * * * root certbot renew --quiet --deploy-hook "cp /etc/letsencrypt/live/${DNS_NAME}/fullchain.pem /opt/cribl-${CRIBL_MODE}/local/cribl/certificates/cribl.crt && cp /etc/letsencrypt/live/${DNS_NAME}/privkey.pem /opt/cribl-${CRIBL_MODE}/local/cribl/certificates/cribl.key && systemctl restart cribl"
EOF

# Optional: Add license key
if [ ! -z "${CRIBL_LICENSE_KEY}" ]; then
  echo "Adding Cribl license key..."
  ./bin/cribl license add ${CRIBL_LICENSE_KEY}
fi

# Create systemd service for Cribl
echo "Creating systemd service for Cribl..."
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
systemctl daemon-reload
systemctl enable cribl
systemctl start cribl

# Verify Cribl is running
systemctl status cribl --no-pager

echo "Cribl ${CRIBL_MODE^} with Let's Encrypt SSL has been configured successfully!"
echo "Access the Cribl UI at: https://${DNS_NAME}:9000"
EOL

# Make the script executable
chmod +x /var/lib/waagent/custom-script/download/0/configure-cribl.sh

echo "First-boot script completed. VM is ready for the CustomScriptExtension."
