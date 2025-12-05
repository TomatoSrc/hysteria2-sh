#!/bin/sh
# Hysteria 2 Installer for Alpine/Debian/CentOS
# Compatible with OpenRC and Systemd

set +e

# --- Helpers ---

red() { printf "\033[31m%s\033[0m\n" "$1"; }
green() { printf "\033[32m%s\033[0m\n" "$1"; }
yellow() { printf "\033[33m%s\033[0m\n" "$1"; }

read_input() {
    printf "$1"
    if [ -t 0 ]; then
        read -r "$2"
    else
        read -r "$2" < /dev/tty
    fi
}

run_cmd() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        if command -v sudo >/dev/null 2>&1; then
            sudo "$@"
        else
            red "Error: Root privileges required."
            exit 1
        fi
    fi
}

get_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|armv8) echo "arm64" ;;
        *) echo "unsupported" ;;
    esac
}

check_sys() {
    if [ -f /etc/alpine-release ]; then
        release="alpine"
    elif [ -f /etc/redhat-release ]; then
        release="centos"
    elif grep -q "debian" /etc/issue 2>/dev/null; then
        release="debian"
    elif grep -q "ubuntu" /etc/issue 2>/dev/null; then
        release="ubuntu"
    else
        release="unknown"
    fi
}

# --- Core Functions ---

install_deps() {
    echo "Installing dependencies..."
    if [ "$release" = "alpine" ]; then
        run_cmd apk update
        run_cmd apk add --no-cache curl wget openssl iptables ip6tables jq grep coreutils bind-tools net-tools openrc
    elif [ "$release" = "debian" ] || [ "$release" = "ubuntu" ]; then
        run_cmd apt-get update
        run_cmd apt-get install -y wget curl openssl net-tools iptables iproute2 ca-certificates jq
    elif [ "$release" = "centos" ]; then
        run_cmd yum install -y epel-release
        run_cmd yum install -y wget curl openssl net-tools iptables iproute ca-certificates jq
    fi
}

check_status() {
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet hysteria; then echo "Running"; else echo "Stopped"; fi
    elif command -v rc-service >/dev/null 2>&1; then
        if rc-service hysteria status 2>&1 | grep -q "started"; then echo "Running"; else echo "Stopped"; fi
    else
        if pgrep -f "hysteria-linux" >/dev/null; then echo "Running"; else echo "Stopped"; fi
    fi
}

start_svc() {
    if command -v systemctl >/dev/null 2>&1; then run_cmd systemctl start hysteria
    elif command -v rc-service >/dev/null 2>&1; then run_cmd rc-service hysteria start
    fi
}

stop_svc() {
    if command -v systemctl >/dev/null 2>&1; then run_cmd systemctl stop hysteria
    elif command -v rc-service >/dev/null 2>&1; then run_cmd rc-service hysteria stop
    else killall hysteria-linux-$(get_arch) 2>/dev/null; fi
}

restart_svc() {
    stop_svc
    sleep 1
    start_svc
}

create_svc() {
    arch=$(get_arch)
    bin_path="/root/hy3/hysteria-linux-$arch"
    work_dir="/root/hy3"

    if command -v systemctl >/dev/null 2>&1; then
        cat > /etc/systemd/system/hysteria.service <<EOF
[Unit]
Description=Hysteria 2 Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$work_dir
ExecStart=$bin_path server
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
        run_cmd systemctl daemon-reload
        run_cmd systemctl enable hysteria
        run_cmd systemctl start hysteria

    elif command -v rc-service >/dev/null 2>&1; then
        cat > /etc/init.d/hysteria <<EOF
#!/sbin/openrc-run

name="hysteria"
description="Hysteria 2 Server"
command="$bin_path"
command_args="server"
command_background=true
pidfile="/run/hysteria.pid"
directory="$work_dir"

depend() {
    need net
    after firewall
}
EOF
        run_cmd chmod +x /etc/init.d/hysteria
        run_cmd rc-update add hysteria default
        run_cmd rc-service hysteria start
    else
        nohup $bin_path server > /root/hy3/hy.log 2>&1 &
    fi
}

