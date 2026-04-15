# docker-vpn (HKU edition)

A lightweight Docker-based HKU VPN client that exposes the connection
as SOCKS5 and HTTP proxies on localhost, so you can route specific apps
through HKU VPN instead of forcing all system traffic through it.

## Why not Cisco AnyConnect?

HKU's official AnyConnect client routes all traffic through the VPN with
no split-tunneling. This breaks workflows that need both HKU intranet
access (e.g. journals, internal services) and a separate proxy for other
sites. Running openconnect inside a container and exposing it as
localhost proxies (SOCKS5 on 1080, HTTP on 1088 by default) lets you
decide per-app whether to use the VPN — your browser, terminal, IDE,
etc. each choose independently.

## What's inside

- `openconnect` running in an Alpine container, authenticating against
  HKU's two-factor VPN
- `expect` automating the static password step, then handing control
  back to your terminal so you can enter the Microsoft Authenticator OTP
- `pproxy` (managed by supervisord) exposing the tunnel as SOCKS5 and
  HTTP proxies bound to 127.0.0.1

## Prerequisites

- macOS (tested on Apple Silicon)
- [Colima](https://github.com/abiosoft/colima) (`brew install colima docker`)
  or any other Docker-compatible runtime
- An HKU account with VPN access
- Microsoft Authenticator set up for your HKU account

## Setup (5 steps)

1. **Clone and build**
   ```bash
   git clone https://github.com/rqhu1995/docker-vpn.git ~/docker-vpn
   cd ~/docker-vpn
   docker build -t local/vpn .
   ```

2. **Create your config file**
   ```bash
   mkdir -p ~/.vpn
   cp ~/docker-vpn/examples/hku.env.example ~/.vpn/hku.env
   # Edit ~/.vpn/hku.env and fill in HKU_USER
   ```

3. **Create your password file** (your HKU Portal PIN, the static one)
   ```bash
   printf '%s' 'YOUR_PORTAL_PIN' > ~/.vpn/hku.pass
   chmod 600 ~/.vpn/hku.pass
   ```
   Note `printf '%s'` (not `echo`) — you do **not** want a trailing newline.
   Verify with `wc -c ~/.vpn/hku.pass` (should equal your PIN length exactly).

4. **Add the launcher function to your shell**
   ```bash
   cat ~/docker-vpn/examples/hkuvpn.zsh >> ~/.zshrc
   source ~/.zshrc
   ```
   (Bash users: same file works, append to `~/.bashrc` instead.)

5. **Connect**
   ```bash
   hkuvpn          # use default endpoint from ~/.vpn/hku.env
   hkuvpn cn       # force mainland China endpoint (faster from CN)
   hkuvpn hk       # force Hong Kong endpoint
   ```
   When prompted with `Response:`, open Microsoft Authenticator on your
   phone, get the current 6-digit OTP, type it, and press Enter.

   Press Ctrl+C to disconnect.

## Using the proxies

By default the proxies are exposed on:

- **SOCKS5**: `127.0.0.1:1080`
- **HTTP**: `127.0.0.1:1088`

If you already have a local proxy (Surge, Clash, etc.) on those ports,
set `HKU_SOCKS_PORT` and/or `HKU_HTTP_PORT` in `~/.vpn/hku.env` to pick
different host-side ports. You can also override them per-invocation:

```bash
HKU_SOCKS_PORT=11080 HKU_HTTP_PORT=11088 hkuvpn
```

The container internally always uses 1080 and 1088 — these settings only
change what your host sees, so the image doesn't need to be rebuilt.

Quick test (replace `1080` / `1088` with your custom ports if you set them):

```bash
curl -x socks5h://127.0.0.1:1080 -I https://www.hku.hk
curl -x http://127.0.0.1:1088    -I https://www.hku.hk
```

### Browser

Configure SOCKS5 `127.0.0.1:1080` in your browser, or use an extension
like FoxyProxy / SwitchyOmega for per-site rules.

### Terminal apps

Most CLI tools respect `ALL_PROXY` / `HTTPS_PROXY`:
```bash
export ALL_PROXY=socks5h://127.0.0.1:1080
```

## Endpoints

HKU provides two VPN endpoints. They have identical credentials but
different network paths:

| Endpoint | Host                  | Best for                       |
|----------|-----------------------|--------------------------------|
| `cn`     | `121.37.195.197`      | Users in mainland China        |
| `hk`     | `vpn2fa.hku.hk`       | Users in Hong Kong / overseas  |

The `cn` endpoint uses a self-signed certificate (validated via pinning),
the `hk` endpoint uses a DigiCert-signed certificate. The launcher
handles both transparently — on first connect to each endpoint, it
fetches the certificate's public key fingerprint via `openssl` and
caches it to `~/.vpn/pin-{cn,hk}.cache`.

If HKU rotates a certificate (rare), delete the corresponding cache
file and reconnect.

## Troubleshooting

**`Failed to fetch certificate from $host`**
Your current network can't reach that endpoint. Try the other one
(`hkuvpn cn` vs `hkuvpn hk`), or manually obtain the pin and write it
to `~/.vpn/pin-{cn,hk}.cache` in the format `pin-sha256:BASE64STRING`.

**`Login failed` after entering OTP**
The OTP expired (they roll every 30 seconds). Wait for a fresh code
and try again.

**`Colima not ready` loops or hangs**
`colima stop && colima start`. If that doesn't help, `colima delete`
and recreate.

**Port 1080 / 1088 already in use**
Another process is bound there. Either stop it (find with
`lsof -i :1080`) or set `HKU_SOCKS_PORT` / `HKU_HTTP_PORT` in
`~/.vpn/hku.env` to use different ports — see "Using the proxies" above.

## Security notes

- `~/.vpn/hku.pass` stores your Portal PIN in plaintext. Use FileVault.
- The container runs with `--cap-add NET_ADMIN` and `--device /dev/net/tun`
  because openconnect needs to manage a tun interface. The proxies are
  bound to `127.0.0.1` only, not exposed to your LAN.
- OTP entry is intentionally manual — that's the whole point of MFA and
  cannot be automated without defeating the security guarantee.

## Credits

Originally forked from [ethack/docker-vpn](https://github.com/ethack/docker-vpn),
a general-purpose VPN-in-a-container tool. This fork strips it down to
HKU-specific use, adds `expect`-based MFA handling, switches the SOCKS
proxy from ssh-based to pproxy-based, and removes the embedded sshd.
See git history for the full diff.

## License

Inherits the upstream license. See LICENSE.
