# Docker-VPN (HKU Edition)

[English](Readme.md) | [简体中文](README.zh-CN.md)

Run HKU's Cisco-compatible VPN inside Docker and expose the tunnel as
loopback-only SOCKS5 and HTTP proxies. Applications use HKU only when a rule or
an explicit proxy setting sends them there. The host's default route stays
unchanged.

```text
normal Internet / existing proxy client --------------------> external sites
                                    |
application -> 127.0.0.1:1080/1088 -> Docker -> OpenConnect -> HKU resources
```

Default listeners:

| Protocol | Address | Purpose |
|---|---|---|
| SOCKS5 | `127.0.0.1:1080` | Preferred application and SSH proxy |
| HTTP | `127.0.0.1:1088` | HTTP/HTTPS clients without SOCKS support |

This project does not turn HKU VPN into a general anonymity service, replace
your normal Internet proxy, or bypass an organization's acceptable-use policy.

## What Is New in This Revision

- English and Chinese documentation with the same operating model.
- A shared `bin/hkuvpn` launcher plus native Zsh/Bash and Fish wrappers.
- `hkuvpn --status`, `--stop`, and non-authenticating `--recover` commands.
- Compatible terminal MFA and detached/file-based MFA modes.
- Longer OpenConnect reconnect handling, optional gateway pinning, and clearer
  exit status reporting.
- Practical Surge rules that keep the VPN control connection out of its own
  tunnel.
- SSH-through-HKU and reverse SSH proxy instructions for remote coding agents.
- A layered Colima, Docker, OpenConnect, and proxy-client troubleshooting guide.

## Choose a Mode

| Situation | Recommended mode |
|---|---|
| Open HKU library or intranet sites locally | Send only HKU domains to `1080` or `1088` |
| Reach a campus SSH or remote-desktop host | Route its exact campus IP/subnet through HKU |
| Use ChatGPT, Claude, Codex, or Copilot locally | Keep them on the existing external proxy group |
| Run a coding agent on a campus computer | Reverse-forward the local proxy to remote loopback port `8152` |
| Both computers are in Hong Kong and the subscription accepts mainland ingress only | Use a supported ingress or move the proxy client to a reachable mainland host; reverse SSH alone cannot change the ingress location |

## How the Layers Fit Together

```text
Mac/Linux host
  |
  +-- Surge/Clash/other proxy on :6152 ---------> normal external route
  |
  +-- Colima or Docker Desktop
        |
        +-- vpn-hku container
              +-- OpenConnect -> HKU AnyConnect endpoint -> tun0
              +-- pproxy SOCKS5 :1080 -> host 127.0.0.1:1080
              +-- pproxy HTTP   :1088 -> host 127.0.0.1:1088
```

Cisco AnyConnect is the server protocol in this design. The official Cisco
desktop client is not started for this connection; OpenConnect runs inside the
container so it cannot replace the host default route.

## Maintainer Reference Setup

This is a tested snapshot, not a minimum-version requirement:

| Component | Tested on 2026-07-20 |
|---|---|
| macOS | 26.5.1, Apple Silicon |
| Terminal / shell | Ghostty, Fish 4.8.1 |
| Colima | 0.10.3, VZ, `virtiofs`, Docker runtime |
| Docker | client 29.6.2, server 29.2.1 |
| Surge | macOS, mixed proxy on `127.0.0.1:6152` |
| OpenConnect in `alpine:3.23` image | 9.12 |
| Current upstream OpenConnect release | 9.21 |

