# HKU VPN launcher — see https://github.com/rqhu1995/docker-vpn
#
# Usage:
#   hkuvpn        # use HKU_ENDPOINT from ~/.vpn/hku.env (default: hk)
#   hkuvpn cn     # force mainland China endpoint (faster from CN)
#   hkuvpn hk     # force Hong Kong endpoint
#
# When prompted for "Response:", enter your Microsoft Authenticator OTP.
# Press Ctrl+C to disconnect.

hkuvpn() {
    local endpoint_override="$1"

    # 1. Colima health check (works around stale 'colima status' after Mac sleep)
    if ! docker info >/dev/null 2>&1; then
        echo "Colima not ready, starting..."
        colima start --cpu 2 --memory 2 --disk 20 --vm-type vz --mount-type virtiofs || return 1
    fi

    # 2. Config file checks
    if [ ! -f "$HOME/.vpn/hku.env" ]; then
        echo "Missing config file: ~/.vpn/hku.env"
        echo "Copy from: ~/docker-vpn/examples/hku.env.example"
        return 1
    fi
    if [ ! -f "$HOME/.vpn/hku.pass" ]; then
        echo "Missing password file: ~/.vpn/hku.pass"
        echo "Create with: printf '%s' 'YOUR_PORTAL_PIN' > ~/.vpn/hku.pass && chmod 600 ~/.vpn/hku.pass"
        return 1
    fi

    # 3. Load user config
    # shellcheck disable=SC1091
    source "$HOME/.vpn/hku.env"

    # 4. Resolve endpoint (CLI arg > env file > default 'hk')
    local endpoint="${endpoint_override:-${HKU_ENDPOINT:-hk}}"
    local host
    case "$endpoint" in
        cn) host="121.37.195.197" ;;
        hk) host="vpn2fa.hku.hk" ;;
        *)  echo "Unknown endpoint: $endpoint (must be 'cn' or 'hk')"; return 1 ;;
    esac
    echo "Using endpoint: $endpoint ($host)"

    # 4b. Resolve proxy ports (env file > defaults)
    local socks_port="${HKU_SOCKS_PORT:-1080}"
    local http_port="${HKU_HTTP_PORT:-1088}"
    echo "Proxy ports: SOCKS5=$socks_port HTTP=$http_port"

    # 5. Auto-fetch pin-sha256 (cached per endpoint)
    local pin_cache="$HOME/.vpn/pin-$endpoint.cache"
    local servercert
    if [ -f "$pin_cache" ]; then
        servercert=$(cat "$pin_cache")
    else
        echo "First connection to $host, computing pin-sha256..."
        local pin
        pin=$(echo | openssl s_client -connect "$host:443" -servername "$host" 2>/dev/null \
              | openssl x509 -pubkey -noout \
              | openssl pkey -pubin -outform der 2>/dev/null \
              | openssl dgst -sha256 -binary \
              | openssl enc -base64)
        if [ -z "$pin" ]; then
            echo "Failed to fetch certificate from $host"
            echo "If you cannot reach this endpoint from your current network,"
            echo "manually obtain the pin and write it to: $pin_cache"
            echo "Format: pin-sha256:BASE64STRING"
            return 1
        fi
        servercert="pin-sha256:$pin"
        echo "$servercert" > "$pin_cache"
        echo "Cached to $pin_cache"
    fi

    # 6. Clean up any stale container
    docker rm -f vpn-hku 2>/dev/null

    # 7. Launch
    docker run --rm -it \
        --name vpn-hku \
        --hostname vpn-hku \
        --cap-add NET_ADMIN \
        --device /dev/net/tun \
        --publish 127.0.0.1:$socks_port:1080 \
        --publish 127.0.0.1:$http_port:1088 \
        -e HKU_PASSWORD="$(cat "$HOME/.vpn/hku.pass")" \
        -e OC_USER="$HKU_USER" \
        -e OC_HOST="$host" \
        -e OC_SERVERCERT="$servercert" \
        local/vpn
}