install_hy2() {
    arch=$(get_arch)
    if [ "$arch" = "unsupported" ]; then red "Architecture not supported"; exit 1; fi

    check_status | grep -q "Running" && { red "Hysteria is already running."; return; }

    install_deps
    run_cmd mkdir -p /root/hy3
    cd /root/hy3 || exit

    echo "Fetching latest version..."
    latest_ver=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    [ -z "$latest_ver" ] && latest_ver="app/v2.6.0"

    dl_url="https://github.com/apernet/hysteria/releases/download/$latest_ver/hysteria-linux-$arch"
    run_cmd wget -O "hysteria-linux-$arch" "$dl_url"
    run_cmd chmod +x "hysteria-linux-$arch"

    # Config Generation
    read_input "Enter Password (Press Enter for random): " password
    if [ -z "$password" ]; then
        password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
        green "Password generated: $password"
    fi

    read_input "Enter Port (Default 443): " port
    [ -z "$port" ] && port=443

    read_input "Cert Mode [1]Self-signed [2]ACME: " cert_mode
    
    CONF="/root/hy3/config.yaml"
    cat > "$CONF" <<EOF
listen: :$port

auth:
  type: password
  password: $password

masquerade:
  type: proxy
  proxy:
    url: https://news.ycombinator.com/
    rewriteHost: true
EOF

    if [ "$cert_mode" = "2" ]; then
        read_input "Domain: " domain
        read_input "Email (Enter for random): " email
        if [ -z "$email" ]; then
            rand_str=$(head /dev/urandom | tr -dc a-z0-9 | head -c 8)
            email="${rand_str}@gmail.com"
            green "Using random email: $email"
        fi

        cat >> "$CONF" <<EOF

acme:
  domains:
    - $domain
  email: $email
EOF

        echo "Verification: [1]HTTP(80 port) [2]DNS(Cloudflare API)"
        read_input "Select [1/2]: " acme_type
        
        if [ "$acme_type" = "2" ]; then
             read_input "Cloudflare API Token: " cf_token
             cat >> "$CONF" <<EOF
  type: dns
  dns:
    name: cloudflare
    config:
      cloudflare_api_token: $cf_token
EOF
        fi
        link_sni="$domain"
        link_addr="$domain"
        proto_suffix="#Hy2-ACME"
        insecure=""
    else
        domain="bing.com"
        run_cmd mkdir -p /etc/ssl/private
        openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
            -keyout "/etc/ssl/private/$domain.key" \
            -out "/etc/ssl/private/$domain.crt" \
            -subj "/CN=$domain" -days 3650 >/dev/null 2>&1
        
        cat >> "$CONF" <<EOF

tls:
  cert: /etc/ssl/private/$domain.crt
  key: /etc/ssl/private/$domain.key
EOF
        link_addr=$(curl -s -4 ip.sb)
        link_sni="$domain"
        proto_suffix="#Hy2-Self"
        insecure="&insecure=1"
    fi
    
    create_svc
    
    green "Installation Complete!"
    echo "--------------------------"
    echo "hysteria2://$password@$link_addr:$port/?sni=$link_sni$insecure$proto_suffix"
    echo "--------------------------"
}

uninstall_hy2() {
    stop_svc
    if command -v systemctl >/dev/null 2>&1; then
        run_cmd systemctl disable hysteria
        run_cmd rm -f /etc/systemd/system/hysteria.service
    elif command -v rc-service >/dev/null 2>&1; then
        run_cmd rc-update del hysteria default
        run_cmd rm -f /etc/init.d/hysteria
    fi
    run_cmd rm -rf /root/hy3
    green "Uninstalled."
}

# --- Main ---

check_sys
arch=$(get_arch)

clear
echo "=================================="
echo " Hysteria 2 Installer (POSIX)"
echo " OS: $release | Arch: $arch"
echo " Status: $(check_status)"
echo "=================================="
echo " 1. Install"
echo " 2. Uninstall"
echo " 3. Restart"
echo " 4. View Config"
echo " 0. Exit"
echo "=================================="

read_input "Choice: " choice

case "$choice" in
    1) install_hy2 ;;
    2) uninstall_hy2 ;;
    3) restart_svc ;;
    4) [ -f /root/hy3/config.yaml ] && cat /root/hy3/config.yaml || red "No config found" ;;
    0) exit 0 ;;
    *) red "Invalid choice" ;;
esac
