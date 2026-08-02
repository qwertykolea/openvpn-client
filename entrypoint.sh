#!/bin/bash
set -e

# Включаем IP Forwarding внутри контейнера
sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1 || true

# Включаем NAT для трафика, уходящего в туннель OpenVPN
iptables -t nat -A POSTROUTING -o tun+ -j MASQUERADE
iptables -A FORWARD -i tun+ -j ACCEPT
iptables -A FORWARD -o tun+ -j ACCEPT

# Если файл конфига передан — запускаем OpenVPN
if [ -f "/vpn/config.ovpn" ]; then
    echo "[+] Starting OpenVPN with /vpn/config.ovpn..."
    exec openvpn --config /vpn/config.ovpn --cd /vpn
else
    echo "[-] Error: /vpn/config.ovpn not found!"
    exit 1
fi
