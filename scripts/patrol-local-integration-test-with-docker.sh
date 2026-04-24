#!/bin/bash

## Pre-requisites
# Install ngrok
# Install patrol CLI
# Open android emulator

# Stoping previous environment if any
killall ngrok || true
cd backend-docker
docker compose down || true
cd ..

# Forward traffic to tmail-backend
ngrok http http://localhost:80 --log=stdout >/dev/null &
until [[ $(curl localhost:4040/api/status | jq -r ".status") == "online" ]]; do
    echo "Waiting for ngrok to connect..."
    sleep 2
done

export BASIC_AUTH_URL=$(curl -s localhost:4040/api/tunnels | jq -r '.tunnels[0].public_url')

cd backend-docker

# Generate keys for tmail backend
echo "Generating keys for tmail-backend..."
openssl genpkey -algorithm rsa -pkeyopt rsa_keygen_bits:4096 -out jwt_privatekey
openssl rsa -in jwt_privatekey -pubout -out jwt_publickey

# Replace content of jmap.properties with url.prefix=$BASIC_AUTH_URL
# and websocket.url.prefix=ws${BASIC_AUTH_URL:4}
sed -i '' "s|url.prefix=.*|url.prefix=$BASIC_AUTH_URL|" jmap.properties
sed -i '' "s|websocket.url.prefix=.*|websocket.url.prefix=ws${BASIC_AUTH_URL:4}|" jmap.properties

echo "Starting services and adding users..."
docker compose up -d
# Wait till the service is started to add users
until (docker compose logs tmail-backend | grep -i "JAMES server started"); do
    echo "Waiting for tmail-backend to start..."
    sleep 2
done
export SHARD="${SHARD:-noProvision}"
export NUM_USERS="${NUM_USERS:-2}"
export DOMAIN="example.com"

# Map shard name to Patrol tag name (case statement for bash 3.x compatibility on macOS)
case "$SHARD" in
  noProvision)    PATROL_TAG="shardNoProvision" ;;
  searchEmails)   PATROL_TAG="shardSearchEmails" ;;
  preloadedEmails) PATROL_TAG="shardPreloadedEmails" ;;
  infra)          PATROL_TAG="shardInfra" ;;
  *) echo "Unknown SHARD: $SHARD. Valid: noProvision, searchEmails, preloadedEmails, infra"; exit 1 ;;
esac

SHARD="$SHARD" NUM_USERS="$NUM_USERS" DOMAIN="$DOMAIN" \
  docker exec tmail-backend ./root/conf/integration_test/provisioning.sh

cd ..

echo "Cleaning build cache to ensure fresh APK with current ngrok URL..."
flutter clean

echo "Building the app and running tests (shard=$SHARD tag=$PATROL_TAG)..."
patrol test -v \
    --tags="$PATROL_TAG" \
    --dart-define=BASIC_AUTH_URL="$BASIC_AUTH_URL" \
    --dart-define=DOMAIN="$DOMAIN" \
    --dart-define=SHARD="$SHARD"

# Clean up
echo "Cleaning up test environment..."
killall ngrok
cd backend-docker
docker compose down
cd ..