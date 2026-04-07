#!/bin/bash

# Simple function to start a VPN container with interactive shell
vpn_shell() {
    local vpnName="$1"; shift
    if [ -z "$vpnName" ]; then
        echo "VPN name must be provided (e.g., vpn_shell myconnection)"
        return
    fi
    
    # Default port settings
    local bindIf="${BIND_INTERFACE:-127.0.0.1}"
    local socksPort="${SOCKS_PORT:-1080}"
    local httpProxyPort="${HTTP_PROXY_PORT:-1088}"
    local sshPort="${SSH_PORT:-2222}"
    local authorizedKeys="${AUTHORIZED_KEYS}"
    
    # Set up authorized keys
    if [ -z "$authorizedKeys" ]; then
        if [ -f "$HOME/.ssh/authorized_keys" ]; then
            printf -v authorizedKeys "$(cat "$HOME/.ssh/authorized_keys")\n"
        fi
        if command -v ssh-add >/dev/null; then
            printf -v authorizedKeys "$(ssh-add -L)\n"
        fi
        authorizedKeys+=$(find "$HOME/.ssh/" -type f -name '*.pub' -exec cat {} \;)
    fi

    # Set up SSH config
    mkdir -p "$HOME/.ssh/config.d/"
    cat > "$HOME/.ssh/config.d/vpn-$vpnName" << EOF
Host vpn-$vpnName $vpnName
    Hostname 127.0.0.1
    User root
    Port $sshPort
    NoHostAuthenticationForLocalhost yes
EOF
    chmod 600 "$HOME/.ssh/config.d/vpn-$vpnName"

    # Include config.d in SSH config if needed
    if ! grep -qFi -e 'Include config.d/*' -e 'Include ~/.ssh/config.d/*' "$HOME/.ssh/config" 2>/dev/null; then
        echo >> "$HOME/.ssh/config"
        echo 'Match all' >> "$HOME/.ssh/config"
        echo 'Include config.d/*' >> "$HOME/.ssh/config"
    fi

    echo "============================================"
    echo "SSH Port: $sshPort (customize with SSH_PORT)"
    echo "SOCKS Proxy Port: $socksPort (customize with SOCKS_PORT)"
    echo "HTTP Proxy Port: $httpProxyPort (customize with HTTP_PROXY_PORT)"
    echo "Use: ssh $vpnName (after connecting VPN)"
    echo "============================================"

    # Run the container with shell entrypoint
    docker run --rm --name "vpn-$vpnName" \
        --hostname "vpn-$vpnName" \
        --cap-add NET_ADMIN \
        --device /dev/net/tun \
        --publish "$bindIf:$sshPort:22" \
        --publish "$bindIf:$socksPort:1080" \
        --publish "$bindIf:$httpProxyPort:1088" \
        --env "AUTHORIZED_KEYS=$authorizedKeys" \
        --interactive --tty \
        --entrypoint /bin/sh \
        ethack/vpn -c "echo 'VPN Container Shell'; echo '==================='; echo '1. First run: /docker-entrypoint.sh'; echo '2. Then run your VPN command, for example:'; echo '   openconnect https://your-vpn-server.com --user your-username'; echo ''; echo 'Once connected, you can access the VPN from your host via:'; echo '- SSH: ssh $vpnName'; echo '- SOCKS proxy: localhost:$socksPort'; echo '- HTTP proxy: localhost:$httpProxyPort'; echo ''; exec /bin/sh"
}

echo "Added vpn_shell function. Run 'vpn_shell myconnection' to start."

