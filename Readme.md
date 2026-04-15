# Docker-VPN (HKU Edition)

Connect to HKU's VPN from a Docker container — then use the tunnel as a
**local proxy** so only the apps you choose go through HKU's network.

**The problem:** HKU's official Cisco AnyConnect client routes *all* your
traffic through the VPN. That means slower speeds, privacy trade-offs,
and broken workflows — when you need HKU
resources (HKU Library academic resources, in-campus remote desktops) *and* sites like Claude (Code) and ChatGPT (Currently are not available in both Hong Kong and mainland China, and require additional proxy to bypass the access restrictions) at the same time.

**This solution:** Run the VPN inside a lightweight container and expose
it as SOCKS5 / HTTP proxies on `localhost`. You decide per-app whether
to use the VPN. Everything else stays on your normal connection.

> **TL;DR** — Run `hkuvpn`, type your 6-digit OTP, done.
> SOCKS5 on `127.0.0.1:1080`, HTTP on `127.0.0.1:1088`.

## Real Use at a Glance

**Typical pain without this project:**

1. Start Cisco AnyConnect to access HKU services.
2. Need ChatGPT / Claude (Code) via your own proxy (for example Surge
   on port `6152`).
3. AnyConnect globally takes over network routing, so you disconnect HKU
   VPN first, then switch back to your own proxy.
4. Later you need HKU again, so you reconnect AnyConnect again.

**With docker-vpn:**

1. Keep your own proxy stack (for example Surge `127.0.0.1:6152`) as-is
   for ChatGPT / Claude (Code).
2. Run `hkuvpn` in Docker to expose local HKU proxies (`127.0.0.1:1080`
   / `127.0.0.1:1088`).
3. In Surge (or similar), route only HKU domains/services to
   docker-vpn, keep AI tools and everything else on your normal/proxy
   path.
4. Result: HKU resources and ChatGPT/Claude can work at the same time,
   no repeated VPN on/off switching.

---

## Table of Contents

