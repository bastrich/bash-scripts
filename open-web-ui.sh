#!/bin/bash -e

if [ -z "$1" ]; then
    echo "Error: domain is not specified."
    echo "Usage: $0 <domain_name> <email>"
    exit 1
fi

if [ -z "$2" ]; then
    echo "Error: email is not specified."
    echo "Usage: $0 <domain_name> <email>"
    exit 1
fi

DOMAIN=$1
EMAIL=$2

# CONFIGURE NGINX

apt install curl gnupg2 ca-certificates lsb-release ubuntu-keyring

curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor | tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null

gpg --dry-run --quiet --no-keyring --import --import-options import-show /usr/share/keyrings/nginx-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/ubuntu `lsb_release -cs` nginx" | tee /etc/apt/sources.list.d/nginx.list

echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | tee /etc/apt/preferences.d/99nginx

apt update
apt install -y nginx

nginx

cat <<EOT > /etc/nginx/conf.d/default.conf
server {
    server_name $DOMAIN;
    listen 80;

    access_log  /var/log/nginx/open-webui.access.log  main;
    error_log /var/log/nginx/open-webui.error.log;

    location / {
        proxy_pass http://localhost:3000;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_read_timeout 300s;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
    }
}
EOT

nginx -s reload

# CONFIGURE HTTPS

snap install core
snap refresh core
apt-get remove -y certbot
snap install --classic certbot
ln -s /snap/bin/certbot /usr/bin/certbot
sudo certbot --nginx \
  --non-interactive \
  --agree-tos \
  -m $EMAIL \
  --no-eff-email \
  --redirect \
  -d $DOMAIN
nginx -s reload

# CONFIGURE FIREWALL

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22
ufw allow 80
ufw allow 443
ufw --force enable
ufw status verbose

# CONFIGURE OPEN WEB UI
apt install -y docker.io
systemctl start docker
systemctl enable docker

docker run -d -p 3000:8080 --add-host=host.docker.internal:host-gateway -v open-webui:/app/backend/data --name open-webui --restart always ghcr.io/open-webui/open-webui:main

# https://openwebui.com/posts/openrouter_integration_for_openwebui_49e4df36
