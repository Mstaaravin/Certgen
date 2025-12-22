#!/bin/bash

# Function to display help
display_help() {
    echo "Usage: $0 [certificate_file.crt]"
    echo ""
    echo "Checks the validity and details of an X.509 certificate."
    echo "If no file is provided, this help message is displayed."
    echo ""
    echo "Arguments:"
    echo "  certificate_file.crt   Path to the certificate file to check."
    echo ""
    echo "Options:"
    echo "  -h, --help             Display this help and exit."
    echo ""
    echo "Examples:"
    echo "  # Check a specific certificate file"
    echo "  $0 domains/lan/certs/minio.lan.crt"
    echo ""
    echo "  # Check a certificate from a different location"
    echo "  $0 /tmp/my_other_cert.pem"
    echo ""
    echo "  # Show this help message"
    echo "  $0 --help"
}

# Check if openssl is installed
if ! command -v openssl &> /dev/null
then
    echo "Error: openssl command not found. Please install openssl."
    exit 1
fi

# Check for no arguments or help flag
if [ -z "$1" ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    display_help
    exit 0
fi

CERT_FILE="$1"

# Validate if the file exists
if [ ! -f "$CERT_FILE" ]; then
    echo "Error: Certificate file '$CERT_FILE' not found."
    exit 1
fi

# --- Extract Certificate Information ---
CN=$(openssl x509 -in "$CERT_FILE" -subject -noout | sed -n '/CN=/s/.*CN=\([^/]*\).*/\1/p')
NOT_BEFORE=$(openssl x509 -in "$CERT_FILE" -dates -noout | grep 'notBefore' | cut -d= -f2)
NOT_AFTER=$(openssl x509 -in "$CERT_FILE" -dates -noout | grep 'notAfter' | cut -d= -f2)

# Convert dates to epoch for comparison
# Note: 'date -d' requires GNU date. On macOS, use 'gdate -d' or adjust.
# Assuming GNU date is available or it's a Linux system as specified in the setup.
NOT_BEFORE_EPOCH=$(date -d "$NOT_BEFORE" +%s)
NOT_AFTER_EPOCH=$(date -d "$NOT_AFTER" +%s)
CURRENT_EPOCH=$(date +%s)

CERT_STATUS="UNKNOWN"
if (( CURRENT_EPOCH >= NOT_BEFORE_EPOCH && CURRENT_EPOCH <= NOT_AFTER_EPOCH )); then
    CERT_STATUS="VALID"
elif (( CURRENT_EPOCH < NOT_BEFORE_EPOCH )); then
    CERT_STATUS="NOT YET VALID"
else
    CERT_STATUS="EXPIRED"
fi

# Extract SANs, clean up, and put into an array
# First, get the raw SAN string
SAN_RAW=$(openssl x509 -in "$CERT_FILE" -text -noout | awk '/X509v3 Subject Alternative Name:/{getline;print}' | sed 's/^[[:space:]]*//')

# Initialize an array for SANs
declare -a SAN_NAMES

# Split the raw SAN string by comma and process each entry
IFS=',' read -ra ADDR <<< "$SAN_RAW"
for i in "${ADDR[@]}"; do
    # Remove "DNS:" prefix and trim whitespace
    SAN_ENTRY=$(echo "$i" | sed -e 's/DNS://g' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    if [ -n "$SAN_ENTRY" ] && [ "$SAN_ENTRY" != "$CN" ]; then # Add if not empty and not the CN
        SAN_NAMES+=("$SAN_ENTRY")
    fi
done

echo "--------------------------------------------------"
echo "Certificate Details: $CERT_FILE"
echo "--------------------------------------------------"
echo "Validity:"
echo "  From: $NOT_BEFORE"
echo "  To:   $NOT_AFTER"
echo "  (Status: $CERT_STATUS)"
echo ""
echo "Registered Names:"
echo "  [Primary]   $CN"

for san_name in "${SAN_NAMES[@]}"; do
    echo "  [SAN]       $san_name"
done
echo "--------------------------------------------------"
