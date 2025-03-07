#!/bin/bash

cd /root/
TEMP_DIR=$(mktemp -d)

FILES=(
    "/etc/hysteria/ca.key"
    "/etc/hysteria/ca.crt"
    "/etc/hysteria/users.json"
    "/etc/hysteria/config.json"
    "/etc/hysteria/.configs.env"
    "/etc/hysteria/core/scripts/telegrambot/.env"
    "/etc/hysteria/core/scripts/singbox/.env"
    "/etc/hysteria/core/scripts/normalsub/.env"
    "/etc/hysteria/core/scripts/webpanel/.env"
)

echo "Backing up and stopping all cron jobs"
crontab -l > /tmp/crontab_backup
crontab -r

echo "Backing up files to $TEMP_DIR"
for FILE in "${FILES[@]}"; do
    mkdir -p "$TEMP_DIR/$(dirname "$FILE")"
    cp "$FILE" "$TEMP_DIR/$FILE"
done

echo "Checking and renaming old systemd service files"
declare -A SERVICE_MAP=(
    ["/etc/systemd/system/hysteria-bot.service"]="hysteria-telegram-bot.service"
    ["/etc/systemd/system/singbox.service"]="hysteria-singbox.service"
    ["/etc/systemd/system/normalsub.service"]="hysteria-normal-sub.service"
)

for OLD_SERVICE in "${!SERVICE_MAP[@]}"; do
    NEW_SERVICE="/etc/systemd/system/${SERVICE_MAP[$OLD_SERVICE]}"
    
    if [[ -f "$OLD_SERVICE" ]]; then
        echo "Stopping old service: $(basename "$OLD_SERVICE")"
        systemctl stop "$(basename "$OLD_SERVICE")" 2>/dev/null
        
        echo "Renaming $OLD_SERVICE to $NEW_SERVICE"
        mv "$OLD_SERVICE" "$NEW_SERVICE"
        
        echo "Reloading systemd daemon"
        systemctl daemon-reload
    fi
done

echo "Removing /etc/hysteria directory"
rm -rf /etc/hysteria/

echo "Cloning Hysteria2 repository"
git clone https://github.com/ReturnFI/Hysteria2 /etc/hysteria

echo "Downloading geosite.dat and geoip.dat"
wget -O /etc/hysteria/geosite.dat https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geosite.dat >/dev/null 2>&1
wget -O /etc/hysteria/geoip.dat https://raw.githubusercontent.com/Chocolate4U/Iran-v2ray-rules/release/geoip.dat >/dev/null 2>&1

echo "Restoring backup files"
for FILE in "${FILES[@]}"; do
    cp "$TEMP_DIR/$FILE" "$FILE"
done

CONFIG_ENV="/etc/hysteria/.configs.env"
if [ ! -f "$CONFIG_ENV" ]; then
    echo ".configs.env not found, creating it with default values."
    echo "SNI=bts.com" > "$CONFIG_ENV"
fi

export $(grep -v '^#' "$CONFIG_ENV" | xargs 2>/dev/null)

if [[ -z "$IP4" ]]; then
    echo "IP4 not found, fetching from ip.gs..."
    IP4=$(curl -s -4 ip.gs || echo "")
    echo "IP4=${IP4:-}" >> "$CONFIG_ENV"
fi

if [[ -z "$IP6" ]]; then
    echo "IP6 not found, fetching from ip.gs..."
    IP6=$(curl -s -6 ip.gs || echo "")
    echo "IP6=${IP6:-}" >> "$CONFIG_ENV"
fi

echo "Setting ownership and permissions"
chown hysteria:hysteria /etc/hysteria/ca.key /etc/hysteria/ca.crt
chmod 640 /etc/hysteria/ca.key /etc/hysteria/ca.crt
chown -R hysteria:hysteria /etc/hysteria/core/scripts/singbox
chown -R hysteria:hysteria /etc/hysteria/core/scripts/telegrambot

echo "Setting execute permissions for user.sh and kick.sh"
chmod +x /etc/hysteria/core/scripts/hysteria2/user.sh
chmod +x /etc/hysteria/core/scripts/hysteria2/kick.sh

cd /etc/hysteria
python3 -m venv hysteria2_venv
source /etc/hysteria/hysteria2_venv/bin/activate
pip install -r requirements.txt

echo "Restarting hysteria services"
systemctl restart hysteria-server.service
systemctl restart hysteria-telegram-bot.service
systemctl restart hysteria-singbox.service
systemctl restart hysteria-normal-sub.service
systemctl restart hysteria-webpanel.service

echo "Checking hysteria-server.service status"
if systemctl is-active --quiet hysteria-server.service; then
    echo "Upgrade completed successfully"
else
    echo "Upgrade failed: hysteria-server.service is not active"
fi

echo "Restoring cron jobs"
crontab /tmp/crontab_backup
rm /tmp/crontab_backup

chmod +x menu.sh
./menu.sh
