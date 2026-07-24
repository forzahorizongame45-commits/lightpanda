#!/bin/sh
# Generates an Ed25519 key pair for Lightpanda's Web Bot Auth support,
# and prints the JWK thumbprint (RFC 7638) to use as WEB_BOT_AUTH_KEYID.
#
# Run this once, locally -- not in the Dockerfile, not in CI.
#
# Usage:
#   ./generate-webbotauth-key.sh
#
# Output files (written to the current directory):
#   webbotauth-private.pem   -- upload as a Render Secret File, point
#                                WEB_BOT_AUTH_KEY_FILE at its mounted path.
#                                Never commit this file. Never put it in
#                                a plain env var.
#   webbotauth-public.pem    -- publish this per the Web Bot Auth spec
#                                (e.g. at the well-known path your domain
#                                needs to serve it from) so sites can
#                                verify your signature.
#
# Requires: openssl, python3 (both standard on macOS/Linux).

set -eu

OUT_DIR="${1:-.}"
PRIVATE_KEY="$OUT_DIR/webbotauth-private.pem"
PUBLIC_KEY="$OUT_DIR/webbotauth-public.pem"

if [ -e "$PRIVATE_KEY" ]; then
  echo "ERROR: $PRIVATE_KEY already exists -- refusing to overwrite an existing key." >&2
  echo "Delete it manually first if you really want to regenerate." >&2
  exit 1
fi

command -v openssl >/dev/null 2>&1 || { echo "ERROR: openssl not found." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 not found." >&2; exit 1; }

umask 077
openssl genpkey -algorithm ed25519 -out "$PRIVATE_KEY"
openssl pkey -in "$PRIVATE_KEY" -pubout -out "$PUBLIC_KEY"
chmod 600 "$PRIVATE_KEY"
chmod 644 "$PUBLIC_KEY"

KEYID=$(python3 - "$PUBLIC_KEY" <<'PYEOF'
import sys, subprocess, base64, hashlib, json

pub_path = sys.argv[1]
der = subprocess.run(
    ["openssl", "pkey", "-in", pub_path, "-pubin", "-outform", "DER"],
    capture_output=True, check=True,
).stdout

# The raw 32-byte Ed25519 public key is the last 32 bytes of the DER
# SubjectPublicKeyInfo structure.
raw_pub = der[-32:]
x = base64.urlsafe_b64encode(raw_pub).rstrip(b"=").decode()

# RFC 7638 JWK thumbprint: SHA-256 over the JSON object with only the
# required members, keys in lexicographic order, no whitespace.
jwk = {"crv": "Ed25519", "kty": "OKP", "x": x}
canonical = json.dumps(jwk, separators=(",", ":"), sort_keys=True).encode()
thumbprint = base64.urlsafe_b64encode(hashlib.sha256(canonical).digest()).rstrip(b"=").decode()

print(thumbprint)
PYEOF
)

echo ""
echo "Generated:"
echo "  private key : $PRIVATE_KEY  (chmod 600 -- upload as a Render Secret File)"
echo "  public key  : $PUBLIC_KEY   (publish this per the Web Bot Auth spec)"
echo ""
echo "Set these in Render:"
echo "  WEB_BOT_AUTH_KEYID=$KEYID"
echo "  WEB_BOT_AUTH_KEY_FILE=<path where you mount the Secret File, e.g. /etc/secrets/webbotauth-private.pem>"
echo "  WEB_BOT_AUTH_DOMAIN=<yourdomain.com>"
