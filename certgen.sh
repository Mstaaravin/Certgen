#!/usr/bin/env bash
#
# Copyright (c) 2025. All rights reserved.
#
# Name: generate_cert_with_intermediate.sh
# Version: 1.0.4
# Author: TuNombre
# Contributors: Developed with assistance from Claude AI
# Description: Certificate generator with hierarchical CA structure
#              (Root CA -> Intermediate CA -> Host certificates)
#              with wildcard certificate support
#              Compatible with OpenSSL 3.x
#
# =================================================================
# Certificate Generator with Intermediate CA
# =================================================================
#
# DESCRIPTION:
#   This script generates a complete certificate hierarchy:
#   Root CA -> Intermediate CA -> Host Certificate
#
#   It organizes certificates by domain in separate directories:
#   domains/[domain]/
#     ├── ca/                # Root CA files
#     ├── intermediate/      # Intermediate CA files
#     └── certs/             # Host certificates
#
# USAGE:
#   ./generate_cert_with_intermediate.sh [options]
#
# OPTIONS:
#   -h, --help                Show this help message
#   -d, --domain DOMAIN       Specify the domain (e.g., example.com)
#   -n, --hostname NAME       Specify the hostname (e.g., www or * for wildcard)
#   -a, --alt-names "N1 N2"   Specify alternative DNS names (space-separated)
#   --country CODE            Specify the country code (default: US)
#   --state STATE             Specify the state/province (default: State)
#   --city CITY               Specify the city (default: City)
#   --org ORG                 Specify the organization (default: Organization)
#   -y, --yes                 Non-interactive mode (use defaults)
#
# EXAMPLES:
#   # Interactive mode:
#   ./generate_cert_with_intermediate.sh
#
#   # Generate certificate for www.example.com non-interactively:
#   ./generate_cert_with_intermediate.sh -d example.com -n www -y
#
#   # Generate wildcard certificate for *.example.com:
#   ./generate_cert_with_intermediate.sh -d example.com -n "*" -y
#
#   # Generate certificate with alternative names:
#   ./generate_cert_with_intermediate.sh -d example.com -n www -a "api.example.com admin.example.com"
#
#   # Generate certificate with wildcard in alternative names:
#   ./generate_cert_with_intermediate.sh -d example.com -n www -a "*.example.com api.example.com"
#
# FILE DESCRIPTIONS:
#   - ca.key:             Root CA private key
#   - ca.crt:             Root CA certificate
#   - intermediate.key:   Intermediate CA private key
#   - intermediate.crt:   Intermediate CA certificate
#   - ca-chain.crt:       Chain of trust (intermediate + root)
#   - [host].key:         Host private key
#   - [host].crt:         Host certificate
#   - [host]-chain.crt:   Host certificate + intermediate + root
#   - [host]-fullchain.crt: Host certificate + intermediate + root
#
# NOTES:
#   - The ca-chain.crt file contains the intermediate certificate concatenated
#     with the root CA certificate. It's used to establish the chain of trust.
#   - Keep your CA private keys secure. The root CA key should ideally be
#     stored offline after initial creation.
#   - This script can create a complete CA infrastructure from scratch
#     or use existing CA files if found in the appropriate directory.
#   - Wildcard certificates (*.domain.com) can be created by specifying "*"
#     as the hostname or by including "*.domain.com" in alternative names.
#   - Compatible with OpenSSL 3.x
# =================================================================

# Script version
VERSION="1.0.3"

# Global variables for common data
COUNTRY="AR"
STATE="Buenos Aires"
CITY="CABA"
ROOT_ORG="Root CA Organization"
ROOT_OU="Root CA Org Unit"
INT_ORG="Intermediate Organization"
INT_OU="Intermediate Org Unit"
HOST_ORG="Host Organization"
HOST_OU="Host Org Unit"
ROOT_CN="Root CA"
INT_CN="Intermediate CA"
DEFAULT_DOMAIN="lan"

# Certificate durations (in days)
ROOT_CA_DAYS=3650    # 10 years
INT_CA_DAYS=1825     # 5 years
HOST_CERT_DAYS=825   # ~2 years

