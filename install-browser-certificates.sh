#!/usr/bin/env bash
#
# Browser Certificate Installation Script for Custom CA
# Version: 1.0.0
# Description: Import custom CA certificates into the NSS database used by Chrome/Chromium
# Supported browsers: Google Chrome, Chromium (system package and snap)
# Usage: ./install-browser-certificates.sh [-d DOMAIN] [--dry-run] [-v]
#

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CA_DOMAIN=""
CA_DIR=""
INTERMEDIATE_DIR=""

# State
DRY_RUN=false
VERBOSE=false
CHROME_DETECTED=false
CHROMIUM_DETECTED=false
CHROMIUM_SNAP_DETECTED=false

# NSS database paths
NSSDB_PATH="$HOME/.pki/nssdb"
CHROMIUM_SNAP_NSSDB="$HOME/snap/chromium/current/.pki/nssdb"

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to display help message
show_help() {
    cat << EOF
Browser Certificate Installation Script (v1.0.0)

Imports custom CA certificates into the NSS database used by Chrome and Chromium.
Runs without root — operates only in the current user's NSS database (~/.pki/nssdb).
Requires: libnss3-tools (provides certutil). Will offer to install it if missing.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message.
    -d, --domain DOMAIN     Specify the CA domain (e.g., lan).
    --list-domains          List available local domains.
    --dry-run               Show what would be done, without making changes.
    -v, --verbose           Enable verbose output.

EXAMPLES:
    # Auto-detect domain (works when only one domain exists)
    $0

    # Install for a specific domain
    $0 -d lan

    # Preview what would be done
    $0 -d lan --dry-run

HOW IT WORKS:
    The script reads two certificate files:
    1. Root CA:      ./domains/[DOMAIN]/ca/ca.crt
    2. Intermediate: ./domains/[DOMAIN]/intermediate/intermediate.crt

    Both are imported into the shared NSS database at ~/.pki/nssdb,
    which is used by Google Chrome, Chromium, and other NSS-based applications.

NOTES:
    - Chrome and Chromium must be restarted after running this script.
    - For snap-installed Chromium, the snap NSS database is also updated if detected.
    - This script does NOT modify the system certificate store.
      Use install-ca-certificates-universal.sh for that.
EOF
    exit 0
}

