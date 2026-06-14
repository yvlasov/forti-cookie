# forti-cookie

Automates FortiGate SSL-VPN browser login and cookie extraction for use with `openfortivpn` CLI. Designed for portals that use Microsoft Authenticator push notifications (MFA) which are incompatible with direct `openfortivpn` authentication.

## Broader context

This tool is one component of a **multi-VPN access gateway** — a Linux cloud host that maintains simultaneous connections to multiple enterprise VPN environments in isolated Docker containers, each exposing a SOCKS5 proxy endpoint:

```
Workstation
    │
    │ WireGuard
    ▼
Cloud Host
    │
    ├── VPN Container A  (openfortivpn + dnsmasq + Dante SOCKS :1080)
    ├── VPN Container B  (openconnect  + dnsmasq + Dante SOCKS :1081)
    └── VPN Container C  (openvpn      + dnsmasq + Dante SOCKS :1082)
```

The workstation connects to the gateway over WireGuard and reaches each enterprise network via the appropriate SOCKS proxy (`socks5h://gateway:1080`, etc.). Container isolation provides independent routing tables, firewall rules, and DNS — so overlapping enterprise IP ranges and split-DNS zones never conflict.

`forti-cookie` solves the MFA bootstrap problem: it drives the browser login flow, obtains the `SVPNCOOKIE`, and hands it off to `openfortivpn` running inside the container.

## How it works

1. Playwright (headless Chromium) logs into the FortiGate SSL-VPN portal
2. Microsoft Authenticator push notification is triggered — approve on your phone
3. `SVPNCOOKIE` is extracted from the browser session and written to `output/cookie.txt`
4. Cookie is passed to `openfortivpn` running in a detached `screen` session on a remote VM via SSH

## Design notes

`forti-cookie` is a single-purpose brick in a wider automation system. It does one thing: obtain the `SVPNCOOKIE`. Error handling, retries, and orchestration are the responsibility of the calling system. No polish is intentional.

`example-run.sh` demonstrates how to invoke the Docker container and hand the cookie off to `openfortivpn` via SSH. It is not a production workflow — adapt it to your own orchestration. Security hardening of this script is out of scope; apply it in the calling system.

## Files

```
.
├── Dockerfile              # Playwright image with Python bindings
├── get_forti_cookie.py     # Playwright login + cookie extraction
└── example-run.sh          # Example orchestration: docker + SSH + screen
```

## Prerequisites

- Docker
- SSH access to the target VM (configured via `FORTI_VPN_CLIENT_HOST`)
- `openfortivpn` installed on the VM
- Passwordless `sudo` for `openfortivpn` on the VM, or adjust accordingly
- Microsoft Authenticator app on your phone

## Build

```bash
docker build -t forti-cookie .
```

## Usage

```bash
FORTI_VPN_PASSWORD='your-password' ./example-run.sh
```

If `FORTI_VPN_PASSWORD` is not set, the script will prompt for it (no echo). The password is written to a `mktemp` file (mode 600), mounted into the container as `/run/secrets/vpn_password`, and deleted on exit — it is never passed via `-e` flag, which would expose it in `docker inspect` and `ps aux`.

`get_forti_cookie.py` reads the password from `/run/secrets/vpn_password` first, falling back to the `FORTI_VPN_PASSWORD` env var.

Approve the push notification on your phone when prompted. The full flow takes ~30 seconds.

## Output

On success the container prints to stdout:

```
FORTI_VPN_COOKIE=<value>
```

The cookie is also written to `/output/cookie.txt` (requires a volume mount).

The calling system is expected to capture the stdout line to obtain the cookie value. All diagnostic messages are written to stderr and can be discarded.

## Configuration

| Variable                  | Default              | Description                        |
|---------------------------|----------------------|------------------------------------|
| `FORTI_VPN_HOST`          | `vpn.example.com`    | FortiGate hostname                 |
| `FORTI_VPN_USER`          | `DOMAIN\username`    | VPN username                       |
| `FORTI_VPN_PASSWORD`      | —                    | VPN password — passed via mounted file in `example-run.sh`, not `-e` flag |
| `FORTI_VPN_CLIENT_HOST`   | `192.168.1.100`      | SSH target VM running openfortivpn |
| `HEADLESS`                | `true`               | Run browser headless               |
| `DEBUG`                   | `false`              | Save screenshots at login and post-login to `/output/` |

To run with visible browser (debug):

```bash
HEADLESS=false FORTI_VPN_PASSWORD='your-password' ./example-run.sh
```

## Example VPN session on VM

The script starts `openfortivpn` in a named `screen` session called `vpn`. To inspect:

```bash
# Attach to session
ssh $FORTI_VPN_CLIENT_HOST -t screen -r vpn

# Or tail the log
ssh $FORTI_VPN_CLIENT_HOST tail -f /tmp/openfortivpn.log
```

To kill the VPN session:

```bash
ssh $FORTI_VPN_CLIENT_HOST screen -S vpn -X quit
```