# Key sizes
ROOT_KEY_SIZE=4096
INT_KEY_SIZE=4096
HOST_KEY_SIZE=2048

# Base directory where all certificates will be stored
BASE_DIR="domains"

# Non-interactive mode flag
NON_INTERACTIVE=false

# Alternative DNS names (space-separated)
ALT_DNS_NAMES=""

# Error handling function
handle_error() {
    echo "ERROR: $1"
    exit 1
}

# Function to display help message
show_help() {
    cat << EOF
Certificate Generator with Intermediate CA (v${VERSION})
Usage: $0 [options]

Options:
  -h, --help                Show this help message
  -d, --domain DOMAIN       Specify the domain (e.g., example.com)
  -n, --hostname NAME       Specify the hostname (e.g., www or * for wildcard)
  -a, --alt-names "N1 N2"   Specify alternative DNS names (space-separated)
  --country CODE            Specify the country code (default: ${COUNTRY})
  --state STATE             Specify the state/province (default: ${STATE})
  --city CITY               Specify the city (default: ${CITY})
  --org ORG                 Specify the organization (default: Host Organization)
  -y, --yes                 Non-interactive mode (use defaults)

Examples:
  # Interactive mode:
  $0

  # Generate certificate for www.example.com non-interactively:
  $0 -d example.com -n www -y

  # Generate wildcard certificate for *.example.com:
  $0 -d example.com -n "*" -y

  # Generate certificate with alternative names:
  $0 -d example.com -n www -a "api.example.com admin.example.com"
EOF
    exit 0
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                ;;
            -d|--domain)
                DOMAIN="$2"
                shift 2
                ;;
            -n|--hostname)
                HOST_NAME="$2"
                shift 2
                ;;
            -a|--alt-names)
                ALT_DNS_NAMES="$2"
                shift 2
                ;;
            --country)
                COUNTRY="$2"
                shift 2
                ;;
            --state)
                STATE="$2"
                shift 2
                ;;
            --city)
                CITY="$2"
                shift 2
                ;;
            --org)
                HOST_ORG="$2"
                shift 2
                ;;
            -y|--yes)
                NON_INTERACTIVE=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                ;;
        esac
    done
}

# Function to check if a file exists
check_file_exists() {
    if [ ! -f "$1" ]; then
        handle_error "The file $1 does not exist."
    fi
}

# Function to create directory if it doesn't exist
create_dir_if_not_exists() {
    if [ ! -d "$1" ]; then
        mkdir -p "$1"
        echo "Directory created: $1"
    fi
}

# Function to handle wildcard certificate names
format_wildcard_name() {
    local name="$1"
    local domain="$2"

    # If it's just a '*', turn it into a proper wildcard for the domain
    if [[ "$name" == "*" ]]; then
        echo "*.${domain}"
    # If it already starts with '*.' (e.g. *.subdomain), keep it as is
    elif [[ "$name" == "*."* ]]; then
        echo "$name"
    # If it's a single '*' with trailing text but no dot (e.g. *api), format as wildcard
    elif [[ "$name" == "*"* && "$name" != "*."* ]]; then
        echo "*.${domain}"
    else
        echo "$name"
    fi
}

# Request domain information
request_domain() {
    if [ -z "$DOMAIN" ]; then
        if [ "$NON_INTERACTIVE" = true ]; then
            DOMAIN="$DEFAULT_DOMAIN"
            echo "Using default domain: ${DOMAIN}"
        else
            # Request domain name for organization
            read -p "Enter the domain name for the CA organization (default: ${DEFAULT_DOMAIN}): " DOMAIN
            DOMAIN=${DOMAIN:-$DEFAULT_DOMAIN}
        fi
    fi

    # Set domain-specific directories
    DOMAIN_DIR="${BASE_DIR}/${DOMAIN}"
    CA_DIR="${DOMAIN_DIR}/ca"
    INT_DIR="${DOMAIN_DIR}/intermediate"
    CERTS_DIR="${DOMAIN_DIR}/certs"

    # Create domain-specific directories
    create_dir_if_not_exists "${CA_DIR}"
    create_dir_if_not_exists "${INT_DIR}"
    create_dir_if_not_exists "${CERTS_DIR}"

    echo "Using domain: ${DOMAIN}"
    echo "Domain directory: ${DOMAIN_DIR}"
}