# Function to list available domains
list_domains() {
    print_message $BLUE "Available domains in domains/ directory:"
    print_message $YELLOW "========================================"

    if [[ ! -d "domains" ]]; then
        print_message $RED "Error: 'domains' directory not found in current location"
        print_message $YELLOW "Please run this script from the directory containing the 'domains' folder"
        exit 1
    fi

    local found_domains=()
    local domain_count=0

    for domain_path in domains/*/; do
        if [[ -d "$domain_path" ]]; then
            local domain_name=$(basename "$domain_path")

            if [[ -f "${domain_path}ca/ca.crt" && -f "${domain_path}intermediate/intermediate.crt" ]]; then
                found_domains+=("$domain_name")
                domain_count=$((domain_count + 1))
                print_message $GREEN "  ✓ $domain_name (complete CA structure)"

                local subject
                subject=$(openssl x509 -in "${domain_path}ca/ca.crt" -noout -subject 2>/dev/null | sed 's/subject=//' || echo "Unable to read subject")
                local expiry
                expiry=$(openssl x509 -in "${domain_path}ca/ca.crt" -noout -enddate 2>/dev/null | sed 's/notAfter=//' || echo "Unable to read expiry")
                print_message $BLUE "    Subject: $subject"
                print_message $BLUE "    Expires: $expiry"
                echo
            else
                print_message $YELLOW "  ⚠ $domain_name (incomplete - missing required certificate files)"
            fi
        fi
    done

    if [[ $domain_count -eq 0 ]]; then
        print_message $RED "No valid certificate domains found."
        print_message $YELLOW "Each domain should have the structure:"
        print_message $YELLOW "  domains/[DOMAIN]/ca/ca.crt"
        print_message $YELLOW "  domains/[DOMAIN]/intermediate/intermediate.crt"
    else
        print_message $GREEN "Found $domain_count valid certificate domain(s)."
        print_message $BLUE "Use: $0 -d DOMAIN_NAME to install certificates for a specific domain"
    fi

    exit 0
}

# Function to auto-detect domain
auto_detect_domain() {
    print_message $BLUE "Auto-detecting CA domain..."

    if [[ ! -d "domains" ]]; then
        print_message $RED "Error: 'domains' directory not found"
        print_message $YELLOW "Please run this script from the directory containing the 'domains' folder"
        exit 1
    fi

    local valid_domains=()

    for domain_path in domains/*/; do
        if [[ -d "$domain_path" ]]; then
            local domain_name=$(basename "$domain_path")

            if [[ -f "${domain_path}ca/ca.crt" && -f "${domain_path}intermediate/intermediate.crt" ]]; then
                valid_domains+=("$domain_name")
            fi
        fi
    done

    if [[ ${#valid_domains[@]} -eq 0 ]]; then
        print_message $RED "No valid certificate domains found in domains/ directory"
        print_message $YELLOW "Run '$0 --list-domains' to see available domains"
        exit 1
    elif [[ ${#valid_domains[@]} -eq 1 ]]; then
        CA_DOMAIN="${valid_domains[0]}"
        print_message $GREEN "✓ Auto-detected domain: $CA_DOMAIN"
    else
        print_message $YELLOW "Multiple valid domains found:"
        for domain in "${valid_domains[@]}"; do
            print_message $YELLOW "  - $domain"
        done
        print_message $RED "Please specify domain explicitly using: $0 -d DOMAIN_NAME"
        print_message $BLUE "Or run '$0 --list-domains' for more details"
        exit 1
    fi
}

# Function to parse command line arguments
parse_arguments() {
    if [[ $# -eq 0 ]]; then
        show_help
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                ;;
            -d|--domain)
                if [[ -z "${2:-}" ]]; then
                    print_message $RED "Error: --domain requires a domain name"
                    print_message $YELLOW "Usage: $0 -d DOMAIN_NAME"
                    exit 1
                fi
                CA_DOMAIN="$2"
                shift 2
                ;;
            --list-domains)
                list_domains
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            *)
                print_message $RED "Unknown option: $1"
                print_message $YELLOW "Use $0 --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Function to set up domain paths
setup_domain_paths() {
    if [[ -z "$CA_DOMAIN" ]]; then
        print_message $RED "Error: No domain specified or detected"
        print_message $YELLOW "Use $0 --help for usage information"
        exit 1
    fi

    CA_DIR="${SCRIPT_DIR}/domains/${CA_DOMAIN}/ca"
    INTERMEDIATE_DIR="${SCRIPT_DIR}/domains/${CA_DOMAIN}/intermediate"

    if [[ "$VERBOSE" == "true" ]]; then
        print_message $BLUE "Using domain: $CA_DOMAIN"
        print_message $BLUE "CA directory: $CA_DIR"
        print_message $BLUE "Intermediate directory: $INTERMEDIATE_DIR"
    fi
}

# Function to verify certificate files exist
verify_certificates() {
    print_message $BLUE "Verifying certificate files..."

    local required_files=(
        "${CA_DIR}/ca.crt"
        "${INTERMEDIATE_DIR}/intermediate.crt"
    )

    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            print_message $RED "Error: Required certificate file not found: $file"
            print_message $YELLOW "Run '$0 --list-domains' to see available domains"
            exit 1
        fi
        print_message $GREEN "✓ Found: $file"
    done
}

# Function to check and install libnss3-tools if needed
check_install_libnss3() {
    print_message $BLUE "Checking for certutil (libnss3-tools)..."

    if command -v certutil &> /dev/null; then
        print_message $GREEN "✓ certutil is available"
        return 0
    fi

    print_message $YELLOW "certutil not found. It is provided by the libnss3-tools package."

    if [[ "$DRY_RUN" == "true" ]]; then
        print_message $YELLOW "[DRY RUN] Would install: sudo apt install -y libnss3-tools"
        return 0
    fi

    if ! command -v apt &> /dev/null; then
        print_message $RED "Error: apt not found. Please install libnss3-tools manually."
        print_message $YELLOW "  Ubuntu/Debian: sudo apt install -y libnss3-tools"
        print_message $YELLOW "  Fedora/RHEL:   sudo dnf install -y nss-tools"
        print_message $YELLOW "  Arch:          sudo pacman -S nss"
        exit 1
    fi

    print_message $YELLOW "Installing libnss3-tools via apt (requires sudo)..."
    sudo apt install -y libnss3-tools

    if ! command -v certutil &> /dev/null; then
        print_message $RED "Error: certutil still not available after installation"
        exit 1
    fi

    print_message $GREEN "✓ certutil installed successfully"
}

# Function to detect installed browsers
detect_browsers() {
    print_message $BLUE "Detecting installed browsers..."

    # Google Chrome
    if command -v google-chrome &> /dev/null || command -v google-chrome-stable &> /dev/null; then
        CHROME_DETECTED=true
        print_message $GREEN "✓ Google Chrome detected"
    fi

    # Chromium (system package)
    if command -v chromium &> /dev/null || command -v chromium-browser &> /dev/null; then
        CHROMIUM_DETECTED=true
        print_message $GREEN "✓ Chromium (system) detected"
    fi

    # Chromium snap
    if [[ -d "$HOME/snap/chromium" ]]; then
        CHROMIUM_SNAP_DETECTED=true
        print_message $GREEN "✓ Chromium (snap) detected"
    fi

    if [[ "$CHROME_DETECTED" == "false" && "$CHROMIUM_DETECTED" == "false" && "$CHROMIUM_SNAP_DETECTED" == "false" ]]; then
        print_message $YELLOW "⚠ No Chrome/Chromium installation detected"
        print_message $YELLOW "  The NSS database at ~/.pki/nssdb will still be updated."
        print_message $YELLOW "  Any browser or application using this NSS database will trust the CA."
    fi
}

# Function to ensure an NSS database exists at the given path
ensure_nssdb() {
    local db_path="$1"
    local db_label="$2"

    print_message $BLUE "Ensuring NSS database exists: $db_path"

    if [[ -d "$db_path" ]] && [[ -f "$db_path/cert9.db" || -f "$db_path/cert8.db" ]]; then
        print_message $GREEN "✓ NSS database already exists: $db_path"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        print_message $YELLOW "[DRY RUN] Would create NSS database: $db_path"
        return 0
    fi

    mkdir -p "$db_path"
    certutil -N -d "sql:${db_path}" --empty-password
    print_message $GREEN "✓ NSS database created: $db_path ($db_label)"
}

# Function to import certificates into an NSS database
import_into_nssdb() {
    local db_path="$1"
    local db_label="$2"

    print_message $BLUE "Importing certificates into $db_label..."

    local root_nickname="${CA_DOMAIN} Root CA"
    local intermediate_nickname="${CA_DOMAIN} Intermediate CA"

    if [[ "$DRY_RUN" == "true" ]]; then
        print_message $YELLOW "[DRY RUN] Would run:"
        print_message $YELLOW "  certutil -d \"sql:${db_path}\" -A -t \"CT,,\" -n \"${root_nickname}\" -i \"${CA_DIR}/ca.crt\""
        print_message $YELLOW "  certutil -d \"sql:${db_path}\" -A -t \"CT,,\" -n \"${intermediate_nickname}\" -i \"${INTERMEDIATE_DIR}/intermediate.crt\""
        return 0
    fi

    # Remove existing entries with same nickname to avoid duplicates
    if certutil -d "sql:${db_path}" -L 2>/dev/null | grep -q "^${root_nickname}"; then
        if [[ "$VERBOSE" == "true" ]]; then
            print_message $YELLOW "  Removing existing entry: ${root_nickname}"
        fi
        certutil -d "sql:${db_path}" -D -n "${root_nickname}" 2>/dev/null || true
    fi

    if certutil -d "sql:${db_path}" -L 2>/dev/null | grep -q "^${intermediate_nickname}"; then
        if [[ "$VERBOSE" == "true" ]]; then
            print_message $YELLOW "  Removing existing entry: ${intermediate_nickname}"
        fi
        certutil -d "sql:${db_path}" -D -n "${intermediate_nickname}" 2>/dev/null || true
    fi

    # Import Root CA
    certutil -d "sql:${db_path}" -A -t "CT,," -n "${root_nickname}" -i "${CA_DIR}/ca.crt"
    print_message $GREEN "✓ Root CA imported: ${root_nickname}"

    # Import Intermediate CA
    certutil -d "sql:${db_path}" -A -t "CT,," -n "${intermediate_nickname}" -i "${INTERMEDIATE_DIR}/intermediate.crt"
    print_message $GREEN "✓ Intermediate CA imported: ${intermediate_nickname}"
}

# Function to verify imported certificates
verify_import() {
    local db_path="$1"
    local db_label="$2"

    if [[ "$DRY_RUN" == "true" ]]; then
        print_message $YELLOW "[DRY RUN] Would verify: certutil -d \"sql:${db_path}\" -L | grep \"${CA_DOMAIN}\""
        return 0
    fi

    print_message $BLUE "Verifying certificates in $db_label..."

    local found
    found=$(certutil -d "sql:${db_path}" -L 2>/dev/null | grep "${CA_DOMAIN}" || true)

    if [[ -n "$found" ]]; then
        print_message $GREEN "✓ Certificates found in $db_label:"
        while IFS= read -r line; do
            print_message $GREEN "    $line"
        done <<< "$found"
    else
        print_message $RED "✗ Certificates NOT found in $db_label after import"
        return 1
    fi
}

# Function to process a single NSS database (ensure + import + verify)
process_nssdb() {
    local db_path="$1"
    local db_label="$2"

    echo
    print_message $BLUE "--- Processing: $db_label ($db_path) ---"

    ensure_nssdb "$db_path" "$db_label"

    if [[ "$DRY_RUN" == "false" ]] && [[ ! -d "$db_path" ]]; then
        print_message $RED "Error: NSS database directory not found after creation attempt: $db_path"
        return 1
    fi

    import_into_nssdb "$db_path" "$db_label"
    verify_import "$db_path" "$db_label"
}

# Function to show post-installation instructions
show_post_install() {
    echo
    print_message $BLUE "Post-Installation Instructions:"
    print_message $YELLOW "==============================="

    echo "The ${CA_DOMAIN} CA certificates have been imported into the NSS database."
    echo

    if [[ "$CHROME_DETECTED" == "true" ]]; then
        echo "  • Google Chrome: restart the browser to apply the new CA trust."
    fi
    if [[ "$CHROMIUM_DETECTED" == "true" ]]; then
        echo "  • Chromium (system): restart the browser to apply the new CA trust."
    fi
    if [[ "$CHROMIUM_SNAP_DETECTED" == "true" ]]; then
        echo "  • Chromium (snap): restart the browser to apply the new CA trust."
    fi
    if [[ "$CHROME_DETECTED" == "false" && "$CHROMIUM_DETECTED" == "false" && "$CHROMIUM_SNAP_DETECTED" == "false" ]]; then
        echo "  • Any browser or application using ~/.pki/nssdb will trust the CA"
        echo "    after it is restarted."
    fi

    echo
    echo "To verify the imported certificates manually:"
    echo "  certutil -d sql:\$HOME/.pki/nssdb -L | grep \"${CA_DOMAIN}\""
    echo
    echo "To verify the certificate chain with OpenSSL:"
    echo "  openssl verify -CAfile ${INTERMEDIATE_DIR}/ca-chain.crt \\"
    echo "    domains/${CA_DOMAIN}/certs/<hostname>.crt"
    echo
    echo "To install the CA in the system trust store (for curl, wget, etc.):"
    echo "  sudo ./install-ca-certificates-universal.sh -d ${CA_DOMAIN}"
    echo
}

# Main function
main() {
    print_message $GREEN "Browser Certificate Installation Script v1.0.0"
    print_message $GREEN "================================================"
    echo

    # Parse arguments (shows help and exits if no args provided)
    parse_arguments "$@"

    # Auto-detect domain if not specified
    if [[ -z "$CA_DOMAIN" ]]; then
        auto_detect_domain
    fi

    # Set up paths
    setup_domain_paths

    # Verify certificate source files exist
    verify_certificates
    echo

    # Ensure certutil is available
    check_install_libnss3
    echo

    # Detect installed browsers (informational)
    detect_browsers
    echo

    # Process the shared NSS database (Chrome, Chromium system, and most NSS apps)
    process_nssdb "$NSSDB_PATH" "shared NSS database (~/.pki/nssdb)"

    # Process snap Chromium NSS database if detected
    if [[ "$CHROMIUM_SNAP_DETECTED" == "true" ]]; then
        process_nssdb "$CHROMIUM_SNAP_NSSDB" "Chromium snap NSS database"
    fi

    echo
    print_message $GREEN "✓ Browser certificate installation completed successfully!"

    show_post_install
}

# Call main function
main "$@"
