#!/bin/sh

pidof openvpn >/dev/null || exit 1

ip addr show tun0 >/dev/null 2>&1 || exit 1

exit 0