# Generate Root CA if it doesn't exist
generate_root_ca() {
    if [ ! -f "${CA_DIR}/ca.key" ] || [ ! -f "${CA_DIR}/ca.crt" ]; then
        echo "Generating Root CA certificate for domain ${DOMAIN}..."

        # Create CA configuration file
        cat > ${CA_DIR}/ca.conf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_ca
x509_extensions = v3_ca
prompt = no

[req_distinguished_name]
C = ${COUNTRY}
ST = ${STATE}
L = ${CITY}
O = ${ROOT_ORG}
OU = ${ROOT_OU}
CN = ${ROOT_CN}.${DOMAIN}

[v3_ca]
subjectKeyIdentifier = hash
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
EOF

        # Generate CA private key
        openssl genpkey -algorithm RSA -out ${CA_DIR}/ca.key -outform PEM -pkeyopt rsa_keygen_bits:${ROOT_KEY_SIZE} || \
            handle_error "Failed to generate root CA private key"
        chmod 400 ${CA_DIR}/ca.key

        # Generate self-signed CA certificate
        openssl req -new -x509 -days ${ROOT_CA_DAYS} -key ${CA_DIR}/ca.key -out ${CA_DIR}/ca.crt -config ${CA_DIR}/ca.conf || \
            handle_error "Failed to generate root CA certificate"

        # Verify the certificate was created
        check_file_exists "${CA_DIR}/ca.crt"

        echo "Root CA certificate generated:"
        echo "- Private key: ${CA_DIR}/ca.key"
        echo "- Certificate: ${CA_DIR}/ca.crt"
    else
        echo "CA files for domain ${DOMAIN} already exist, using existing ones."
    fi
}

# Generate Intermediate CA if it doesn't exist
generate_intermediate_ca() {
    if [ ! -f "${INT_DIR}/intermediate.key" ] || [ ! -f "${INT_DIR}/intermediate.crt" ]; then
        echo "Generating Intermediate CA certificate for domain ${DOMAIN}..."

        # Create Intermediate CA configuration file
        cat > ${INT_DIR}/intermediate.conf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_ca
prompt = no

[req_distinguished_name]
C = ${COUNTRY}
ST = ${STATE}
L = ${CITY}
O = ${INT_ORG}
OU = ${INT_OU}
CN = ${INT_CN}.${DOMAIN}

[v3_ca]
subjectKeyIdentifier = hash
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
EOF

        # Create Intermediate CA extension file for signing
        cat > ${INT_DIR}/intermediate_ext.conf <<EOF
[ v3_intermediate_ca ]
subjectKeyIdentifier = hash
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
EOF

        # Generate Intermediate CA private key
        openssl genpkey -algorithm RSA -out ${INT_DIR}/intermediate.key -outform PEM -pkeyopt rsa_keygen_bits:${INT_KEY_SIZE} || \
            handle_error "Failed to generate intermediate CA private key"
        chmod 400 ${INT_DIR}/intermediate.key

        # Generate Intermediate CA CSR
        openssl req -new -key ${INT_DIR}/intermediate.key -out ${INT_DIR}/intermediate.csr -config ${INT_DIR}/intermediate.conf || \
            handle_error "Failed to generate intermediate CA CSR"

        # Sign Intermediate CA CSR with Root CA
        openssl x509 -req -in ${INT_DIR}/intermediate.csr \
            -CA ${CA_DIR}/ca.crt -CAkey ${CA_DIR}/ca.key -CAcreateserial \
            -out ${INT_DIR}/intermediate.crt -days ${INT_CA_DAYS} -sha256 \
            -extfile ${INT_DIR}/intermediate_ext.conf -extensions v3_intermediate_ca || \
            handle_error "Failed to sign intermediate CA certificate"

        # Verify the certificate was created
        check_file_exists "${INT_DIR}/intermediate.crt"

        # Create certificate chain file (intermediate + root)
        cat ${INT_DIR}/intermediate.crt ${CA_DIR}/ca.crt > ${INT_DIR}/ca-chain.crt || \
            handle_error "Failed to create certificate chain"

        echo "Intermediate CA certificate generated:"
        echo "- Private key: ${INT_DIR}/intermediate.key"
        echo "- Certificate: ${INT_DIR}/intermediate.crt"
        echo "- Certificate chain: ${INT_DIR}/ca-chain.crt"
    else
        echo "Intermediate CA files for domain ${DOMAIN} already exist, using existing ones."
    fi
}