The Homebrew OpenConnect installation on the host is not used by the container.
The image follows Alpine 3.23's package, which is currently 9.12. Upstream 9.21
is the newest release as of this snapshot; check the
[official releases](https://gitlab.com/openconnect/openconnect/-/releases) before
making version-sensitive assumptions.

## Requirements

- An HKU account allowed to use VPN.
- The static HKU Portal PIN and the current Microsoft Authenticator code.
- Docker Engine, Docker Desktop, or Colima.
- `openssl`, available by default on macOS and in common Linux distributions.
- Fish only if you choose the Fish wrapper.
- `autossh` only for the optional persistent reverse tunnel.

## Install

### 1. Install a Docker runtime

Recommended on macOS:

```bash
brew install colima docker
colima start --cpu 2 --memory 2 --disk 20 --vm-type vz --mount-type virtiofs
docker info
```

Docker Desktop also works. On Linux, install Docker Engine from your
distribution or from Docker's official instructions. Windows users can run the
launcher inside WSL2 with Docker Desktop's WSL integration.

### 2. Clone and build

```bash
git clone https://github.com/rqhu1995/docker-vpn.git ~/docker-vpn
cd ~/docker-vpn
docker build -t local/vpn .
```

Confirm the version actually installed in the image:

```bash
docker run --rm --entrypoint openconnect local/vpn --version
```

### 3. Create private configuration

```bash
mkdir -p ~/.vpn
cp ~/docker-vpn/examples/hku.env.example ~/.vpn/hku.env
printf '%s' 'YOUR_PORTAL_PIN' > ~/.vpn/hku.pass
chmod 600 ~/.vpn/hku.pass
```

Edit `~/.vpn/hku.env` and replace the example account:

```ini
HKU_USER=youruid@connect.hku.hk
HKU_ENDPOINT=hk
```

Use the account form HKU assigned to you. Do not put the static PIN, MFA code,
proxy subscription, or private key in this repository.

### 4. Install the shell wrapper

Zsh:

```bash
printf '\nsource ~/docker-vpn/examples/hkuvpn.zsh\n' >> ~/.zshrc
source ~/.zshrc
```

Bash:

```bash
printf '\nsource ~/docker-vpn/examples/hkuvpn.zsh\n' >> ~/.bashrc
source ~/.bashrc
```

Fish:

```fish
mkdir -p ~/.config/fish/functions
cp ~/docker-vpn/examples/hkuvpn.fish ~/.config/fish/functions/hkuvpn.fish
fish -n ~/.config/fish/functions/hkuvpn.fish
```

Do not paste the Zsh function into Fish. Fish does not use `export`,
`VAR=value command`, POSIX `case`, or POSIX function syntax.

If the clone is elsewhere, set `DOCKER_VPN_HOME`:

```bash
export DOCKER_VPN_HOME=/path/to/docker-vpn        # Zsh/Bash
```

```fish
set -Ux DOCKER_VPN_HOME /path/to/docker-vpn      # Fish
```

## Daily Commands

```bash
hkuvpn              # endpoint from ~/.vpn/hku.env
hkuvpn cn           # mainland-facing HKU endpoint
hkuvpn hk           # Hong Kong HKU endpoint
hkuvpn --status
hkuvpn --stop
hkuvpn --recover    # repair Docker/Colima only; does not request MFA
```

At `Response:`, enter the current six-digit Authenticator code. Keep the
terminal open while using the proxies. `Ctrl+C` stops the foreground container.

Endpoint guidance:

| Argument | Server | Usually appropriate when |
|---|---|---|
| `cn` | HKU's mainland-facing address | The client is in mainland China |
| `hk` | `vpn2fa.hku.hk` | The client is in Hong Kong or overseas |

Reachability is more important than geography. If certificate retrieval or TLS
fails, test the other endpoint and inspect the route selected by your existing
proxy client.

## Use the Local Proxies

Quick checks from a second terminal:

```bash
curl -x socks5h://127.0.0.1:1080 -I https://www.hku.hk/
curl -x http://127.0.0.1:1088 -I https://www.hku.hk/
```

Use `socks5h`, not `socks5`, when DNS should also be resolved through the proxy.
The published Docker ports are TCP; do not advertise this setup as a general UDP
proxy.

Per-command proxy examples:

```bash
ALL_PROXY=socks5h://127.0.0.1:1080 curl https://lib.hku.hk/   # Zsh/Bash
```

```fish
env ALL_PROXY=socks5h://127.0.0.1:1080 curl https://lib.hku.hk/
# Or limit a variable to the current Fish block:
begin
    set -lx ALL_PROXY socks5h://127.0.0.1:1080
    curl https://lib.hku.hk/
end
```

Change host ports in `~/.vpn/hku.env` if they conflict:

```ini
HKU_SOCKS_PORT=11080
HKU_HTTP_PORT=11088
```

## Surge Split Routing

Merge [examples/surge.conf](examples/surge.conf) into the existing profile. The
important order is:

1. Route the VPN control endpoint outside the HKU local proxy. Otherwise the
   connection tries to enter its own tunnel before that tunnel exists.
2. Route only exact campus subnets and HKU services to the `HKU` group.
3. Keep AI, general external traffic, and the final rule on the existing proxy
   path.

Minimal fragment:

```ini
[Proxy]
HKU-SOCKS5 = socks5, 127.0.0.1, 1080
HKU-HTTP = http, 127.0.0.1, 1088

[Proxy Group]
HKU = select, HKU-SOCKS5, HKU-HTTP, EXISTING-PROXY, DIRECT
HKU-CONTROL = select, DIRECT, EXISTING-PROXY

[Rule]
DOMAIN,vpn2fa.hku.hk,HKU-CONTROL
IP-CIDR,121.37.195.197/32,HKU-CONTROL,no-resolve
# IP-CIDR,<exact-campus-subnet>,HKU,no-resolve
DOMAIN-SUFFIX,hku.hk,HKU
DOMAIN-SUFFIX,hku.edu.hk,HKU
```

Do not blindly route all `10.0.0.0/8` traffic to HKU. Home, office, and container
networks commonly use that range. Add the smallest campus subnet that your
service needs.

Choose `DIRECT` in `HKU-CONTROL` when the selected endpoint is directly
reachable. Choose `EXISTING-PROXY` only when that route is required and works.
Never select `HKU-SOCKS5` or `HKU-HTTP` for the control group.

The same model works in Clash/Mihomo, sing-box, Quantumult X, Loon, and other
clients that support a local SOCKS5/HTTP upstream and ordered rules. Names and
syntax differ; the control-plane and data-plane separation does not.

## SSH and Remote Desktop Through HKU

For a campus host that is reachable only through HKU, merge and edit
[examples/ssh_config.example](examples/ssh_config.example):

```sshconfig
Host campus-host
  HostName 10.0.0.10
  User yourname
  ProxyCommand nc -X 5 -x 127.0.0.1:1080 %h %p
  ServerAliveInterval 30
  ServerAliveCountMax 3
```

Then connect normally:

```bash
ssh campus-host
```

For remote desktop, route the exact campus destination IP through the HKU group
in Surge Enhanced Mode, or use a remote-desktop client with SOCKS support. A
process-name rule is optional and macOS-specific; an exact destination rule is
more predictable.

## Give a Campus Computer the Local Proxy

This is useful when a coding agent runs on a school computer but your paid proxy
subscription is usable only from the mainland client where Surge/Clash is
running.

### Traffic direction

```text
campus Codex/Copilot
  -> remote 127.0.0.1:8152
  -> encrypted SSH reverse forward
  -> client 127.0.0.1:6152 (existing mixed proxy)
  -> existing paid proxy route
```

Although the option is named `RemoteForward`, the SSH control connection still
starts on the client. `-R` creates a listener on the remote computer and carries
each accepted connection back to a destination visible from the client.

### One-time SSH configuration

```sshconfig
Host campus-host-tunnel
  HostName 10.0.0.10
  User yourname
  ProxyCommand nc -X 5 -x 127.0.0.1:1080 %h %p
  RemoteForward 127.0.0.1:8152 127.0.0.1:6152
  ExitOnForwardFailure yes
  ServerAliveInterval 30
  ServerAliveCountMax 3
```

The explicit remote `127.0.0.1` bind is intentional. OpenSSH also binds remote
forwarding to loopback by default, but writing it explicitly prevents this proxy
from becoming a campus-wide open proxy if server settings later change.

Start and verify:

```bash
ssh -N campus-host-tunnel
ssh campus-host 'curl -x http://127.0.0.1:8152 -I https://www.apple.com/'
```

On the remote computer, scope proxy variables to the agent when possible:

```bash
HTTP_PROXY=http://127.0.0.1:8152 \
HTTPS_PROXY=http://127.0.0.1:8152 \
NO_PROXY=localhost,127.0.0.1 \
codex
```

Fish equivalent:

```fish
begin
    set -lx HTTP_PROXY http://127.0.0.1:8152
    set -lx HTTPS_PROXY http://127.0.0.1:8152
    set -lx NO_PROXY localhost,127.0.0.1
    codex
end
```

Browser-only ChatGPT or Claude usage normally belongs on the local browser and
does not require remote forwarding. Use the tunnel when the process itself runs
on the campus computer, as with remote Codex, Copilot, package managers, or Git.

### Keep the tunnel alive

```bash
brew install autossh
autossh -M 0 -N campus-host-tunnel
```

`-M 0` uses OpenSSH's own keepalives from the host block. For unattended macOS
use, place that command in a user LaunchAgent. A running `autossh` process is not
proof that the forward is healthy; verify remote `127.0.0.1:8152` with `curl`.

This design does not help if the SSH client and proxy client are also in Hong
Kong while the subscription accepts connections only from mainland China. The
proxy ingress remains the machine running port `6152`. In that topology, run the
proxy client on a reachable mainland machine/VPS or buy a supported ingress.

## Advanced Reliability

### OpenConnect reconnects

The entrypoint uses verbose timestamps and a 30-minute reconnect window. Recent
failures can still end with `CSTP Dead Peer Detection detected dead peer`, TLS
read errors, `Host is unreachable`, or a rejected cookie.

A `401 Unauthorized` or rejected cookie immediately after reconnect can mean
that DNS selected a different HKU backend. Advanced users can pin one real
gateway for the session:

```ini
HKU_RESOLVE=vpn2fa.hku.hk:REAL_IP
```

Use only an IP learned from real DNS or the proxy client's real DNS cache. Do not
use `198.18.0.0/15` fake-IP results from enhanced mode. Re-check this address
when HKU changes infrastructure; a stale pin prevents connection.

### Colima recovery levels

1. `docker info`: verify the host socket, not only `colima status`.
2. `hkuvpn --recover`: start/restart Colima without requesting a new MFA code.
3. `colima ssh -- docker info`: distinguish a healthy guest daemon from broken
   host socket forwarding.
4. Inspect `~/.colima/_lima/colima/ha.stderr.log` for VZ or disk-attachment
   failures.
5. Use `colima stop --force` only when the control plane is stuck. macOS may need
   one or more minutes to release the VZ disk before a restart succeeds.

Deleting the Colima VM is a last resort because it removes local images and
containers. It is not the first troubleshooting command.

### Proxy-client independence

Surge-specific automatic reload and policy switching are intentionally not in
the portable launcher. Users of Clash, sing-box, or no proxy client must still
be able to use Docker-VPN. If you automate a client, keep these rules:

- On HKU tunnel failure, move HKU traffic to an explicit fallback such as
  `DIRECT` or an existing Hong Kong route.
- Never send `vpn2fa.hku.hk` or the mainland endpoint into `HKU-SOCKS5`.
- Restore the HKU group only after the local `1080/1088` listener and tunnel are
  confirmed healthy.

## Troubleshooting

### No tmux/terminal session remains

Check Docker first. A launcher can exit before the VPN prompt if the Colima host
socket is unavailable:

```bash
docker info
colima status
hkuvpn --recover
```

### Certificate retrieval fails

Try `hkuvpn cn` and `hkuvpn hk`, check the control-endpoint rule, and remove only
the affected cache after verifying the endpoint:

```bash
rm ~/.vpn/pin-hk.cache
```

### Port already in use

```bash
lsof -nP -iTCP:1080 -sTCP:LISTEN
```

Select different host ports in `~/.vpn/hku.env` and update the proxy-client
entries to match.

### Container is running but a service fails

Test each layer separately:

```bash
docker ps --filter name=vpn-hku
hkuvpn --status
curl -x socks5h://127.0.0.1:1080 -I https://www.hku.hk/
ssh -G campus-host | grep -E 'proxycommand|hostname|port'
```

Do not treat `autossh` or `colima status` alone as an end-to-end health check.

## Security

- Proxies bind to host loopback only. Do not publish them on `0.0.0.0` without
  authentication and a firewall.
- Reverse forwarding also binds to remote loopback only. Do not enable
  `GatewayPorts yes` for this use case.
- `~/.vpn/hku.pass` is plaintext. Set mode `600` and enable disk encryption.
- Docker environment variables can be inspected by a user with Docker access.
  Treat Docker access as privileged.
- The container needs `NET_ADMIN` and `/dev/net/tun`. Review changes before
  rebuilding and do not use untrusted images.
- Keep private hostnames, campus IPs, account names, certificate caches, logs,
  subscription URLs, and SSH keys out of issues and commits.

## Repository vs Local Deployment

The portable repository includes the launcher, shell wrappers, routing examples,
and container entrypoint. A maintainer deployment may additionally include
machine-specific Fish recovery logic, Surge CLI automation, tmux monitoring,
LaunchAgents, and diagnostic logs under `~/.vpn/logs/`. Those items are examples
of advanced operations, not hidden project requirements.

Before comparing local and GitHub behavior:

```bash
git status --short --branch
git fetch origin
git log --oneline --left-right HEAD...origin/main
git diff origin/main --
```

## Credits and Licensing

Derived from [ethack/docker-vpn](https://github.com/ethack/docker-vpn) and
adapted for HKU, OpenConnect MFA, and loopback proxy export.

This repository currently has no explicit `LICENSE` file. Do not assume that a
fork automatically grants a license. The maintainer should select a compatible
license and add the complete license text before inviting redistribution or
outside contributions.
