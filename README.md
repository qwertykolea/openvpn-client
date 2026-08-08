# OpenVPN Client Container

[![Build and Push OpenVPN Container](https://github.com/qwertykolea/openvpn-client/actions/workflows/docker-build.yml/badge.svg)](https://github.com/qwertykolea/openvpn-client/actions/workflows/docker-build.yml)
[![Docker Image Version](https://img.shields.io/docker/v/qwertykolea/openvpn-client?sort=date&label=latest)](https://github.com/qwertykolea/openvpn-client/pkgs/container/openvpn-client)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A lightweight, multi‑architecture OpenVPN client container built on Alpine Linux, designed specifically for **MikroTik RouterOS** container support and other resource‑constrained environments.

> **Why this exists:** MikroTik's built‑in OpenVPN client has limitations (e.g., limited cipher support, no `auth-user-pass` file support, no custom DNS). This container runs a full OpenVPN client inside a container on your MikroTik, giving you the full OpenVPN feature set.

---

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Deploying on MikroTik RouterOS](#deploying-on-mikrotik-routeros)
- [Environment Variables (Complete Reference)](#environment-variables-complete-reference)
- [Mount Points & Files](#mount-points--files)
- [Custom Post‑Up Script](#custom-post-up-script)
- [Healthcheck Watchdog – Internals](#healthcheck-watchdog--internals)
- [Entrypoint Script Logic (Step‑by‑Step)](#entrypoint-script-logic-step-by-step)
- [Building from Source – Compilation Details](#building-from-source--compilation-details)
- [CI/CD Pipeline (GitHub Actions)](#cicd-pipeline-github-actions)
- [Version Information](#version-information)
- [Troubleshooting](#troubleshooting)
- [License](#license)
- [Contributing](#contributing)
- [Links](#links)

---

## Features

- **Multi‑architecture** – Supports `linux/amd64`, `linux/arm64`, `linux/arm/v7`, `linux/arm/v6` – works on MikroTik ARM, ARM64, and x86 devices.
- **Automatic updates** – Weekly GitHub Actions workflow checks for new Alpine and OpenVPN releases.
- **Flexible authentication** – Use environment variables (`OVPN_USER`/`OVPN_PASS`) **or** an `auth.txt` file (path configurable via `OVPN_AUTH_FILE`).
- **DNS control** – Set custom DNS servers via `OVPN_DNS_SERVERS` (space, comma, or semicolon separated). Container overwrites `/etc/resolv.conf` and DNATs DNS requests to the first DNS server.
- **Healthcheck watchdog** – Pings a host through `tun0` and reboots the container on consecutive failures.
- **NAT & routing** – Applies iptables MASQUERADE, MSS clamping, and forwarding.
- **Custom post‑up script** – Execute `/vpn/post-up.sh` after the tunnel is up.
- **Small footprint** – Built with OpenVPN's `--enable-small` and minimal runtime dependencies.
- **Config auto‑detection** – Picks the first `.ovpn` file in `/vpn` if `OVPN_CONFIG_NAME` is not set.

---

## Quick Start

### Run with Docker

```bash
docker run -d \
  --name openvpn-client \
  --cap-add NET_ADMIN \
  --device /dev/net/tun \
  -v /path/to/your/config.ovpn:/vpn/config.ovpn \
  -e OVPN_USER=your_username \
  -e OVPN_PASS=your_password \
  -e OVPN_DNS_SERVERS="8.8.8.8 1.1.1.1" \
  ghcr.io/qwertykolea/openvpn-client:latest
```

### Run with docker-compose

```bash
services:
  openvpn-client:
    image: ghcr.io/qwertykolea/openvpn-client:latest
    container_name: openvpn-client
    privileged: true
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
    volumes:
      - ./config.ovpn:/vpn/config.ovpn
      - ./auth.txt:/vpn/auth.txt # or environment OVPN_USER/OVPN_PASS
    environment:
      - OVPN_USER=username # or auth.txt
      - OVPN_PASS=password
      - OVPN_DNS_SERVERS=8.8.8.8 1.1.1.1
      - HEALTHCHECK_HOST=1.1.1.1
    restart: unless-stopped
```

## Deploying on MikroTik RouterOS

This is the primary use case. The container runs as a VPN gateway – other devices on your network can route traffic through it.

### 1. Create a bridge and VETH interface

```routeros
/interface bridge
add name=bridge-container-openvpn-1

/interface veth
add address=192.168.40.10/24 dhcp=no gateway=192.168.40.1 name=veth-container-ovpn-1
```
### 2. Create the container

```routeros
/container
add envlists=ENV_OpenVPN hostname=OpenVPN-1 interface=veth-container-ovpn-1 \
    mountlists=MOUNT_OpenVPN name=OpenVPN-1 privileged=yes \
    remote-image=ghcr.io/qwertykolea/openvpn-client:latest \
    restart-policy=always root-dir=/openvpn-client:latest
```
### 3. Create a routing table for VPN traffic
```routeros
/routing table
add disabled=no fib name=OpenVPN-1-route-table
```
### 4. Set up environment variables

```routeros
/container envs
add key=HEALTHCHECK_HOST list=ENV_OpenVPN value=1.1.1.1
add key=HEALTHCHECK_INTERVAL list=ENV_OpenVPN value=5
add key=HEALTHCHECK_MAX_FAILS list=ENV_OpenVPN value=2
add key=OVPN_CONFIG_NAME list=ENV_OpenVPN value=""
add key=OVPN_DNS_SERVERS list=ENV_OpenVPN value="8.8.4.4 8.8.8.8;1.1.1.1,1.0.0.1"
add key=OVPN_EXTRA_ARGS list=ENV_OpenVPN value=""
add key=OVPN_LOG_LEVEL list=ENV_OpenVPN value=3
add key=OVPN_PASS list=ENV_OpenVPN value="your_password"
add key=OVPN_USER list=ENV_OpenVPN value="your_username"
# Optional: override auth file path
add key=OVPN_AUTH_FILE list=ENV_OpenVPN value="/vpn/custom_auth.txt" comment="Optional: override auth file path"
```

### 5. Mount the OpenVPN config directory

Place your `.ovpn` config file(s) on a USB drive or persistent storage.

```routeros
/container mountAs
add dst=/vpn list=MOUNT_OpenVPN src=/usb1/OpenVPN_config
```
### 6. Add the VETH to the bridge
```routeros
/interface bridge port
add bridge=bridge-container-openvpn-1 interface=veth-container-ovpn-1
```

### 7. Add the bridge to your LAN interface list

```routeros
/interface list member
add interface=bridge-container-openvpn-1 list=LAN
```
### 8. Set up the bridge IP address

```routeros
/ip address
add address=192.168.40.1/24 interface=bridge-container-openvpn-1 network=192.168.40.0
```
### 9. Create an address list for traffic to route through VPN

```routeros
/ip firewall address-list
add address=17.241.31.0/24 list=To_OpenVPN-1
add address=8.8.8.0/24 list=To_OpenVPN-1
```
### 10. Mark routing for traffic destined to the VPN

```routeros
/ip firewall mangle
add action=mark-routing chain=prerouting dst-address-list=To_OpenVPN-1 \
    in-interface-list=LAN new-routing-mark=OpenVPN-1-route-table passthrough=no
```
### 11. Add the VPN route

```routeros
/ip route
add disabled=no distance=1 dst-address=0.0.0.0/0 gateway=192.168.40.10 \
    routing-table=OpenVPN-1-route-table scope=30 target-scope=10
```

>**Note:** The gateway (`192.168.40.10`) is the VETH IP address assigned to the container.

## Environment Variables (Complete Reference)

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `OVPN_USER` | OpenVPN username. If set together with `OVPN_PASS`, they override any auth file. | (none) | `user` |
| `OVPN_PASS` | OpenVPN password. Must be set together with `OVPN_USER`. | (none) | `User1234` |
| `OVPN_CONFIG_NAME` | Filename of the `.ovpn` config. If not set, the first `.ovpn` in `/vpn` (alphabetical) is used. |(auto‑detect) | `myconf.ovpn` |
| `OVPN_AUTH_FILE` | Path to a two‑line auth file (username + password). Used **only if** `OVPN_USER`/`OVPN_PASS` are not both set. | `/vpn/auth.txt` | `/vpn/user-auth.txt` |
| `OVPN_LOG_LEVEL` | OpenVPN verbosity (0–11). Also accepts `VPN_LOG_LEVEL` as fallback (if `OVPN_LOG_LEVEL` is empty). | `3` | `7` |
| `OVPN_DNS_SERVERS` | Space, comma, or semicolon‑separated list of DNS servers. The first one is used for DNAT. | (none) | `8.8.4.4,8.8.8.8 1.1.1.1;1.0.0.1` |
| `OVPN_EXTRA_ARGS` | Any additional arguments passed directly to the `openvpn` command. | (none) | `--route 10.0.0.0 255.0.0.0`|
| `HEALTHCHECK_HOST` | Host to ping via `tun0` for health monitoring. If empty, the watchdog is not started. | (none) | `17.241.31.24` |
| `HEALTHCHECK_INTERVAL` | How often (in seconds) to ping the host. | `30` | `10` |
| `HEALTHCHECK_MAX_FAILS` | Number of consecutive failed pings before the container reboots. | `3` | `2` |

>**Note:** All variable values are trimmed of leading/trailing quotes and whitespace via `clean_var()` function.

### DNS Configuration Details

- The container splits `OVPN_DNS_SERVERS` on `,`, `;`, and spaces.
- It writes all DNS servers to `/etc/resolv.conf`.
- It adds iptables DNAT rules for UDP and TCP port 53, redirecting all DNS queries to the **first** DNS server in the list.

## Mount Points & Files

| Mount point | Purpose |
|-------------|---------|
| `/vpn` | Directory containing `.ovpn` config files, optional `auth.txt`, and optional `post-up.sh`. |

### Supported files inside `/vpn`

- **`*.ovpn`** – OpenVPN configuration file(s). The container selects one according to the rules below.
- **`auth.txt`** (or custom path via `OVPN_AUTH_FILE`) – Two‑line file with username and password. Used only if env vars are not provided.
- **`post-up.sh`** – Custom script executed after the tunnel is up (see below).

### Config file selection logic

1. If `OVPN_CONFIG_NAME` is set, the container checks:
   - the current working directory (inside container)
   - `/vpn/`  
   If found, it uses that file; otherwise, it exits with an error.
2. If not set, it lists all `.ovpn` files in `/vpn`, sorts them alphabetically, and uses the first one. If no `.ovpn` files exist, it exits.

### Authentication precedence

1. **Environment variables** (`OVPN_USER` **and** `OVPN_PASS` both set) – highest priority.  
   The container creates a temporary file `/tmp/auth_env.txt` with the two lines and inserts `auth-user-pass /tmp/auth_env.txt` into the config.
2. **Auth file** – either the default `/vpn/auth.txt` or a custom path specified by `OVPN_AUTH_FILE`.  
   The container inserts `auth-user-pass <path>` into the config.
3. If **no** credentials are provided, any existing `auth-user-pass` line in the config is commented out (so the VPN may ask interactively, which will fail).

The config is copied to `/tmp/config.ovpn` and modified with `sed` to either add or override the `auth-user-pass` directive.

## Custom Post‑Up Script

Place an executable script `post-up.sh` in `/vpn/`. It is executed **after** the tunnel is established, after the default iptables rules have been applied. Failures are ignored (`|| true`).

Example `/vpn/post-up.sh`:

```bash
#!/bin/sh
# Add custom routes
ip route add 10.0.0.0/8 via $(ip route show dev tun0 | grep -oP 'via \K[0-9.]+')
echo "Custom post-up script executed!"
























