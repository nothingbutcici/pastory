#!/usr/bin/env bash
# One-time: create a self-signed code-signing identity "Pastory Dev" in the login
# keychain so rebuilds keep a stable signature (and the Screen Recording grant survives).
set -euo pipefail
NAME="${1:-Pastory Dev}"
KC="$HOME/Library/Keychains/login.keychain-db"
if security find-identity -v -p codesigning "$KC" 2>/dev/null | grep -q "\"$NAME\""; then
    echo "identity '$NAME' already exists"; exit 0
fi
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/ext.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $NAME
[v3]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
subjectKeyIdentifier = hash
CNF
openssl req -x509 -newkey rsa:2048 -days 3650 -nodes -config "$TMP/ext.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" >/dev/null 2>&1
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:snipclip 2>/dev/null \
 || openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:snipclip
security import "$TMP/id.p12" -k "$KC" -P snipclip -T /usr/bin/codesign -T /usr/bin/security >/dev/null
# Trust it for code signing (user trust domain; macOS may ask for your password once).
security add-trusted-cert -r trustRoot -p codeSign -k "$KC" "$TMP/cert.pem"
security find-identity -v -p codesigning "$KC" | grep "$NAME" || { echo "identity not usable"; exit 1; }
echo "created identity '$NAME'"
