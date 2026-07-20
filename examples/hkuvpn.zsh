# Source this file from ~/.zshrc or ~/.bashrc.
hkuvpn() {
    "${DOCKER_VPN_HOME:-$HOME/docker-vpn}/bin/hkuvpn" "$@"
}
