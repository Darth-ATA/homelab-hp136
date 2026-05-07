#!/bin/bash
#
# run_api.sh - Script to authenticate with NPM API and fetch certificates
#
# Usage:
#   1. Copy .env.example to .env and fill in your credentials
#   2. Edit .env with your actual NPM credentials
#   3. Run: ./run_api.sh
#
# Note: Never commit .env to version control - it's in .gitignore
#

# Load environment variables from .env file
if [ -f .env ]; then
    source .env
else
    echo "Error: .env file not found!"
    echo "Copy .env.example to .env and configure your credentials first."
    exit 1
fi

# Validate required variables
if [ -z "$NPM_API_USER" ] || [ -z "$NPM_API_PASS" ]; then
    echo "Error: NPM_API_USER and NPM_API_PASS must be set in .env"
    exit 1
fi

# Login and get auth token
LOGIN_RESP=$(wget -qO- --post-data="{\"email\":\"$NPM_API_USER\",\"password\":\"$NPM_API_PASS\"}" --header='Content-Type: application/json' http://localhost:81/api/users/login)
echo "$LOGIN_RESP"
echo "---"

# Extract token from response
TOKEN=$(echo "$LOGIN_RESP" | grep -oP '"token":\s*"\K[^"]+' | head -1)
echo "TOKEN: $TOKEN"

# Fetch certificates using the token
CERT_RESP=$(wget -qO- --header="Authorization: Bearer $TOKEN" http://localhost:81/api/nginx/certificates)
echo "$CERT_RESP"