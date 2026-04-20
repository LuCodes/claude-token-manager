#!/bin/bash
# Extract SPKI hash(es) from claude.ai's current certificate chain.
# Run this at build time to populate PinnedURLSessionDelegate.
#
# Usage: ./scripts/extract-spki-hash.sh

set -e

HOST="claude.ai"
PORT=443

echo "Fetching certificate chain for $HOST..."
echo ""

openssl s_client -connect "$HOST:$PORT" -servername "$HOST" -showcerts < /dev/null 2>/dev/null | \
  awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' | \
  awk -v n=0 '
    /-----BEGIN CERTIFICATE-----/ { n++; file = "/tmp/cert-" n ".pem" }
    { print > file }
  '

for cert in /tmp/cert-*.pem; do
  SUBJECT=$(openssl x509 -in "$cert" -noout -subject | sed 's/subject=//')
  HASH=$(openssl x509 -in "$cert" -pubkey -noout | \
         openssl pkey -pubin -outform der 2>/dev/null | \
         openssl dgst -sha256 -binary | \
         openssl base64)
  echo "Subject: $SUBJECT"
  echo "SPKI hash (SHA-256, base64): $HASH"
  echo ""
done

rm -f /tmp/cert-*.pem

echo "Copy the hash of the LEAF certificate (first one, usually claude.ai)"
echo "into PinnedURLSessionDelegate.pinnedSPKIHashes."
echo ""
echo "Also include the hash of the INTERMEDIATE cert for safety in case"
echo "the leaf rotates."
