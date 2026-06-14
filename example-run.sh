#!/bin/bash
set -euo pipefail

[[ -d output ]] || mkdir output
[[ -f output/cookie.txt ]] && rm output/cookie.txt

if [[ -z "${FORTI_VPN_PASSWORD:-}" ]]; then
    read -rsp "FORTI_VPN_PASSWORD is not set. Enter password: " FORTI_VPN_PASSWORD
    echo
fi
FORTI_VPN_HOST="${FORTI_VPN_HOST:-vpn.example.com}"
FORTI_VPN_USER="${FORTI_VPN_USER:-DOMAIN\username}"
FORTI_VPN_CLIENT_HOST="${FORTI_VPN_CLIENT_HOST:-192.168.1.100}"

PASS_FILE=$(mktemp)
chmod 600 "$PASS_FILE"
printf '%s' "$FORTI_VPN_PASSWORD" > "$PASS_FILE"
trap 'rm -f "$PASS_FILE"' EXIT

docker run --rm -it \
  -e FORTI_VPN_HOST="$FORTI_VPN_HOST" \
  -e FORTI_VPN_USER="$FORTI_VPN_USER" \
  -v "$(pwd)/output:/output" \
  -v "$PASS_FILE:/run/secrets/vpn_password:ro" \
  forti-cookie

[[ -f output/cookie.txt ]] \
    && echo "Cookie saved to output/cookie.txt" \
    || { echo "Failed to save cookie." && exit 1; }

COOKIE=$(cat output/cookie.txt)

ssh $FORTI_VPN_CLIENT_HOST "
  screen -dmS vpn bash -c 'sudo openfortivpn ${FORTI_VPN_HOST}:443 --username=\"${FORTI_VPN_USER}\" --cookie=\"${COOKIE}\" 2>&1 | tee /tmp/openfortivpn.log'
"

echo "VPN started in detached screen session on VM. Attach with: ssh $FORTI_VPN_CLIENT_HOST -t screen -r vpn"
