#!/bin/sh

set -eu

# Helper: trim quotes and leading/trailing whitespace from variable values
clean_var() {
    printf '%s' "$1" | sed 's/^[ '\''"]*//;s/[ '\''"]*$//'
}

# 1. Clean and initialize main variables
OVPN_USER=$(clean_var "${OVPN_USER:-}")
OVPN_PASS=$(clean_var "${OVPN_PASS:-}")
OVPN_CONFIG=$(clean_var "${OVPN_CONFIG:-}")
OVPN_AUTH_FILE=$(clean_var "${OVPN_AUTH_FILE:-}")
OVPN_LOG_LEVEL=$(clean_var "${OVPN_LOG_LEVEL:-${VPN_LOG_LEVEL:-3}}")
HEALTHCHECK_HOST=$(clean_var "${HEALTHCHECK_HOST:-}")
HEALTHCHECK_INTERVAL=$(clean_var "${HEALTHCHECK_INTERVAL:-30}")
HEALTHCHECK_MAX_FAILS=$(clean_var "${HEALTHCHECK_MAX_FAILS:-3}")
OVPN_DNS_SERVER=$(clean_var "${OVPN_DNS_SERVER:-}")
OVPN_EXTRA_ARGS=$(clean_var "${OVPN_EXTRA_ARGS:-}")

VERB="${OVPN_LOG_LEVEL}"

# 2. Select configuration file (.ovpn)
if [ -n "$OVPN_CONFIG" ]; then
    if [ -f "$OVPN_CONFIG" ]; then
        CONFIG="$OVPN_CONFIG"
    elif [ -f "/vpn/$OVPN_CONFIG" ]; then
        CONFIG="/vpn/$OVPN_CONFIG"
    else
        echo "ERROR: Specified config '$OVPN_CONFIG' not found!"
        exit 1
    fi
else
    # If not specified, pick the first .ovpn file in /vpn (alphabetical order)
    CONFIG=$(ls -1 /vpn/*.ovpn 2>/dev/null | sort | head -n 1 || true)
    if [ -z "$CONFIG" ]; then
        echo "ERROR: No .ovpn config files found in /vpn!"
        exit 1
    fi
fi

echo "Selected config: $CONFIG"

# Create temporary config copy to allow modifications
TMP_CONFIG="/tmp/config.ovpn"
cp "$CONFIG" "$TMP_CONFIG"

# 3. Authentication: environment variables take priority over auth file
AUTH_FILE=""
if [ -n "$OVPN_USER" ] && [ -n "$OVPN_PASS" ]; then
    AUTH_FILE="/tmp/auth_env.txt"
    printf "%s\n%s\n" "$OVPN_USER" "$OVPN_PASS" > "$AUTH_FILE"
    chmod 600 "$AUTH_FILE"
    echo "Using credentials from environment variables (OVPN_USER / OVPN_PASS)."
else
    DEFAULT_AUTH_FILE="${OVPN_AUTH_FILE:-/vpn/auth.txt}"
    if [ -f "$DEFAULT_AUTH_FILE" ]; then
        AUTH_FILE="$DEFAULT_AUTH_FILE"
        echo "Using credentials from file: $AUTH_FILE"
    fi
fi

# Insert or override 'auth-user-pass' directive in config
if [ -n "$AUTH_FILE" ]; then
    if grep -Eq '^[[:space:]]*auth-user-pass([[:space:]]+.*)?$' "$TMP_CONFIG"; then
        sed -i -E "s|^[[:space:]]*auth-user-pass.*|auth-user-pass $AUTH_FILE|" "$TMP_CONFIG"
    else
        echo "auth-user-pass $AUTH_FILE" >> "$TMP_CONFIG"
    fi
else
    # If no credentials provided, comment out any existing auth-user-pass line
    sed -i -E 's/^[[:space:]]*(auth-user-pass.*)/# \1/' "$TMP_CONFIG"
fi

# 4. Ensure TUN device exists (required for VPN tunnel)
if [ ! -c /dev/net/tun ]; then
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200
    chmod 600 /dev/net/tun
fi

# 5. Background healthcheck watchdog: pings a host via tun0 to detect tunnel failure
start_watchdog() {
    if [ -n "$HEALTHCHECK_HOST" ]; then
        (
            INTERVAL="${HEALTHCHECK_INTERVAL}"
            MAX_FAILS="${HEALTHCHECK_MAX_FAILS}"
            FAILS=0

            echo "Watchdog started: pinging $HEALTHCHECK_HOST every ${INTERVAL}s (max fails: $MAX_FAILS)"
            
            # Wait a bit for tunnel to establish before first check
            sleep 15

            while true; do
                sleep "$INTERVAL"
                if ping -I tun0 -c 1 -W 3 "$HEALTHCHECK_HOST" >/dev/null 2>&1; then
                    FAILS=0
                else
                    FAILS=$((FAILS + 1))
                    echo "WARNING: Healthcheck failed ($FAILS/$MAX_FAILS) for host $HEALTHCHECK_HOST"
                    if [ "$FAILS" -ge "$MAX_FAILS" ]; then
                        echo "CRITICAL: VPN tunnel dead. Killing container for restart..."
                        pkill -9 openvpn || true
                        exit 1
                    fi
                fi
            done
        ) &
    fi
}

# 6. Generate up script (executed after tunnel is up) to set iptables NAT and routing
cat > /tmp/up.sh << 'EOF'
#!/bin/sh
iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
iptables -P FORWARD ACCEPT
iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
echo "iptables NAT & MSS rules applied for tun0."
EOF

# If DNS servers(OVPN_DNS_SERVER variable) are provided, add them to resolv.conf and DNAT rules
if [ -n "$OVPN_DNS_SERVER" ]; then
    CLEAN_DNS_LIST=$(echo "$OVPN_DNS_SERVER" | tr ',;' ' ')
    PRIMARY_DNS=""
    DNS_ENTRIES=""

    for dns in $CLEAN_DNS_LIST; do
        dns_clean=$(printf '%s' "$dns" | tr -d ' "' "'")
        if [ -n "$dns_clean" ]; then
            if [ -z "$PRIMARY_DNS" ]; then
                PRIMARY_DNS="$dns_clean"
            fi
            DNS_ENTRIES="${DNS_ENTRIES}nameserver ${dns_clean}\n"
        fi
    done

    if [ -n "$PRIMARY_DNS" ]; then
        cat >> /tmp/up.sh << EOF
printf "${DNS_ENTRIES}" > /etc/resolv.conf
iptables -t nat -A PREROUTING -p udp --dport 53 -j DNAT --to-destination ${PRIMARY_DNS}:53
iptables -t nat -A PREROUTING -p tcp --dport 53 -j DNAT --to-destination ${PRIMARY_DNS}:53
echo "DNS redirected to ${PRIMARY_DNS} via iptables DNAT."
EOF
    fi
fi

# Allow custom user-defined post-up script
cat >> /tmp/up.sh << 'EOF'
if [ -f /vpn/post-up.sh ]; then
    echo "Executing custom script /vpn/post-up.sh..."
    sh /vpn/post-up.sh || true
fi
EOF

chmod +x /tmp/up.sh

# Start watchdog in background
start_watchdog

echo "Starting OpenVPN..."
echo "Config : $CONFIG"
echo "Verb   : $VERB"

# Launch OpenVPN with the generated config and up script
exec openvpn \
    --config "$TMP_CONFIG" \
    --verb "$VERB" \
    --suppress-timestamps \
    --script-security 2 \
    --up /tmp/up.sh \
    --up-restart \
    $OVPN_EXTRA_ARGS
