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
      - ./auth.txt:/vpn/auth.txt
    environment:
      - OVPN_USER=username
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




