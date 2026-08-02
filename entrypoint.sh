#!/usr/bin/env bash

set -e

cleanup() {
    if [[ $openvpn_child ]]; then
        kill SIGTERM "$openvpn_child"
    fi
    sleep 0.5
    echo "info: exiting"
    exit 0
}

mkdir -p /data/{config,scripts}

echo " --- Running with the following variables --- "

if [[ $VPN_CONFIG_FILE ]]; then
    echo "VPN configuration file: $VPN_CONFIG_FILE"
fi

if [[ $VPN_CONFIG_PATTERN ]]; then
    echo "VPN configuration file name pattern: $VPN_CONFIG_PATTERN"
fi

echo "Using OpenVPN log level: $VPN_LOG_LEVEL"

if [[ $VPN_CONFIG_PATTERN ]]; then
    config_files=$(find vpn -name "$VPN_CONFIG_PATTERN" 2> /dev/null)
else
    config_files=$(find vpn -name '*.conf' -o -name '*.ovpn' 2> /dev/null)
fi

if [[ -z $config_files ]]; then
    >&2 echo 'Error: No openvpn configuration files found.'
    exit 1
fi

if [[ -f vpn/$IPTABLES_RULES ]]; then
    echo "Loading ipatables from vpn/$IPTABLES_RULES"
    iptables-restore vpn/$IPTABLES_RULES
else
    echo "No iptables rules file found."
fi

default_gateway=$(ip -4 route | grep 'default via' | awk '{print $3}')
echo "Default gateway is $default_gateway"

for CONFIG_FILE in $config_files
do
    echo "Starting OpenVpn using config file $CONFIG_FILE"
    openvpn_args=(
        "--config" "$CONFIG_FILE"
        "--auth-nocache"
        "--cd" "vpn"
        "--pull-filter" "ignore" "ifconfig-ipv6 "
        "--pull-filter" "ignore" "route-ipv6 "
        "--script-security" "2"
        "--up-restart"
        "--verb" "$VPN_LOG_LEVEL"
        )

    if [[ $VPN_AUTH_SECRET ]]; then
        openvpn_args+=("--auth-user-pass" "/run/secrets/$VPN_AUTH_SECRET")
    fi

    openvpn "${openvpn_args[@]}" &
    #openvpn_child+=$!
    #openvpn_child[${i}]=$!
done

wait < <(jobs -p)
