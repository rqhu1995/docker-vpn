# Copy this file to ~/.config/fish/functions/hkuvpn.fish.
function hkuvpn --description 'HKU VPN in Docker'
    set -l project_dir $HOME/docker-vpn
    if set -q DOCKER_VPN_HOME
        set project_dir $DOCKER_VPN_HOME
    end
    "$project_dir/bin/hkuvpn" $argv
end
