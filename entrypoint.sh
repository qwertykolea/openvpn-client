#!/bin/sh

set -eu

CONFIG="${OVPN_CONFIG:-/vpn/config.ovpn}"
AUTH_FILE="${OVPN_AUTH_FILE:-/vpn/auth.txt}"
VERB="${OVPN_LOG_LEVEL:-3}"

if [ ! -f "$CONFIG" ]; then
    echo "ERROR: $CONFIG not found."
    exit 1
fi

TMP_CONFIG="/tmp/config.ovpn"
cp "$CONFIG" "$TMP_CONFIG"

if grep -Eq '^[[:space:]]*auth-user-pass[[:space:]]*$' "$TMP_CONFIG"; then
    if [ -f "$AUTH_FILE" ]; then
        sed -i "s|^auth-user-pass$|auth-user-pass $AUTH_FILE|" "$TMP_CONFIG"
        echo "Using auth file: $AUTH_FILE"
    else
        echo "WARNING: auth-user-pass found but $AUTH_FILE is missing."
    fi
fi

# Создаём up-скрипт, который применит iptables после поднятия tun0
cat > /tmp/up.sh << 'EOF'
#!/bin/sh
iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
iptables -P FORWARD ACCEPT
echo "iptables rules for tun0 applied."
EOF
chmod +x /tmp/up.sh

echo "Starting OpenVPN..."
echo "Config : $CONFIG"
echo "Verb   : $VERB"

exec openvpn \
    --config "$TMP_CONFIG" \
    --verb "$VERB" \
    --suppress-timestamps \
    --up /tmp/up.sh
