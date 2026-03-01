#!/bin/bash -e

if [ -z "$1" ]; then
    echo "Error: domain is not specified."
    echo "Usage: $0 <domain_name> <email> <password> <openai_api_base_url> <openai_api_key> <openai_api_stt_key> <openai_ig_api_base_url> <openai_ig_api_key>"
    exit 1
fi

if [ -z "$2" ]; then
    echo "Error: email is not specified."
    echo "Usage: $0 <domain_name> <email> <password> <openai_api_base_url> <openai_api_key> <openai_api_stt_key> <openai_ig_api_base_url> <openai_ig_api_key>"
    exit 1
fi

if [ -z "$3" ]; then
    echo "Error: password is not specified."
    echo "Usage: $0 <domain_name> <email> <password> <openai_api_base_url> <openai_api_key> <openai_api_stt_key> <openai_ig_api_base_url> <openai_ig_api_key>"
    exit 1
fi

if [ -z "$4" ]; then
    echo "Error: openai_api_base_url is not specified."
    echo "Usage: $0 <domain_name> <email> <password> <openai_api_base_url> <openai_api_key> <openai_api_stt_key> <openai_ig_api_base_url> <openai_ig_api_key>"
    exit 1
fi

if [ -z "$5" ]; then
    echo "Error: openai_api_key is not specified."
    echo "Usage: $0 <domain_name> <email> <password> <openai_api_base_url> <openai_api_key> <openai_api_stt_key> <openai_ig_api_base_url> <openai_ig_api_key>"
    exit 1
fi

if [ -z "$6" ]; then
    echo "Error: openai_api_stt_key is not specified."
    echo "Usage: $0 <domain_name> <email> <password> <openai_api_base_url> <openai_api_key> <openai_api_stt_key> <openai_ig_api_base_url> <openai_ig_api_key>"
    exit 1
fi

if [ -z "$7" ]; then
    echo "Error: openai_ig_api_base_url is not specified."
    echo "Usage: $0 <domain_name> <email> <password> <openai_api_base_url> <openai_api_key> <openai_api_stt_key> <openai_ig_api_base_url> <openai_ig_api_key>"
    exit 1
fi

if [ -z "$8" ]; then
    echo "Error: openai_ig_api_key is not specified."
    echo "Usage: $0 <domain_name> <email> <password> <openai_api_base_url> <openai_api_key> <openai_api_stt_key> <openai_ig_api_base_url> <openai_ig_api_key>"
    exit 1
fi

DOMAIN=$1
EMAIL=$2
PASSWORD=$3
OPENAI_API_BASE_URL=$4
OPENAI_API_KEY=$5
OPENAI_API_STT_KEY=$6
OPENAI_IG_API_BASE_URL=$7
OPENAI_IG_API_KEY=$8

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
    http2 on;

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

# DISABLE SSH PASSWORD LOGIN
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?ChallengeResponseAuthentication .*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
systemctl restart ssh

# CONFIGURE OPEN WEB UI
apt install -y docker.io
systemctl start docker
systemctl enable docker

docker run -d -p 3000:8080 --add-host=host.docker.internal:host-gateway \
  -e WEBUI_URL="https://$DOMAIN" \
  -e WEBUI_ADMIN_EMAIL="$EMAIL" \
  -e WEBUI_ADMIN_PASSWORD="$PASSWORD" \
  -e WEBUI_ADMIN_NAME="Daniil Bastrich" \
  -e DEFAULT_LOCALE=ru \
  -e ENABLE_OLLAMA_API=False \
  -e ENABLE_DIRECT_CONNECTIONS=False \
  -e ENABLE_OPENAI_API=True \
  -e OPENAI_API_BASE_URL="$OPENAI_API_BASE_URL" \
  -e OPENAI_API_KEY="$OPENAI_API_KEY" \
  -e ENABLE_BASE_MODELS_CACHE=True \
  -e MODELS_CACHE_TTL=18000 \
  -e DEFAULT_MODELS="openai/gpt-5.2-pro" \
  -e DEFAULT_PINNED_MODELS="openai/gpt-5.2-pro,google/gemini-3.1-pro-preview,anthropic/claude-opus-4.6" \
  -e AUDIO_STT_ENGINE="openai" \
  -e AUDIO_STT_MODEL="gpt-4o-transcribe" \
  -e AUDIO_STT_OPENAI_API_BASE_URL="https://api.openai.com/v1" \
  -e AUDIO_STT_OPENAI_API_KEY="$OPENAI_API_STT_KEY" \
  -e IMAGES_OPENAI_API_BASE_URL="$OPENAI_IG_API_BASE_URL" \
  -e IMAGES_OPENAI_API_KEY="$OPENAI_IG_API_KEY" \
  -e ENABLE_IMAGE_GENERATION=True \
  -e ENABLE_IMAGE_PROMPT_GENERATION=True \
  -e IMAGE_GENERATION_ENGINE=openai \
  -e IMAGE_GENERATION_MODEL="google/nano-banana-2" \
  -e IMAGE_SIZE=auto \
  -e IMAGE_AUTO_SIZE_MODELS_REGEX_PATTERN=".*" \
  -e IMAGES_EDIT_OPENAI_API_BASE_URL="$OPENAI_IG_API_BASE_URL" \
  -e IMAGES_EDIT_OPENAI_API_KEY="$OPENAI_IG_API_KEY" \
  -e ENABLE_IMAGE_EDIT=True \
  -e IMAGE_EDIT_ENGINE=openai \
  -e IMAGE_EDIT_MODEL="google/nano-banana-2" \
  -e IMAGES_GEMINI_ENDPOINT_METHOD="generateContent" \
  -v open-webui:/app/backend/data --name open-webui --restart always ghcr.io/open-webui/open-webui:main