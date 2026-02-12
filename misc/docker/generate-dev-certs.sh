#!/bin/sh
# Generate self-signed SSL certificates for local development
# Usage: ./generate-dev-certs.sh [domain]
# Default domain: microcrm.local

DOMAIN="${1:-microcrm.local}"
CERTS_DIR="$(dirname "$0")/../certs/dev"
mkdir -p "$CERTS_DIR"

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$CERTS_DIR/privkey.pem" \
  -out "$CERTS_DIR/fullchain.pem" \
  -subj "/CN=$DOMAIN/O=Dev/C=XX" \
  -addext "subjectAltName=DNS:$DOMAIN,DNS:localhost,IP:127.0.0.1"

echo "Generated certificates for $DOMAIN in $CERTS_DIR"
echo "Add to /etc/hosts: 127.0.0.1 $DOMAIN"