# Generate host certificate
generate_host_certificate() {
    if [ -z "$HOST_NAME" ]; then
        if [ "$NON_INTERACTIVE" = true ]; then
            handle_error "Hostname is required in non-interactive mode. Use -n or --hostname to specify a hostname"
        else
            # Request hostname
            read -p "Enter the hostname (example: host01, or * for wildcard): " HOST_NAME
            if [ -z "$HOST_NAME" ]; then
                handle_error "Hostname cannot be empty"
            fi
        fi
    fi

    # Build the FQDN with special handling for wildcards
    if [[ "$HOST_NAME" == "*" || "$HOST_NAME" == "*."* ]]; then
        # Handle wildcard certificate
        FQDN=$(format_wildcard_name "$HOST_NAME" "$DOMAIN")
        echo "Generating wildcard certificate for $FQDN..."
    elif [[ "$HOST_NAME" == *"."* ]]; then
        # If user entered a complete FQDN, use it as is
        FQDN=$HOST_NAME
    else
        # Otherwise, combine hostname with domain
        FQDN="${HOST_NAME}.${DOMAIN}"
    fi

    # Normalize filename for wildcards (replace * with 'wildcard')
    CERT_FILENAME=$(echo "${FQDN}" | sed 's/\*\./wildcard./g')

    echo "Generating certificate for $FQDN..."

    # Create host configuration file
    cat > ${CERTS_DIR}/${CERT_FILENAME}.conf <<EOF
[req]
default_bits = ${HOST_KEY_SIZE}
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext

[dn]
C = ${COUNTRY}
ST = ${STATE}
L = ${CITY}
O = ${HOST_ORG}
OU = ${HOST_OU}
CN = ${FQDN}

[req_ext]
subjectAltName = @alt_names
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth

[alt_names]
DNS.1 = ${FQDN}
EOF

    # Add additional DNS names if needed
    DNS_COUNT=2

    # First check command-line provided alternative names
    if [ ! -z "$ALT_DNS_NAMES" ]; then
        for ALT_DNS in $ALT_DNS_NAMES; do
            # Handle wildcards in alternative names
            if [[ "$ALT_DNS" == "*" ]]; then
                ALT_DNS="*.${DOMAIN}"
                echo "Converting wildcard to: $ALT_DNS"
            elif [[ "$ALT_DNS" == "*."* ]]; then
                # Already a properly formatted wildcard, keep as is
                :
            fi

            echo "DNS.$DNS_COUNT = $ALT_DNS" >> ${CERTS_DIR}/${CERT_FILENAME}.conf
            DNS_COUNT=$((DNS_COUNT+1))
        done
    elif [ "$NON_INTERACTIVE" = false ]; then
        # Ask for alternative names if in interactive mode
        read -p "Do you want to add alternative DNS names? (y/n): " ADD_DNS
        if [[ "$ADD_DNS" =~ ^[Yy]$ ]]; then
            while true; do
                read -p "Enter alternative DNS name ($DNS_COUNT) or leave empty to finish: " ALT_DNS
                if [ -z "$ALT_DNS" ]; then
                    break
                fi

                # Handle wildcards in alternative names
                if [[ "$ALT_DNS" == "*" ]]; then
                    ALT_DNS="*.${DOMAIN}"
                    echo "Converting wildcard to: $ALT_DNS"
                elif [[ "$ALT_DNS" == "*"* && "$ALT_DNS" != "*."* ]]; then
                    # Handle case where user enters *something without a dot
                    ALT_DNS="*.${DOMAIN}"
                    echo "Converting to proper wildcard format: $ALT_DNS"
                fi

                echo "DNS.$DNS_COUNT = $ALT_DNS" >> ${CERTS_DIR}/${CERT_FILENAME}.conf
                DNS_COUNT=$((DNS_COUNT+1))
            done
        fi
    fi

    # Generate host private key
    openssl genpkey -algorithm RSA -out ${CERTS_DIR}/${CERT_FILENAME}.key -outform PEM -pkeyopt rsa_keygen_bits:${HOST_KEY_SIZE} || \
        handle_error "Failed to generate host private key"
    chmod 400 ${CERTS_DIR}/${CERT_FILENAME}.key
    echo "Private key generated: ${CERTS_DIR}/${CERT_FILENAME}.key"

    # Generate host CSR
    openssl req -new -key ${CERTS_DIR}/${CERT_FILENAME}.key -out ${CERTS_DIR}/${CERT_FILENAME}.csr -config ${CERTS_DIR}/${CERT_FILENAME}.conf || \
        handle_error "Failed to generate CSR"
    echo "CSR generated: ${CERTS_DIR}/${CERT_FILENAME}.csr"

    # Verify intermediate cert exists
    check_file_exists "${INT_DIR}/intermediate.crt"
    check_file_exists "${INT_DIR}/intermediate.key"

    # Sign host CSR with Intermediate CA
    openssl x509 -req -in ${CERTS_DIR}/${CERT_FILENAME}.csr \
        -CA ${INT_DIR}/intermediate.crt -CAkey ${INT_DIR}/intermediate.key \
        -CAcreateserial -out ${CERTS_DIR}/${CERT_FILENAME}.crt -days ${HOST_CERT_DAYS} \
        -sha256 -extfile ${CERTS_DIR}/${CERT_FILENAME}.conf -extensions req_ext || \
        handle_error "Failed to sign host certificate"

    # Verify the certificate was created
    check_file_exists "${CERTS_DIR}/${CERT_FILENAME}.crt"
    echo "Certificate signed: ${CERTS_DIR}/${CERT_FILENAME}.crt"

    # Create complete certificate chain file
    cat ${CERTS_DIR}/${CERT_FILENAME}.crt ${INT_DIR}/intermediate.crt ${CA_DIR}/ca.crt > ${CERTS_DIR}/${CERT_FILENAME}-fullchain.crt || \
        handle_error "Failed to create full certificate chain"
    echo "Full certificate chain generated: ${CERTS_DIR}/${CERT_FILENAME}-fullchain.crt"

    # Create server certificate bundle (for services that need certificate + chain)
    #cat ${CERTS_DIR}/${CERT_FILENAME}.crt ${INT_DIR}/ca-chain.crt > ${CERTS_DIR}/${CERT_FILENAME}-chain.crt || \
    #    handle_error "Failed to create certificate with chain"
    #echo "Certificate with chain generated: ${CERTS_DIR}/${CERT_FILENAME}-chain.crt"

    echo "Process completed! Key files are:"
    echo "- Private key: ${CERTS_DIR}/${CERT_FILENAME}.key"
    echo "- Certificate: ${CERTS_DIR}/${CERT_FILENAME}.crt"
    echo "- Certificate with intermediate chain: ${CERTS_DIR}/${CERT_FILENAME}-chain.crt"
    echo "- Full chain (host + intermediate + CA): ${CERTS_DIR}/${CERT_FILENAME}-fullchain.crt"
}

# Main execution flow
main() {
    echo "=== Certificate Generator with CA → Intermediate → Host hierarchy v${VERSION} ==="

    # Parse command-line arguments
    parse_arguments "$@"

    echo "This script will generate certificates organized by domain"
    echo "Each domain will have its own CA and certificates structure"
    echo "==========================================================="

    # Request domain and set up directory structure
    create_dir_if_not_exists "${BASE_DIR}"
    request_domain

    # Generate or use existing CA
    generate_root_ca

    # Generate or use existing Intermediate CA
    generate_intermediate_ca

    # Generate host certificate
    generate_host_certificate

    echo "All certificates have been generated in the ${DOMAIN_DIR} directory"
}

# Call main function with all command line parameters
main "$@"
