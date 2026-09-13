#!/bin/bash
# Creates a self-signed code-signing certificate in the login keychain.
#
# Why: macOS ties the Accessibility grant to an app's code signature. Ad-hoc signing
# (`codesign -s -`) has no identity — the signature is just a hash of the contents — so
# every rebuild looks like a different app and the permission has to be granted again.
# Signing with a stable certificate keeps the identity constant across rebuilds, so the
# permission is granted once.
#
# Run once. build-app.sh picks the certificate up automatically when it exists.
set -euo pipefail

IDENTITY="${SPACESWITCHER_IDENTITY:-SpaceSwitcher Self Signed}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  echo "Certificate \"$IDENTITY\" already exists — nothing to do."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/openssl.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions    = v3
prompt             = no
[ dn ]
CN = $IDENTITY
[ v3 ]
basicConstraints     = critical,CA:false
keyUsage             = critical,digitalSignature
extendedKeyUsage     = critical,codeSigning
EOF

echo "==> Generating certificate"
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/openssl.cnf" 2>/dev/null

# Two things Apple's Security framework is fussy about here:
#  - it cannot read OpenSSL 3's default PKCS#12 encryption (AES-256 with an SHA-256 MAC)
#    and fails with "MAC verification failed", so force legacy 3DES/SHA-1
#  - an empty passphrase fails the same way, so use a throwaway one
PASSPHRASE="spaceswitcher-import"
openssl pkcs12 -export -out "$WORK/bundle.p12" \
  -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -passout "pass:$PASSPHRASE" \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 2>/dev/null

echo "==> Importing into the login keychain"
# -T grants codesign access to the private key so signing does not prompt every build.
security import "$WORK/bundle.p12" -k "$KEYCHAIN" -P "$PASSPHRASE" -T /usr/bin/codesign >/dev/null

echo "==> Trusting it for code signing"
# Required: without trust the identity exists but reports CSSMERR_TP_NOT_TRUSTED and
# codesign refuses it. User-domain only — the system trust store is left alone.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem" 2>/dev/null \
  || echo "    (trust step failed — run it manually, see README)"

if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  echo
  echo "Done. \"$IDENTITY\" is ready; build-app.sh will use it automatically."
  echo "Grant Accessibility once more after the next build, and it will stick from then on."
else
  echo "error: the certificate was not registered as a code-signing identity" >&2
  exit 1
fi
