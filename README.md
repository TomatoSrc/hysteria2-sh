# hysteria2-sh
---
# Hysteria 2 Installer (POSIX Shell)

A lightweight, dependency-free installation script for Hysteria 2. 
Written in pure POSIX sh, making it perfectly compatible with Alpine Linux (Ash), as well as standard Debian/Ubuntu/CentOS (Bash) systems.

## Features

- Lightweight: Pure Shell implementation, no redundant logic.
- Cross-Platform: 
  - Alpine Linux: Full support for OpenRC service management.
  - Debian/Ubuntu/CentOS: Full support for Systemd.
- Certificate Management:
  - Auto-generate Self-signed certificates (Recommended for testing).
  - ACME automated certificates (HTTP & Cloudflare DNS API support).
- Architecture Support: Auto-detects amd64 and arm64.

## Installation

You can run the script directly using curl or wget.

### Option 1: Curl (Recommended)

```bash
curl -s [https://raw.githubusercontent.com/TomatoSrc/hysteria2-sh/main/install.sh](https://raw.githubusercontent.com/TomatoSrc/hysteria2-sh/main/install.sh) | sh
```

### Option 2: Wget (For minimal Alpine installs)

```bash
wget -O install.sh [https://raw.githubusercontent.com/TomatoSrc/hysteria2-sh/main/install.sh](https://raw.githubusercontent.com/TomatoSrc/hysteria2-sh/main/install.sh) && chmod +x install.sh && sh install.sh
```

> Note: If you are having trouble connecting to GitHub, you can use the jsDelivr CDN:
> ```bash
> curl -s [https://cdn.jsdelivr.net/gh/TomatoSrc/hysteria2-sh@main/install.sh](https://cdn.jsdelivr.net/gh/TomatoSrc/hysteria2-sh@main/install.sh) | sh
> ```

## Usage

After installation, the script will automatically set up the service. You can re-run the script to manage the service.

### Service Commands

Systemd (Debian/Ubuntu/CentOS):
```bash
systemctl start hysteria    # Start
systemctl stop hysteria     # Stop
systemctl restart hysteria  # Restart
systemctl status hysteria   # Status
```

OpenRC (Alpine Linux):
```bash
rc-service hysteria start   # Start
rc-service hysteria stop    # Stop
rc-service hysteria restart # Restart
rc-service hysteria status  # Status
```

## File Locations

- Config File: /root/hy3/config.yaml
- Binary: /root/hy3/hysteria-linux-amd64 (or arm64)
- Certificates: /etc/ssl/private/

## Todo List

- [ ] Add Chinese translation

## Disclaimer

This script is for educational and testing purposes only. Use it at your own risk.
