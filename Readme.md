# Docker-VPN (HKU edition)

Connect to HKU VPN (`vpn2fa.hku.hk`) from a Docker container using
openconnect, with automatic password entry and manual Microsoft
Authenticator OTP input. The VPN tunnel is exposed as **SOCKS5** and
**HTTP** proxies on localhost, enabling per-app split tunneling — route
only HKU traffic (journals, library, internal services) through the VPN
while keeping the rest of your network untouched. This is especially
useful for users in mainland China who need to access both HKU resources
and sites blocked by the GFW (Claude, ChatGPT, Google Scholar, GitHub
Copilot, etc.) through separate routing paths.

> **TL;DR** — `hkuvpn` in your terminal, type the 6-digit OTP when
> prompted, done. SOCKS5 on `127.0.0.1:1080`, HTTP on `127.0.0.1:1088`.

## Quick start

**Prerequisites:** macOS with a Docker runtime — we recommend
[Colima](https://github.com/abiosoft/colima) (`brew install colima docker`),
an HKU account with VPN access, and Microsoft Authenticator set up for
your HKU account. See [Platform support](#platform-support) for Linux /
Windows.

```bash
# 1. Clone and build
git clone https://github.com/rqhu1995/docker-vpn.git ~/docker-vpn
cd ~/docker-vpn && docker build -t local/vpn .

# 2. Create config (edit HKU_USER to your HKU email)
mkdir -p ~/.vpn
cp examples/hku.env.example ~/.vpn/hku.env

# 3. Save your HKU Portal PIN (the static password, NOT the OTP)
printf '%s' 'YOUR_PORTAL_PIN' > ~/.vpn/hku.pass
chmod 600 ~/.vpn/hku.pass

# 4. Add the launcher to your shell
cat examples/hkuvpn.zsh >> ~/.zshrc
source ~/.zshrc

# 5. Connect!
hkuvpn
```

When you see the `Response:` prompt, open Microsoft Authenticator, type
the 6-digit code, press Enter. Press **Ctrl+C** to disconnect.

> **Note:** `printf '%s'` (not `echo`) avoids a trailing newline. Verify
> with `wc -c ~/.vpn/hku.pass` — should equal your PIN length exactly.

## Usage

```bash
hkuvpn          # use default endpoint from ~/.vpn/hku.env
hkuvpn cn       # force mainland China endpoint (faster from CN)
hkuvpn hk       # force Hong Kong endpoint
```

### Endpoints

HKU provides two VPN endpoints with identical credentials but different
network paths:

| Endpoint | Host             | Best for                      |
|----------|------------------|-------------------------------|
| `cn`     | `121.37.195.197` | Users in mainland China       |
| `hk`     | `vpn2fa.hku.hk`  | Users in Hong Kong / overseas |

The `cn` endpoint uses a self-signed certificate, `hk` uses a
DigiCert-signed one. Both are validated via public key pinning — the
launcher auto-fetches and caches the fingerprint on first connect
(`~/.vpn/pin-{cn,hk}.cache`). If HKU rotates a certificate (rare),
delete the cache file and reconnect.

## Using the proxies

By default the proxies are exposed on:

- **SOCKS5**: `127.0.0.1:1080`
- **HTTP**: `127.0.0.1:1088`

Quick test:

```bash
curl -x socks5h://127.0.0.1:1080 -I https://www.hku.hk
curl -x http://127.0.0.1:1088    -I https://www.hku.hk
```

### Custom ports

If 1080/1088 conflict with an existing proxy (Surge, Clash, etc.), set
`HKU_SOCKS_PORT` / `HKU_HTTP_PORT` in `~/.vpn/hku.env`, or override
per-invocation:

```bash
HKU_SOCKS_PORT=11080 HKU_HTTP_PORT=11088 hkuvpn
```

The container always uses 1080/1088 internally — these only change the
host-side mapping, no rebuild needed.

### Routing through an existing proxy client

If you already run Surge, Clash, V2RayN, etc., the cleanest setup is to
add docker-vpn as an upstream proxy and write a rule that routes only
HKU traffic through it.

<details>
<summary><b>Surge (macOS / iOS)</b></summary>

```ini
[Proxy]
HKU-SOCKS5 = socks5, 127.0.0.1, 1080
HKU-HTTP   = http, 127.0.0.1, 1088

[Rule]
DOMAIN-SUFFIX,hku.hk,HKU-SOCKS5
DOMAIN-SUFFIX,hku.edu.hk,HKU-SOCKS5
# Add more HKU-specific suffixes as needed
```

SOCKS5 is generally preferred (UDP-capable); HTTP is a fallback for apps
that don't speak SOCKS.

</details>

<details>
<summary><b>Clash / Clash Verge / Clash Verge Rev / Mihomo</b></summary>

```yaml
proxies:
  - name: "HKU-SOCKS5"
    type: socks5
    server: 127.0.0.1
    port: 1080
    udp: true

  - name: "HKU-HTTP"
    type: http
    server: 127.0.0.1
    port: 1088

proxy-groups:
  - name: "HKU"
    type: select
    proxies:
      - HKU-SOCKS5
      - HKU-HTTP
      - DIRECT

rules:
  - DOMAIN-SUFFIX,hku.hk,HKU
  - DOMAIN-SUFFIX,hku.edu.hk,HKU
  # ... your other rules below
```

In the UI, pick `HKU-SOCKS5` from the new "HKU" proxy group.

</details>

<details>
<summary><b>V2RayN / V2RayNG (Windows / Android)</b></summary>

Add to your Xray JSON config:

```json
{
  "outbounds": [
    {
      "tag": "hku-vpn",
      "protocol": "socks",
      "settings": {
        "servers": [
          { "address": "127.0.0.1", "port": 1080 }
        ]
      }
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "domain": ["domain:hku.hk", "domain:hku.edu.hk"],
        "outboundTag": "hku-vpn"
      }
    ]
  }
}
```

Apply via "Settings → Routing → Custom routing rules" or a custom config
profile. If editing JSON feels painful, Clash Verge Rev has a friendlier
rule editor with the same capabilities.

</details>

<details>
<summary><b>Other clients</b></summary>

The pattern is the same in any tool that supports upstream SOCKS5/HTTP
proxies + rule-based routing: declare `127.0.0.1:1080` as a proxy,
write a domain rule for `hku.hk`, point the rule at it. Quantumult X,
Loon, sing-box, Shadowrocket etc. all support this.

</details>

**What domains to route:** `hku.hk` and `hku.edu.hk` cover most cases
(portal, internal services, library). Add specific journal proxy
hostnames as needed. Don't route everything — only hosts that require an
HKU IP.

### Browser

Configure SOCKS5 `127.0.0.1:1080` in your browser, or use an extension
like FoxyProxy / SwitchyOmega for per-site rules.

### Terminal apps

Most CLI tools respect `ALL_PROXY` / `HTTPS_PROXY`:
```bash
export ALL_PROXY=socks5h://127.0.0.1:1080
```

## Why not Cisco AnyConnect?

HKU's official AnyConnect client routes **all** traffic through the VPN
with no split-tunneling. This forces your entire internet connection
through HKU's network — slower speeds, privacy concerns, and broken
workflows when you need both HKU intranet access and direct connections
to other services simultaneously.

This project runs openconnect inside a container and exposes the tunnel
as localhost proxies, so you decide per-app whether to use the VPN.

## How it works

- **openconnect** connects to HKU's Cisco AnyConnect-compatible VPN
  endpoint inside an Alpine container
- **expect** automates the static password prompt, then `interact` hands
  the terminal back for you to type the Microsoft Authenticator OTP
- **pproxy** (managed by supervisord) exposes the tunnel as SOCKS5 and
  HTTP proxies on `0.0.0.0:1080` / `0.0.0.0:1088` inside the container,
  mapped to `127.0.0.1` on the host
- The expect script is PID 1 — Ctrl+C kills it, which stops the
  container and all child processes cleanly

## Platform support

**macOS** is the primary tested platform (Apple Silicon +
[Colima](https://github.com/abiosoft/colima), recommended).

**Linux** works without modification — just remove the `colima start`
block from the `hkuvpn` function (your Docker daemon is already
running).

**Windows** should work via Docker Desktop + WSL2. The container is a
standard Linux image; `--cap-add NET_ADMIN` and `--device /dev/net/tun`
work through WSL2. Run the `hkuvpn` function from a WSL2 distro (e.g.
Ubuntu) — `localhost:1080` forwards to the Windows host out of the box.
**Not tested by the author** — please open an issue or PR with your
findings.

## Troubleshooting

**`Failed to fetch certificate from $host`**
Your network can't reach that endpoint. Try the other one (`hkuvpn cn`
vs `hkuvpn hk`), or manually write the pin to
`~/.vpn/pin-{cn,hk}.cache` in the format `pin-sha256:BASE64STRING`.

**`Login failed` after entering OTP**
The OTP expired (they roll every 30 seconds). Wait for a fresh code.

**`Colima not ready` loops**
`colima stop && colima start`. If stuck, `colima delete` and recreate.

**Port 1080 / 1088 already in use**
Find what's using it (`lsof -i :1080`), or set `HKU_SOCKS_PORT` /
`HKU_HTTP_PORT` in `~/.vpn/hku.env`.

## Security notes

- `~/.vpn/hku.pass` stores your Portal PIN in plaintext. Use FileVault.
- The container needs `NET_ADMIN` and `/dev/net/tun` for the tun
  interface. Proxies bind to `127.0.0.1` only — not exposed to LAN.
- OTP entry is intentionally manual. That's the point of MFA.

## Credits

Forked from [ethack/docker-vpn](https://github.com/ethack/docker-vpn).
This edition strips it down to HKU-specific use, adds `expect`-based
MFA handling, replaces the ssh-based SOCKS proxy with pproxy, and
removes the embedded sshd.

## License

Inherits the upstream license. See LICENSE.
