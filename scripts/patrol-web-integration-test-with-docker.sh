#!/bin/bash

## Pre-requisites
# Install patrol CLI
echo "Installing patrol CLI..."
dart pub global activate patrol_cli 4.5.0

# Stop previous environment if any
cd backend-docker
docker compose down || true
cd ..

# Forward traffic to tmail-backend
export BASIC_AUTH_URL="http://localhost/"
export WEBSOCKET_URL="ws://localhost/"

cd backend-docker

# Generate keys for tmail backend
echo "Generating keys for tmail-backend..."
openssl genpkey -algorithm rsa -pkeyopt rsa_keygen_bits:4096 -out jwt_privatekey
openssl rsa -in jwt_privatekey -pubout -out jwt_publickey

# Replace jmap.properties URLs so James reports the correct public base URL
# in its JMAP session responses (the app uses these URLs for subsequent requests).
sed -i "s|url.prefix=.*|url.prefix=$BASIC_AUTH_URL|" jmap.properties
sed -i "s|websocket.url.prefix=.*|websocket.url.prefix=$WEBSOCKET_URL|" jmap.properties

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

echo "Copying integration_test/integration_test_env.file to env.file..."
cp integration_test/integration_test_env.file env.file

echo "Building the app and running tests (shard=$SHARD tag=$PATROL_TAG)..."
patrol test -v \
    --tags="$PATROL_TAG" \
    --device=chrome \
    --web-port=3000 \
    --web-headless=true \
    --web-browser-args='["--lang=en-US","--accept-lang=en-US,en"]' \
    --dart-define=BASIC_AUTH_URL="$BASIC_AUTH_URL" \
    --dart-define=DOMAIN="$DOMAIN" \
    --dart-define=SHARD="$SHARD"
TEST_EXIT_CODE=$?

# Clean up (runs regardless of test result)
echo "Cleaning up test environment..."
cd backend-docker
docker compose down
cd ..

exit $TEST_EXIT_CODE