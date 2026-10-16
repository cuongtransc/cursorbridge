#!/usr/bin/env bash
# Creates a self-signed code-signing identity for local builds, once.
#
# The Accessibility grant is tied to the app's designated requirement. Signed with this identity the
# requirement pins the certificate (`certificate leaf = H"…"`), so the grant survives rebuilds and no
# other binary can claim it without the private key. The certificate does not need to be trusted.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/signing.sh

KEYCHAIN="${1:-$(security default-keychain -d user | tr -d ' "')}"

if security find-identity -p codesigning "$KEYCHAIN" | grep -qF "\"$LOCAL_IDENTITY\""; then
    echo "Signing identity \"$LOCAL_IDENTITY\" already exists in $KEYCHAIN"
    exit 0
fi

umask 077
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat >"$WORK/cert.cnf" <<'EOF'
[req]
distinguished_name = dn
[dn]
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

PASS="$(openssl rand -hex 16)"
openssl req -x509 -newkey rsa:3072 -nodes -days 3650 -subj "/CN=$LOCAL_IDENTITY" \
    -config "$WORK/cert.cnf" -extensions ext -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
# macOS `security` only reads the legacy PKCS#12 encryption; LibreSSL has no -legacy flag and uses it anyway.
openssl pkcs12 -export -legacy -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -out "$WORK/id.p12" -passout "pass:$PASS" 2>/dev/null \
    || openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -out "$WORK/id.p12" -passout "pass:$PASS"
# Only codesign may use the key without asking; anything else gets a keychain prompt.
security import "$WORK/id.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null

echo "Created signing identity \"$LOCAL_IDENTITY\" in $KEYCHAIN"
echo "The first build may ask for your keychain password; choose Always Allow."
