#!/bin/bash

# Test script for RFID webhook endpoint
# Usage: RFID=<rfid_value> KEY=<reader_key> [SERVER_URL=<url>] [PIN=<4_digit_pin>] ./test_rfid_webhook.sh

# Default values
SERVER_URL="${SERVER_URL:-http://localhost:3000}"
# Generate random 4-digit PIN if not provided (works on both Linux and macOS)
if [ -z "$PIN" ]; then
    PIN=$((1000 + RANDOM % 9000))
fi

# Check required environment variables
if [ -z "$RFID" ]; then
    echo "Error: RFID environment variable is required"
    echo "Usage: RFID=<rfid_value> KEY=<reader_key> [SERVER_URL=<url>] [PIN=<4_digit_pin>] $0"
    exit 1
fi

if [ -z "$KEY" ]; then
    echo "Error: KEY environment variable is required"
    echo "Usage: RFID=<rfid_value> KEY=<reader_key> [SERVER_URL=<url>] [PIN=<4_digit_pin>] $0"
    exit 1
fi

# Validate PIN is 4 digits
if ! [[ "$PIN" =~ ^[0-9]{4}$ ]]; then
    echo "Error: PIN must be exactly 4 digits"
    exit 1
fi

WEBHOOK_URL="${SERVER_URL}/webhooks/rfid"

echo "Testing RFID Webhook"
echo "==================="
echo "Server URL: $SERVER_URL"
echo "RFID: $RFID"
echo "Reader Key: $KEY"
echo "PIN: $PIN"
echo "Webhook URL: $WEBHOOK_URL"
echo ""

# Make the webhook request
echo "Sending webhook request..."
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "rfid=$RFID" \
    -d "pin=$PIN" \
    -d "key=$KEY")

# Extract response body and status code (works on both Linux and macOS)
HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
HTTP_BODY=$(echo "$RESPONSE" | sed '$d')

echo ""
echo "Response:"
echo "HTTP Status: $HTTP_CODE"

if [ "$HTTP_CODE" -eq 200 ]; then
    echo "✓ Webhook accepted successfully"
    echo ""
    echo "Next steps:"
    echo "1. Go to ${SERVER_URL}/login"
    echo "2. Click 'Sign In with Keyfob'"
    echo "3. Wait for the webhook to be detected"
    echo "4. Enter PIN: $PIN"
elif [ "$HTTP_CODE" -eq 401 ]; then
    echo "✗ Unauthorized - Invalid reader key"
    echo "Response body: $HTTP_BODY"
elif [ "$HTTP_CODE" -eq 403 ]; then
    echo "✗ Forbidden - IP not whitelisted"
    echo "Response body: $HTTP_BODY"
elif [ "$HTTP_CODE" -eq 400 ]; then
    echo "✗ Bad Request - Invalid parameters"
    echo "Response body: $HTTP_BODY"
else
    echo "✗ Error: Unexpected response"
    echo "Response body: $HTTP_BODY"
fi

exit 0