- [Real Use at a Glance](#real-use-at-a-glance)
- [What You Need](#what-you-need)
- [Setup (One-Time)](#setup-one-time)
  - [Step 1 — Install Docker](#step-1--install-docker)
  - [Step 2 — Build the VPN Image](#step-2--build-the-vpn-image)
  - [Step 3 — Create Your Config Files](#step-3--create-your-config-files)
  - [Step 4 — Install the Launcher](#step-4--install-the-launcher)
- [Daily Usage](#daily-usage)
- [Using the Proxies](#using-the-proxies)
  - [Quick Test](#quick-test)
  - [Custom Ports](#custom-ports)
  - [Browser](#browser)
  - [Terminal / CLI](#terminal--cli)
  - [Routing Through a Proxy Client](#routing-through-a-proxy-client)
- [How It Works](#how-it-works)
- [Troubleshooting](#troubleshooting)
- [Security Notes](#security-notes)
- [Credits & License](#credits--license)

---

## What You Need

Before you start, make sure you have:

| #  | Requirement | Why |
|----|-------------|-----|
| 1  | **An HKU account with VPN access** | The service connects to HKU's VPN endpoint |
| 2  | **Microsoft Authenticator** on your phone, set up for your HKU account | You'll type a 6-digit one-time code each time you connect |
| 3  | **Your HKU Portal PIN** (the static password you use to log in to HKU Portal — *not* the OTP) | The launcher sends it automatically so you only have to type the OTP |
| 4  | **Docker** installed on your computer | The VPN runs inside a Docker container — see [Step 1](#step-1--install-docker) |
| 5  | **A terminal** (Terminal.app, iTerm2, Windows Terminal, etc.) | You'll run a few commands to set things up and connect |

> **New to Docker?** Docker lets you run a small, isolated Linux
> environment ("container") on your computer. You don't need to know how
> it works — just install it and the launcher script handles the rest.

---

## Setup (One-Time)

You only need to do these steps once. After that, connecting is a single
command.

### Step 1 — Install Docker

Pick your operating system:

<details open>
<summary><b>macOS</b></summary>

We recommend **Colima** — a lightweight Docker runtime that runs in the
background. Install it with [Homebrew](https://brew.sh):

```bash
brew install colima docker
```

Start it once to make sure it works:

```bash
colima start
```

> Don't have Homebrew? Install it first:
> ```bash
> /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
> ```

> **Alternative:** [Docker Desktop for Mac](https://www.docker.com/products/docker-desktop/)
> also works. If you use Docker Desktop, remove the Colima health-check
> block from the launcher function (Step 4) — it's only needed for Colima.

</details>

<details>
<summary><b>Linux (Ubuntu / Debian / Fedora / Arch)</b></summary>

Install Docker Engine using your distro's package manager. For example,
on Ubuntu / Debian:

```bash
sudo apt update
sudo apt install docker.io
sudo systemctl enable --now docker
```

Then add yourself to the `docker` group so you don't need `sudo` every
time:

```bash
sudo usermod -aG docker $USER
```

**Log out and back in** (or run `newgrp docker`) for the group change to
take effect.

Verify it works:

```bash
docker run --rm hello-world
```

> See the [official Docker docs](https://docs.docker.com/engine/install/)
> for other distros.

</details>

<details>
<summary><b>Windows</b></summary>

1. Install **[Docker Desktop](https://www.docker.com/products/docker-desktop/)**
   and enable the **WSL 2 backend** during setup.
2. Open **Windows Terminal** and launch a WSL2 distro (e.g. Ubuntu).
3. Follow the rest of this guide inside that WSL2 terminal — all
   commands work the same as on Linux.
4. Proxies on `localhost:1080` / `localhost:1088` inside WSL2
   automatically forward to the Windows host, so your Windows apps can
   use them too.

> **Note:** Windows support is community-tested. If you run into issues,
> please [open an issue](https://github.com/rqhu1995/docker-vpn/issues).

</details>

### Step 2 — Build the VPN Image

Clone this repository and build the Docker image:

```bash
git clone https://github.com/rqhu1995/docker-vpn.git ~/docker-vpn
cd ~/docker-vpn
docker build -t local/vpn .
```

This downloads a small Alpine Linux base image and installs the VPN
tools inside it. It only needs internet access this one time.

> **What's happening:** `docker build` reads the `Dockerfile` in this
> repo and creates a local image called `local/vpn`. It installs
> `openconnect` (the VPN client), `pproxy` (the proxy server), and a
> few helper tools. The resulting image is ~80 MB.

### Step 3 — Create Your Config Files

Create a private directory for your VPN config:

```bash
mkdir -p ~/.vpn
```

**a) Copy and edit the config template:**

```bash
cp ~/docker-vpn/examples/hku.env.example ~/.vpn/hku.env
```

Open `~/.vpn/hku.env` in any text editor and change `youruid` to your
actual HKU UID:

```bash
# Students: uid@connect.hku.hk
# Staff:    uid@hku.hk
HKU_USER=youruid@connect.hku.hk
```

Save and close the file. Leave the other settings at their defaults for
now.

**b) Save your Portal PIN:**

```bash
printf '%s' 'YOUR_PORTAL_PIN' > ~/.vpn/hku.pass
chmod 600 ~/.vpn/hku.pass
```

Replace `YOUR_PORTAL_PIN` with your actual HKU Portal password (the
static one, **not** the 6-digit OTP).

> **Why `printf` instead of `echo`?** `echo` adds a hidden newline
> character at the end of the file, which would make your password
> wrong. `printf '%s'` writes exactly what you give it.
>
> **Verify it's correct:** Run `wc -c ~/.vpn/hku.pass` — the number
> should equal the length of your PIN (e.g. an 8-character PIN → `8`).

### Step 4 — Install the Launcher

The launcher is a shell function that handles Docker, certificates, and
credentials for you. Add it to your shell profile:

**For Zsh (default on macOS):**

```bash
cat ~/docker-vpn/examples/hkuvpn.zsh >> ~/.zshrc
source ~/.zshrc
```

**For Bash (default on most Linux distros):**

```bash
cat ~/docker-vpn/examples/hkuvpn.zsh >> ~/.bashrc
source ~/.bashrc
```

> **Not sure which shell you use?** Run `echo $SHELL`. If the output
> ends in `zsh`, use `.zshrc`; if it ends in `bash`, use `.bashrc`.

> **Linux users:** The launcher includes a Colima health-check (lines
> 15-18 in `hkuvpn.zsh`) designed for macOS. On Linux, Docker runs
> natively so this block is harmless — it simply gets skipped when
> `docker info` succeeds. No changes needed.

---

## Daily Usage

After the one-time setup, connecting is just:

```bash
hkuvpn
```

1. The launcher builds the connection automatically.
2. When you see `Response:`, open **Microsoft Authenticator** on your
   phone, find the 6-digit code for HKU, type it, and press **Enter**.
3. You're connected! The terminal stays open — this is normal.
4. Press **Ctrl+C** to disconnect when you're done.

### Choosing an Endpoint

HKU provides two VPN endpoints. The launcher picks one automatically,
or you can choose:

```bash
hkuvpn          # use the default from ~/.vpn/hku.env
hkuvpn cn       # mainland China endpoint (faster from CN)
hkuvpn hk       # Hong Kong endpoint (better outside CN)
```

| Endpoint | Host | Best for |
|----------|------|----------|
| `cn` | `121.37.195.197` | Users in mainland China |
| `hk` | `vpn2fa.hku.hk` | Users in Hong Kong / overseas |

The first time you connect to an endpoint, the launcher fetches and
caches its certificate fingerprint in `~/.vpn/pin-{cn,hk}.cache`. This
is automatic.

---

## Using the Proxies

Once connected, two proxies are available on your machine:

| Protocol | Address | Default Port |
|----------|---------|-------------|
| SOCKS5 | `127.0.0.1` | `1080` |
| HTTP | `127.0.0.1` | `1088` |

Any app you point at these proxies will route its traffic through HKU's
VPN. Everything else uses your normal internet.

### Quick Test

Open a **new** terminal window (keep the VPN terminal running) and try:

```bash
curl -x socks5h://127.0.0.1:1080 -I https://www.hku.hk
curl -x http://127.0.0.1:1088    -I https://www.hku.hk
```

If you see `HTTP/... 200`, the VPN is working.

### Custom Ports

If ports 1080 or 1088 are already taken (e.g. by Surge, Clash, etc.),
change them in `~/.vpn/hku.env`:

```bash
HKU_SOCKS_PORT=11080
HKU_HTTP_PORT=11088
```

Or override per-session:

```bash
HKU_SOCKS_PORT=11080 HKU_HTTP_PORT=11088 hkuvpn
```

### Browser

Set your browser's proxy to SOCKS5 `127.0.0.1:1080`. For per-site
rules (recommended), use an extension like
[FoxyProxy](https://getfoxyproxy.org/) or
[SwitchyOmega](https://github.com/nicehash/nicehash-js-web-ext) to
only route `*.hku.hk` through the proxy.

### Terminal / CLI

Most command-line tools respect the `ALL_PROXY` environment variable:

```bash
export ALL_PROXY=socks5h://127.0.0.1:1080
```

Add this to your shell profile to make it persistent, or prefix
individual commands:

```bash
ALL_PROXY=socks5h://127.0.0.1:1080 curl https://lib.hku.hk
```

### Routing Through a Proxy Client

If you already run a proxy client (Surge, Clash, V2RayN, etc.), the
cleanest setup is to add docker-vpn as an **upstream proxy** and write
rules to route only HKU traffic through it.

<details>
<summary><b>Surge (macOS / iOS)</b></summary>

```ini
[Proxy]
HKU-SOCKS5 = socks5, 127.0.0.1, 1080
HKU-HTTP   = http, 127.0.0.1, 1088

[Rule]
DOMAIN-SUFFIX,hku.hk,HKU-SOCKS5
DOMAIN-SUFFIX,hku.edu.hk,HKU-SOCKS5
```

SOCKS5 is preferred (UDP-capable); HTTP is a fallback for apps that
don't speak SOCKS.

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
profile.

</details>

<details>
<summary><b>Other clients</b></summary>

The pattern is the same in any tool that supports upstream SOCKS5/HTTP
proxies + rule-based routing: declare `127.0.0.1:1080` as a proxy,
write a domain rule for `hku.hk`, point the rule at it. Quantumult X,
Loon, sing-box, Shadowrocket, etc. all support this.

</details>

**Which domains to route:** `hku.hk` and `hku.edu.hk` cover most
cases (portal, internal services, library). Add specific journal proxy
hostnames as needed. Only route what actually requires an HKU IP.

---

## How It Works

```
Your computer                                                     Docker container
─────────────                                                     ────────────────
                                                                  ┌──────────────────────────┐
 hkuvpn (shell fn)                                                │  hku-connect.exp (PID 1) │
   │                                                              │    ├─ openconnect → VPN  │
   ├─ loads ~/.vpn/hku.env                                        │    └─ sends Portal PIN   │
   ├─ loads ~/.vpn/hku.pass                                       │       then waits for OTP │
   ├─ fetches certificate pin                                     │                          │
   └─ docker run ────────────────────────────────────────────────► │  supervisord (daemon)    │
                                                                  │    ├─ SOCKS5 on :1080    │
 Surge (example local mixed-routing entry on :6152)              │    └─ HTTP   on :1088    │
   ├─ HKU rules (hku.hk, hku.edu.hk, library systems) ───────────► localhost:1080 / :1088   │
   └─ ChatGPT / Claude(Code) / other traffic ────────────────────► your normal proxy path    │
                                                                  │  tun0 ── VPN tunnel ───► │── HKU network
                                                                  └──────────────────────────┘
```

- **openconnect** connects to HKU's Cisco AnyConnect VPN inside an
  Alpine Linux container.
- **expect** automates the password prompt, then hands the terminal back
  to you for the Microsoft Authenticator OTP.
- **pproxy** (managed by supervisord) exposes the tunnel as SOCKS5 and
  HTTP proxies, mapped to `127.0.0.1` on your machine.
- In real mixed setups, tools like **Surge** can keep their own local
  entry (for example `127.0.0.1:6152`) for ChatGPT / Claude(Code), and
  only forward HKU domains to docker-vpn (`127.0.0.1:1080` / `:1088`).
- The expect script runs as PID 1 — pressing Ctrl+C stops the container
  and all child processes cleanly.

---

## Troubleshooting

### "Failed to fetch certificate from ..."

Your network can't reach that VPN endpoint. Try the other one:

```bash
hkuvpn cn    # if 'hk' failed
hkuvpn hk    # if 'cn' failed
```

Or manually write the pin to `~/.vpn/pin-{cn,hk}.cache` in the format
`pin-sha256:BASE64STRING`.

### "Login failed" after entering OTP

The OTP expired — they rotate every 30 seconds. Wait for a fresh code
in Microsoft Authenticator and try again.

### Port 1080 or 1088 already in use

Find what's using it:

```bash
lsof -i :1080
```

Then either stop that process, or set custom ports (see
[Custom Ports](#custom-ports)).

### "Colima not ready" keeps looping (macOS)

```bash
colima stop
colima start
```

If that doesn't help:

```bash
colima delete
colima start --cpu 2 --memory 2 --disk 20 --vm-type vz --mount-type virtiofs
```

### Container starts but proxy doesn't work

Make sure you're testing in a **different** terminal window — the VPN
terminal must stay open. Then verify the container is running:

```bash
docker ps | grep vpn-hku
```

### Certificate changed (rare)

If HKU rotates their VPN certificate, delete the cache and reconnect:

```bash
rm ~/.vpn/pin-*.cache
hkuvpn
```

---

## Security Notes

- `~/.vpn/hku.pass` stores your Portal PIN in **plaintext**. Enable
  full-disk encryption (FileVault on macOS, LUKS on Linux, BitLocker on
  Windows) to protect it at rest.
- The container requires `NET_ADMIN` capability and `/dev/net/tun` for
  the VPN tunnel. Proxies bind to `127.0.0.1` only — they are **not**
  exposed to your LAN.
- OTP entry is intentionally manual — that's the point of MFA.

---

## Credits & License

Forked from [ethack/docker-vpn](https://github.com/ethack/docker-vpn).
This edition strips it down to HKU-specific use, adds `expect`-based
MFA handling, replaces the SSH-based SOCKS proxy with pproxy, and
removes the embedded sshd.

Inherits the upstream license. See LICENSE.
