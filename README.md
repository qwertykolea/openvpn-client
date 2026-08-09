# OpenVPN Client Container

[![Build and Push OpenVPN Container](https://github.com/qwertykolea/openvpn-client/actions/workflows/docker-build.yml/badge.svg)](https://github.com/qwertykolea/openvpn-client/actions/workflows/docker-build.yml)
[![Docker Image Version](https://img.shields.io/docker/v/qwertykolea/openvpn-client?sort=date&label=latest)](https://github.com/qwertykolea/openvpn-client/pkgs/container/openvpn-client)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A lightweight, multi‑architecture OpenVPN client container built on Alpine Linux, designed specifically for **MikroTik RouterOS** container support and other resource‑constrained environments.

> [!NOTE]
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
> [!IMPORTANT]
> Container must be privileged: `privileged=yes`
### 3. Create a routing table for VPN traffic
```routeros
/routing table
add disabled=no fib name=OpenVPN-1-route-table
```
### 4. Set up environment variables

```routeros
/container envs
add key=HEALTHCHECK_HOST list=ENV_OpenVPN value=17.241.31.254
add key=HEALTHCHECK_INTERVAL list=ENV_OpenVPN value=5
add key=HEALTHCHECK_MAX_FAILS list=ENV_OpenVPN value=2
add key=OVPN_CONFIG_NAME list=ENV_OpenVPN value=""
add key=OVPN_DNS_SERVERS list=ENV_OpenVPN value="8.8.4.4 8.8.8.8;1.1.1.1,1.0.0.1"
add key=OVPN_EXTRA_ARGS list=ENV_OpenVPN value=""
add key=OVPN_LOG_LEVEL list=ENV_OpenVPN value=3
add key=OVPN_PASS list=ENV_OpenVPN value="your_password"
add key=OVPN_USER list=ENV_OpenVPN value="your_username"
add key=OVPN_AUTH_FILE list=ENV_OpenVPN value="/vpn/custom_auth.txt" comment="Optional: override auth file path"
```

### 5. Mount the OpenVPN config directory

Place your `.ovpn` config file(s) on a USB drive or persistent storage.

```routeros
/container mountAs
add dst=/vpn list=MOUNT_OpenVPN src=/usb1/OpenVPN_config
```
> [!NOTE]
> Change `usb1`to your disk
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
> [!IMPORTANT]
> The gateway ( ` 192.168.40.10 ` ) is the VETH IP address assigned to the container.
> 
> It is imposible to use container interface ( ` veth-container-ovpn-1 ` ) or bridge ( ` bridge-container-openvpn-1 ` ) as gateway with OpenVPN.

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
> [!NOTE]
> All variable values are trimmed of leading/trailing quotes and whitespace via `clean_var()` function.

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
```
## Healthcheck Watchdog – Internals

The watchdog is a background subshell started by the entrypoint script.

- It waits **15 seconds** before the first ping to give the tunnel time to come up.
- Then it pings `HEALTHCHECK_HOST` using `ping -I tun0 -c 1 -W 3` every `HEALTHCHECK_INTERVAL` seconds.
- If the ping succeeds, the failure counter is reset to 0.
- If it fails, the counter increments. When it reaches `HEALTHCHECK_MAX_FAILS`, the container calls `reboot` (which forces the container to exit, allowing the orchestrator to restart it).

This watchdog runs **in parallel** with OpenVPN; it does not block the main process.

## Entrypoint Script Logic (Step‑by‑Step)

The entrypoint (`/entrypoint.sh`) performs the following actions in order:

1. **Clean and initialize variables** – Strips quotes and whitespace from all environment variables using `clean_var()`.
2. **Select configuration file** – Determines the `.ovpn` file to use and copies it to `/tmp/config.ovpn`.
3. **Handle authentication** – Based on env vars or auth file, it inserts or comments out the `auth-user-pass` directive in the temporary config.
4. **Ensure TUN device exists** – Creates `/dev/net/tun` if it doesn't exist.
5. **Start healthcheck watchdog** – If `HEALTHCHECK_HOST` is set, the watchdog subshell is started in the background.
6. **Generate the up script** – Writes `/tmp/up.sh` with the following commands:
   - `iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE`
   - `iptables -P FORWARD ACCEPT`
   - `iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu`
   - If `OVPN_DNS_SERVERS` is set:
     - Writes the DNS list to `/etc/resolv.conf`
     - Adds DNAT rules: `iptables -t nat -A PREROUTING -p udp --dport 53 -j DNAT --to-destination ${PRIMARY_DNS}:53` (and same for TCP)
   - Executes `/vpn/post-up.sh` if present.
7. **Launch OpenVPN** with:
   - `--config /tmp/config.ovpn`
   - `--verb $VERB`
   - `--suppress-timestamps`
   - `--script-security 2`
   - `--up /tmp/up.sh`
   - `--up-restart`
   - plus any arguments from `OVPN_EXTRA_ARGS`

The container uses `exec` to run OpenVPN as PID 1, so signals are handled properly.

## Building from Source – Compilation Details

### Local Build

```bash
docker build \
  --build-arg ALPINE_VERSION=3.20 \
  --build-arg OPENVPN_VERSION=2.6.12 \
  -t openvpn-client .
```

### Inside the build ( `openvpn-compile.sh` )
 - Installs build dependencies ( `build‑base, libtool, curl, openssl‑dev, lzo‑dev, lz4‑dev, etc.` ).
 - Downloads the official OpenVPN tarball from GitHub (`https://github.com/OpenVPN/openvpn/releases/download/v${VERSION}/openvpn-${VERSION}.tar.gz`).
 - Configures with the following flags:
```text
--prefix=/usr
--sysconfdir=/etc
--disable-dco
--disable-pkcs11
--enable-small
--disable-plugins
--disable-systemd
--disable-selinux
--disable-management
--disable-fragment
--disable-port-share
```
- Injects a custom version string by patching config.h:
  - Extracts architecture ( `uname -m` ), OS ( `/etc/os-release `), and build date in `UTC`.
  - Replaces  `#define TARGET_ALIAS ` with a custom string:
- Compiles with  `make -j` (parallel).
- Installs only executables and libraries ( `make install-exec` ) – skips man pages and docs.
- Cleans up build dependencies to keep the final image small.


## CI/CD Pipeline (GitHub Actions)

The workflow (`.github/workflows/docker-build.yml`) does the following:

- **Trigger**:
  - Scheduled weekly (every Sunday at 00:00 UTC).
  - Manual (`workflow_dispatch`) with inputs: `alpine_version`, `openvpn_version`, and `force_build`.
- **Version detection**:
  - Reads the current versions from `current_versions` file in the repo.
  - Fetches the latest Alpine version from Docker Hub (filtering semantic tags `X.Y.Z`).
  - Fetches the latest OpenVPN version from GitHub API (using `GITHUB_TOKEN` to avoid rate limits).
  - If `force_build` is true, or if either version differs from `current_versions`, it triggers a build.
- **Build & Push**:
  - Uses `docker/setup-qemu-action` and `docker/setup-buildx-action` for multi‑arch.
  - Logs in to GHCR.
  - Builds for `linux/amd64`, `linux/arm64`, `linux/arm/v7`, `linux/arm/v6`.
  - Pushes with tags:
    - `latest`
    - `alpine-<alpine-version>-openvpn-<openvpn-version>`
    - `<openvpn-version>` (e.g., `2.6.12`)
  - Provenance attestation is disabled.
- **Update versions** (only for automatic/scheduled runs):
  - If the build succeeded, it overwrites `current_versions` with the new versions.
  - Commits and pushes the change to the repository (with `[skip ci]`).

---

## Version Information

The compiled OpenVPN binary shows a custom version string (e.g., `openvpn --version`):
`OpenVPN 2.6.12 linux-armv7l-alpine-linux-v3.20-musl built on 7 Aug 2026 14:56 UTC | https://github.com/qwertykolea/openvpn-client | [SSL (OpenSSL)] [LZO] [LZ4] [EPOLL] [MH/PKTINFO] [AEAD]`

This includes:
- Architecture
- OS and version
- Build date (UTC)
- Repository URL for traceability

---

## Troubleshooting

### Container exits immediately
| Description | Linux | ` routeros ` |
|-------------|---------|---------|
| Check logs | `docker logs openvpn-client` | `routeros`: `log print where message~"container" ` |
> [!NOTE]
> Don't forget to enable logging on ` routeros ` container.

Common causes:
- Missing `.ovpn` file in `/vpn/` or invalid `OVPN_CONFIG_NAME`.
- Missing credentials (both env vars and auth file absent).
- Missing `/dev/net/tun` – use `--device /dev/net/tun` 
- Missing `privileged: true` | on `routeros` : `privileged=yes`

### No network through VPN
| Docker | ` routeros ` |
|-------------|---------|
|Verify `tun0` exists: `docker exec openvpn-client ip addr show tun0` | ` container shell [find tag=ghcr.io/qwertykolea/openvpn-client:latest] cmd="ip addr show tun0" ` |
|Check routing: `docker exec openvpn-client ip route` | ` container shell [find tag=ghcr.io/qwertykolea/openvpn-client:latest] cmd="ip route" ` |
|Inspect iptables NAT rules: `docker exec openvpn-client iptables -t nat -L -n` | ` container shell [find tag=ghcr.io/qwertykolea/openvpn-client:latest] cmd="iptables -t nat -L -n" ` |


### Healthcheck keeps rebooting
| Description | Docker | ` routeros ` |
|-------------|-------------|---------|
|Ensure `HEALTHCHECK_HOST` is reachable via `tun0`| `docker exec openvpn-client ping -I tun0 1.1.1.1` | ` container shell [find tag=ghcr.io/qwertykolea/openvpn-client:latest] cmd="ping -I tun0 1.1.1.1" ` |
||Increase `HEALTHCHECK_INTERVAL` or `HEALTHCHECK_MAX_FAILS` if the host is slow to respond.||

### DNS not working
| Description | Docker | ` routeros ` |
|-------------|-------------|---------|
||||
||||
||||
- Verify `OVPN_DNS_SERVERS` is set and properly parsed.
- Check DNAT rules: `docker exec openvpn-client iptables -t nat -L PREROUTING -n` | ` container shell [find tag=ghcr.io/qwertykolea/openvpn-client:latest] cmd="iptables -t nat -L PREROUTING -n" `
- Check `/etc/resolv.conf` inside the container | ` container shell [find tag=ghcr.io/qwertykolea/openvpn-client:latest] cmd="cat /etc/resolv.conf" `

### Custom script not running

- Ensure `/vpn/post-up.sh` exists and is executable (`chmod +x`).
- Add `set -x` at the top of the script to debug; errors are ignored (`|| true`), but output goes to logs.

---

## License

MIT License – see the [LICENSE](https://github.com/qwertykolea/openvpn-client/blob/main/LICENSE) file.

---

## Contributing

Issues and PRs are welcome. Please keep compatibility with MikroTik and all target architectures. Update the README and relevant scripts when adding features.

---

## Links

- [GitHub Repository](https://github.com/qwertykolea/openvpn-client)
- [OpenVPN Official Site](https://openvpn.net/)
- [MikroTik Container Documentation](https://help.mikrotik.com/docs/display/ROS/Container)
- [GitHub Container Registry](https://ghcr.io/qwertykolea/openvpn-client)















