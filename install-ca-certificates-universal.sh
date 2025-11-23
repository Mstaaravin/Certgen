#!/usr/bin/env bash
#
# Universal Certificate Installation Script for Custom CA
# Version: 1.0.0
# Description: Install custom CA certificates in multiple Linux distributions
# Supported: Debian/Ubuntu, RHEL/CentOS/Fedora/Oracle Linux, SUSE/openSUSE, Arch Linux
# Usage: ./install-ca-certificates-universal-clean-v1.0.0.sh
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
CA_DOMAIN=""  # Will be auto-detected or set via parameter
CA_DIR=""
INTERMEDIATE_DIR=""
URL_BASE=""  # Base URL for downloading certificates via HTTP
TEMP_DIR=""  # Temporary directory for downloaded certificates

# Distribution detection variables
DISTRO=""
DISTRO_FAMILY=""
PKG_MANAGER=""
SYSTEM_CA_PATH=""
UPDATE_COMMAND=""
INSTALL_COMMAND=""

# Non-interactive mode and additional flags
DRY_RUN=false
VERBOSE=false

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to display help message
show_help() {
    cat << EOF
Universal CA Certificate Installation Script v1.0.0

DESCRIPTION:
    Install custom CA certificates in the system trust store across multiple Linux distributions.
    Supports Debian/Ubuntu, RHEL/CentOS/Fedora/Oracle Linux, SUSE/openSUSE, and Arch Linux.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -d, --domain DOMAIN     Specify the CA domain name (e.g., marvin.ar)
    --url URL              Base URL (host only). The script auto-completes with /domains/DOMAIN/
                           Example: [URL] (will download from [URL]domains/DOMAIN/...)
    --list-domains          List available domains in the domains/ directory
    --dry-run              Show what would be done without making changes
    -v, --verbose          Enable verbose output

EXAMPLES:
    # Auto-detect domain (if only one exists)
    $0

    # Specify domain explicitly
    $0 -d marvin.ar

    # Download certificates from HTTP server (auto-completes path)
    $0 -d lan --url http://ip.lan
    # Downloads from: [URL]domains/lan/ca/ca.crt
    #                 [URL]domains/lan/intermediate/intermediate.crt
    #                 [URL]domains/lan/intermediate/ca-chain.crt

    # List available domains first
    $0 --list-domains

    # Dry run to see what would happen
    $0 -d marvin.ar --dry-run

REQUIREMENTS:
    - Run from directory containing 'domains/' folder OR use --url to download from HTTP
    - Domain directory must contain (local or via HTTP):
      └── domains/[DOMAIN]/
          ├── ca/ca.crt
          ├── intermediate/intermediate.crt
          └── intermediate/ca-chain.crt

    When using --url:
    - Provide only the base URL (e.g., [URL])
    - The script automatically appends: /domains/[DOMAIN]/ca/ca.crt
    - Example: --url [URL] -d mydom
      Downloads: [URL]domains/mydom/ca/ca.crt
                 [URL]domains/mydom/intermediate/intermediate.crt
                 [URL]domains/mydom/intermediate/ca-chain.crt

SUPPORTED DISTRIBUTIONS:
    - Debian/Ubuntu family (apt)
    - RHEL/CentOS/Fedora/Oracle Linux (yum/dnf)
    - SUSE/openSUSE (zypper)
    - Arch Linux (pacman)
    - Alpine Linux (apk)

NOTES:
    - Requires sudo privileges for system-wide installation
    - Creates automatic backups before making changes
    - Certificates will be installed in distribution-specific locations
    - Run verify-ca-installation script after installation to confirm success

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
            
            # Check if this looks like a valid certificate domain
            if [[ -f "${domain_path}ca/ca.crt" && -f "${domain_path}intermediate/intermediate.crt" ]]; then
                found_domains+=("$domain_name")
                domain_count=$((domain_count + 1))
                print_message $GREEN "  ✓ $domain_name (complete CA structure)"
                
                # Show certificate details
                local subject=$(openssl x509 -in "${domain_path}ca/ca.crt" -noout -subject 2>/dev/null | sed 's/subject=//' || echo "Unable to read subject")
                local expiry=$(openssl x509 -in "${domain_path}ca/ca.crt" -noout -enddate 2>/dev/null | sed 's/notAfter=//' || echo "Unable to read expiry")
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
        print_message $YELLOW "  domains/[DOMAIN]/intermediate/ca-chain.crt"
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
            
            # Check if this looks like a valid certificate domain
            if [[ -f "${domain_path}ca/ca.crt" && -f "${domain_path}intermediate/intermediate.crt" && -f "${domain_path}intermediate/ca-chain.crt" ]]; then
                valid_domains+=("$domain_name")
            fi
        fi
    done
    
    if [[ ${#valid_domains[@]} -eq 0 ]]; then
        print_message $RED "No valid certificate domains found in domains/ directory"
        print_message $YELLOW "Run '$0 --list-domains' to see available domains"
        print_message $YELLOW "Or create certificate structure using the certificate generator script"
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
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                ;;
            -d|--domain)
                if [[ -z "$2" ]]; then
                    print_message $RED "Error: --domain requires a domain name"
                    print_message $YELLOW "Usage: $0 -d DOMAIN_NAME"
                    exit 1
                fi
                CA_DOMAIN="$2"
                shift 2
                ;;
            --url)
                if [[ -z "$2" ]]; then
                    print_message $RED "Error: --url requires a URL"
                    print_message $YELLOW "Usage: $0 --url http://192.168.1.100"
                    exit 1
                fi
                URL_BASE="$2"
                # Remove trailing slash if present
                URL_BASE="${URL_BASE%/}"
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

# Function to download certificates from HTTP URL
download_certificates_from_url() {
    if [[ -z "$URL_BASE" ]]; then
        return 0  # No URL specified, skip download
    fi

    print_message $BLUE "Downloading certificates from: $URL_BASE"

    # Check for download tool (curl or wget)
    local DOWNLOAD_CMD=""
    if command -v curl &> /dev/null; then
        DOWNLOAD_CMD="curl"
    elif command -v wget &> /dev/null; then
        DOWNLOAD_CMD="wget"
    else
        print_message $RED "Error: Neither curl nor wget found"
        print_message $YELLOW "Please install curl or wget to download certificates"
        exit 1
    fi

    print_message $BLUE "Using download tool: $DOWNLOAD_CMD"

    # Create temporary directory
    TEMP_DIR=$(mktemp -d -t ca-certificates-XXXXXX)
    if [[ $? -ne 0 ]]; then
        print_message $RED "Error: Failed to create temporary directory"
        exit 1
    fi

    print_message $BLUE "Created temporary directory: $TEMP_DIR"

    # Create directory structure
    mkdir -p "${TEMP_DIR}/domains/${CA_DOMAIN}/ca"
    mkdir -p "${TEMP_DIR}/domains/${CA_DOMAIN}/intermediate"

    # Define files to download
    local files=(
        "domains/${CA_DOMAIN}/ca/ca.crt"
        "domains/${CA_DOMAIN}/intermediate/intermediate.crt"
        "domains/${CA_DOMAIN}/intermediate/ca-chain.crt"
    )

    # Download each file
    local download_failed=false
    for file in "${files[@]}"; do
        local url="${URL_BASE}/${file}"
        local dest="${TEMP_DIR}/${file}"

        print_message $BLUE "Downloading: $url"

        if [[ "$DOWNLOAD_CMD" == "curl" ]]; then
            if ! curl -f -sS -o "$dest" "$url"; then
                print_message $RED "✗ Failed to download: $url"
                download_failed=true
            else
                print_message $GREEN "✓ Downloaded: $(basename $file)"
            fi
        else  # wget
            if ! wget -q -O "$dest" "$url"; then
                print_message $RED "✗ Failed to download: $url"
                download_failed=true
            else
                print_message $GREEN "✓ Downloaded: $(basename $file)"
            fi
        fi
    done

    if [[ "$download_failed" == "true" ]]; then
        print_message $RED "Error: Failed to download one or more certificate files"
        print_message $YELLOW "Please check:"
        print_message $YELLOW "  1. The URL is correct and accessible: $URL_BASE"
        print_message $YELLOW "  2. The domain directory exists on the server: domains/${CA_DOMAIN}/"
        print_message $YELLOW "  3. The certificate files exist in the correct locations"
        cleanup_temp_dir
        exit 1
    fi

    print_message $GREEN "✓ All certificates downloaded successfully"
}

# Function to cleanup temporary directory
cleanup_temp_dir() {
    if [[ -n "$TEMP_DIR" ]] && [[ -d "$TEMP_DIR" ]]; then
        print_message $BLUE "Cleaning up temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
        print_message $GREEN "✓ Temporary files cleaned up"
    fi
}

# Function to set up domain paths after domain is determined
setup_domain_paths() {
    if [[ -z "$CA_DOMAIN" ]]; then
        print_message $RED "Error: No domain specified or detected"
        print_message $YELLOW "Use $0 --help for usage information"
        exit 1
    fi

    # Use TEMP_DIR if downloading from URL, otherwise use SCRIPT_DIR
    local base_dir="${TEMP_DIR:-$SCRIPT_DIR}"

    CA_DIR="${base_dir}/domains/${CA_DOMAIN}/ca"
    INTERMEDIATE_DIR="${base_dir}/domains/${CA_DOMAIN}/intermediate"

    print_message $BLUE "Using domain: $CA_DOMAIN"
    if [[ -n "$URL_BASE" ]]; then
        print_message $BLUE "Source: $URL_BASE (downloaded to temporary location)"
    else
        print_message $BLUE "Source: Local directory"
    fi
    print_message $BLUE "CA directory: $CA_DIR"
    print_message $BLUE "Intermediate directory: $INTERMEDIATE_DIR"
}

# Function to detect Linux distribution
detect_distribution() {
    print_message $BLUE "Detecting Linux distribution..."
    
    # Check for distribution-specific files and commands
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO="$ID"
        
        case "$ID" in
            debian|ubuntu|linuxmint|elementary|pop)
                DISTRO_FAMILY="debian"
                PKG_MANAGER="apt"
                SYSTEM_CA_PATH="/usr/local/share/ca-certificates"
                UPDATE_COMMAND="update-ca-certificates"
                INSTALL_COMMAND="apt update && apt install -y"
                ;;
            rhel|centos|fedora|almalinux|rocky|ol)
                DISTRO_FAMILY="redhat"
                PKG_MANAGER="yum"
                if command -v dnf &> /dev/null; then
                    PKG_MANAGER="dnf"
                fi
                SYSTEM_CA_PATH="/etc/pki/ca-trust/source/anchors"
                UPDATE_COMMAND="update-ca-trust"
                INSTALL_COMMAND="$PKG_MANAGER install -y"
                ;;
            opensuse*|sles|sled)
                DISTRO_FAMILY="suse"
                PKG_MANAGER="zypper"
                SYSTEM_CA_PATH="/etc/pki/trust/anchors"
                UPDATE_COMMAND="update-ca-certificates"
                INSTALL_COMMAND="zypper install -y"
                ;;
            arch|manjaro|endeavouros)
                DISTRO_FAMILY="arch"
                PKG_MANAGER="pacman"
                SYSTEM_CA_PATH="/etc/ca-certificates/trust-source/anchors"
                UPDATE_COMMAND="trust extract-compat"
                INSTALL_COMMAND="pacman -S --noconfirm"
                ;;
            alpine)
                DISTRO_FAMILY="alpine"
                PKG_MANAGER="apk"
                SYSTEM_CA_PATH="/usr/local/share/ca-certificates"
                UPDATE_COMMAND="update-ca-certificates"
                INSTALL_COMMAND="apk add"
                ;;
            *)
                print_message $YELLOW "Unknown distribution: $ID"
                print_message $YELLOW "Attempting to detect based on available commands..."
                detect_by_commands
                ;;
        esac
    else
        print_message $YELLOW "/etc/os-release not found. Detecting by available commands..."
        detect_by_commands
    fi
    
    print_message $GREEN "✓ Detected: $DISTRO ($DISTRO_FAMILY family)"
    print_message $BLUE "  Package Manager: $PKG_MANAGER"
    print_message $BLUE "  CA Path: $SYSTEM_CA_PATH"
    print_message $BLUE "  Update Command: $UPDATE_COMMAND"
}

# Function to detect distribution by available commands
detect_by_commands() {
    if command -v apt &> /dev/null; then
        DISTRO="debian-like"
        DISTRO_FAMILY="debian"
        PKG_MANAGER="apt"
        SYSTEM_CA_PATH="/usr/local/share/ca-certificates"
        UPDATE_COMMAND="update-ca-certificates"
        INSTALL_COMMAND="apt update && apt install -y"
    elif command -v dnf &> /dev/null; then
        DISTRO="redhat-like"
        DISTRO_FAMILY="redhat"
        PKG_MANAGER="dnf"
        SYSTEM_CA_PATH="/etc/pki/ca-trust/source/anchors"
        UPDATE_COMMAND="update-ca-trust"
        INSTALL_COMMAND="dnf install -y"
    elif command -v yum &> /dev/null; then
        DISTRO="redhat-like"
        DISTRO_FAMILY="redhat"
        PKG_MANAGER="yum"
        SYSTEM_CA_PATH="/etc/pki/ca-trust/source/anchors"
        UPDATE_COMMAND="update-ca-trust"
        INSTALL_COMMAND="yum install -y"
    elif command -v zypper &> /dev/null; then
        DISTRO="suse-like"
        DISTRO_FAMILY="suse"
        PKG_MANAGER="zypper"
        SYSTEM_CA_PATH="/etc/pki/trust/anchors"
        UPDATE_COMMAND="update-ca-certificates"
        INSTALL_COMMAND="zypper install -y"
    elif command -v pacman &> /dev/null; then
        DISTRO="arch-like"
        DISTRO_FAMILY="arch"
        PKG_MANAGER="pacman"
        SYSTEM_CA_PATH="/etc/ca-certificates/trust-source/anchors"
        UPDATE_COMMAND="trust extract-compat"
        INSTALL_COMMAND="pacman -S --noconfirm"
    elif command -v apk &> /dev/null; then
        DISTRO="alpine-like"
        DISTRO_FAMILY="alpine"
        PKG_MANAGER="apk"
        SYSTEM_CA_PATH="/usr/local/share/ca-certificates"
        UPDATE_COMMAND="update-ca-certificates"
        INSTALL_COMMAND="apk add"
    else
        print_message $RED "Unable to detect distribution or package manager"
        print_message $YELLOW "Supported distributions:"
        print_message $YELLOW "  - Debian/Ubuntu family (apt)"
        print_message $YELLOW "  - RHEL/CentOS/Fedora/Oracle Linux (yum/dnf)"
        print_message $YELLOW "  - SUSE/openSUSE (zypper)"
        print_message $YELLOW "  - Arch Linux (pacman)"
        print_message $YELLOW "  - Alpine Linux (apk)"
        exit 1
    fi
}

# Function to check and create CA directory
ensure_ca_directory() {
    if [[ ! -d "$SYSTEM_CA_PATH" ]]; then
        print_message $YELLOW "Creating CA certificates directory: $SYSTEM_CA_PATH"
        sudo mkdir -p "$SYSTEM_CA_PATH"
    fi
    
    if [[ ! -w "$SYSTEM_CA_PATH" ]] && [[ $EUID -ne 0 ]]; then
        print_message $YELLOW "Root privileges required for certificate installation"
        return 1
    fi
    
    return 0
}

# Function to install required tools based on distribution
install_required_tools() {
    print_message $BLUE "Checking for required tools..."
    
    local tools_needed=()
    
    # Check for openssl
    if ! command -v openssl &> /dev/null; then
        case "$DISTRO_FAMILY" in
            debian|alpine) tools_needed+=("openssl") ;;
            redhat) tools_needed+=("openssl") ;;
            suse) tools_needed+=("openssl") ;;
            arch) tools_needed+=("openssl") ;;
        esac
    fi
    
    # Check for ca-certificates package
    case "$DISTRO_FAMILY" in
        debian|alpine)
            if ! dpkg -l ca-certificates &> /dev/null && ! apk info ca-certificates &> /dev/null; then
                tools_needed+=("ca-certificates")
            fi
            ;;
        redhat)
            if ! rpm -q ca-certificates &> /dev/null; then
                tools_needed+=("ca-certificates")
            fi
            ;;
        suse)
            if ! rpm -q ca-certificates &> /dev/null; then
                tools_needed+=("ca-certificates")
            fi
            ;;
        arch)
            if ! pacman -Q ca-certificates &> /dev/null; then
                tools_needed+=("ca-certificates")
            fi
            ;;
    esac
    
    # Install missing tools
    if [[ ${#tools_needed[@]} -gt 0 ]]; then
        print_message $YELLOW "Installing required tools: ${tools_needed[*]}"
        sudo bash -c "$INSTALL_COMMAND ${tools_needed[*]}"
        print_message $GREEN "✓ Required tools installed"
    else
        print_message $GREEN "✓ All required tools are available"
    fi
}

# Function to verify certificate files exist
verify_certificates() {
    print_message $BLUE "Verifying certificate files..."
    
    local required_files=(
        "${CA_DIR}/ca.crt"
        "${INTERMEDIATE_DIR}/intermediate.crt"
        "${INTERMEDIATE_DIR}/ca-chain.crt"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            print_message $RED "Error: Required certificate file not found: $file"
            exit 1
        fi
        print_message $GREEN "✓ Found: $file"
    done
}

# Function to get certificate file extension based on distribution
get_cert_extension() {
    case "$DISTRO_FAMILY" in
        debian|alpine|suse) echo ".crt" ;;
        redhat|arch) echo ".pem" ;;
        *) echo ".crt" ;;
    esac
}

# Function to install CA certificates in system trust store
install_system_ca() {
    print_message $BLUE "Installing CA certificates in system trust store..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_message $YELLOW "[DRY RUN] Would install certificates to: $SYSTEM_CA_PATH"
        print_message $YELLOW "[DRY RUN] Would run: $UPDATE_COMMAND"
        return 0
    fi
    
    # Ensure CA directory exists and check permissions
    if ! ensure_ca_directory; then
        print_message $YELLOW "System installation requires sudo privileges."
        read -p "Do you want to install system-wide certificates? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_message $YELLOW "Skipping system installation."
            return 0
        fi
    fi
    
    local cert_ext=$(get_cert_extension)
    
    # Copy Root CA certificate
    local root_dest="${SYSTEM_CA_PATH}/${CA_DOMAIN}-root-ca${cert_ext}"
    sudo cp "${CA_DIR}/ca.crt" "$root_dest"
    print_message $GREEN "✓ Root CA certificate installed: $root_dest"
    
    # Copy Intermediate CA certificate
    local intermediate_dest="${SYSTEM_CA_PATH}/${CA_DOMAIN}-intermediate-ca${cert_ext}"
    sudo cp "${INTERMEDIATE_DIR}/intermediate.crt" "$intermediate_dest"
    print_message $GREEN "✓ Intermediate CA certificate installed: $intermediate_dest"
    
    # Set proper permissions
    sudo chmod 644 "$root_dest" "$intermediate_dest"
    
    # Update certificate store based on distribution
    print_message $BLUE "Updating system certificate store using: $UPDATE_COMMAND"
    
    case "$DISTRO_FAMILY" in
        debian|alpine|suse)
            sudo $UPDATE_COMMAND
            ;;
        redhat)
            sudo $UPDATE_COMMAND
            ;;
        arch)
            sudo $UPDATE_COMMAND
            ;;
    esac
    
    print_message $GREEN "✓ System certificate store updated successfully!"
}

# Function to verify system installation
verify_system_installation() {
    print_message $BLUE "Verifying system installation..."
    
    # Check if certificates are properly formatted
    local root_subject=$(openssl x509 -in "${CA_DIR}/ca.crt" -noout -subject)
    print_message $BLUE "  Root CA subject: $root_subject"
    
    # More flexible check for Root CA
    if echo "$root_subject" | grep -q "${CA_DOMAIN}" && echo "$root_subject" | grep -q "Root CA"; then
        print_message $GREEN "✓ Root CA certificate verified: $root_subject"
    else
        print_message $YELLOW "⚠ Root CA subject doesn't match expected pattern, but certificate exists"
        print_message $BLUE "  Expected pattern: Contains '${CA_DOMAIN}' and 'Root CA'"
        print_message $BLUE "  Actual subject: $root_subject"
    fi
    
    # Test certificate validation
    print_message $BLUE "Testing certificate chain validation..."
    if openssl verify -CAfile "${INTERMEDIATE_DIR}/ca-chain.crt" "${INTERMEDIATE_DIR}/intermediate.crt" >/dev/null 2>&1; then
        print_message $GREEN "✓ Certificate chain validation successful"
    else
        print_message $YELLOW "⚠ Certificate chain validation failed (this might be normal for self-signed CAs)"
    fi
    
    # Verify certificates are actually installed in system
    local cert_ext=$(get_cert_extension)
    local root_installed="${SYSTEM_CA_PATH}/${CA_DOMAIN}-root-ca${cert_ext}"
    local intermediate_installed="${SYSTEM_CA_PATH}/${CA_DOMAIN}-intermediate-ca${cert_ext}"
    
    if [[ -f "$root_installed" ]] && [[ -f "$intermediate_installed" ]]; then
        print_message $GREEN "✓ Certificates confirmed installed in system CA directory"
        
        # Check if certificates are readable
        if openssl x509 -in "$root_installed" -noout -subject >/dev/null 2>&1; then
            print_message $GREEN "✓ Installed Root CA certificate is readable"
        else
            print_message $YELLOW "⚠ Installed Root CA certificate has issues"
        fi
        
        if openssl x509 -in "$intermediate_installed" -noout -subject >/dev/null 2>&1; then
            print_message $GREEN "✓ Installed Intermediate CA certificate is readable"
        else
            print_message $YELLOW "⚠ Installed Intermediate CA certificate has issues"
        fi
    else
        print_message $RED "✗ Certificates not found in system CA directory"
        return 1
    fi
}

# Function to create backup
create_backup() {
    print_message $BLUE "Creating backup of current certificates..."
    
    local backup_dir="$HOME/.ca-certificates-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    local cert_ext=$(get_cert_extension)
    
    # Backup existing certificates if any
    local root_cert="${SYSTEM_CA_PATH}/${CA_DOMAIN}-root-ca${cert_ext}"
    local intermediate_cert="${SYSTEM_CA_PATH}/${CA_DOMAIN}-intermediate-ca${cert_ext}"
    
    if [[ -f "$root_cert" ]]; then
        sudo cp "$root_cert" "$backup_dir/" 2>/dev/null || true
    fi
    
    if [[ -f "$intermediate_cert" ]]; then
        sudo cp "$intermediate_cert" "$backup_dir/" 2>/dev/null || true
    fi
    
    print_message $GREEN "✓ Backup created in: $backup_dir"
}

# Function to show certificate information
show_certificate_info() {
    print_message $BLUE "Certificate Information:"
    print_message $YELLOW "========================"
    
    echo "Distribution: $DISTRO ($DISTRO_FAMILY family)"
    echo "Package Manager: $PKG_MANAGER"
    echo "CA Path: $SYSTEM_CA_PATH"
    echo "Update Command: $UPDATE_COMMAND"
    echo
    
    echo "Root CA Certificate:"
    openssl x509 -in "${CA_DIR}/ca.crt" -noout -subject -issuer -dates
    echo
    
    echo "Intermediate CA Certificate:"
    openssl x509 -in "${INTERMEDIATE_DIR}/intermediate.crt" -noout -subject -issuer -dates
    echo
}

# Function to provide post-installation instructions
show_post_install_instructions() {
    print_message $BLUE "Post-Installation Instructions:"
    print_message $YELLOW "==============================="
    
    echo "1. System certificates have been installed for: $DISTRO ($DISTRO_FAMILY)"
    echo "   - curl, wget, and other command-line tools should now trust your CA"
    echo "   - Most applications that use the system certificate store will work"
    echo
    
    case "$DISTRO_FAMILY" in
        debian|alpine)
            echo "2. For this distribution, certificates are stored in: $SYSTEM_CA_PATH"
            echo "   - Certificate bundle: /etc/ssl/certs/ca-certificates.crt"
            ;;
        redhat)
            echo "2. For Red Hat family distributions:"
            echo "   - Certificates stored in: $SYSTEM_CA_PATH"
            echo "   - Certificate bundle: /etc/pki/tls/certs/ca-bundle.crt"
            echo "   - Some applications may use: /etc/ssl/certs/ca-bundle.crt"
            ;;
        suse)
            echo "2. For SUSE distributions:"
            echo "   - Certificates stored in: $SYSTEM_CA_PATH"
            echo "   - Certificate bundle: /var/lib/ca-certificates/ca-bundle.pem"
            ;;
        arch)
            echo "2. For Arch Linux:"
            echo "   - Certificates stored in: $SYSTEM_CA_PATH"
            echo "   - Certificate bundle: /etc/ssl/certs/ca-certificates.crt"
            ;;
    esac
    
    echo
    echo "3. For Firefox, run the Firefox installation script:"
    echo "   ./install-firefox-certificates-universal-v1.0.0.sh"
    echo
    echo "4. To test the installation:"
    echo "   - curl -v https://your-domain (should not show certificate errors)"
    echo "   - openssl s_client -connect your-domain:443"
    echo
    echo "5. Certificate files locations:"
    local cert_ext=$(get_cert_extension)
    echo "   - Root CA: ${SYSTEM_CA_PATH}/${CA_DOMAIN}-root-ca${cert_ext}"
    echo "   - Intermediate: ${SYSTEM_CA_PATH}/${CA_DOMAIN}-intermediate-ca${cert_ext}"
    echo "   - Chain file: ${INTERMEDIATE_DIR}/ca-chain.crt"
    echo
}

# Main function
main() {
    print_message $GREEN "Universal CA Certificate Installation Script v1.0.0"
    print_message $GREEN "===================================================="
    echo

    # Set up trap to cleanup temporary files on exit or error
    trap cleanup_temp_dir EXIT INT TERM

    # Parse command line arguments first
    parse_arguments "$@"

    # If no domain specified and not using URL, try to auto-detect
    if [[ -z "$CA_DOMAIN" ]] && [[ -z "$URL_BASE" ]]; then
        auto_detect_domain
    fi

    # If using URL, domain is required
    if [[ -n "$URL_BASE" ]] && [[ -z "$CA_DOMAIN" ]]; then
        print_message $RED "Error: When using --url, you must specify --domain"
        print_message $YELLOW "Usage: $0 --url http://192.168.1.100 --domain marvin.ar"
        exit 1
    fi

    # Download certificates from URL if specified
    if [[ -n "$URL_BASE" ]]; then
        download_certificates_from_url
    fi

    # Set up domain paths
    setup_domain_paths

    # Detect distribution
    detect_distribution
    echo

    # Verify we're in the right directory and domain exists (skip if using URL)
    if [[ -z "$URL_BASE" ]] && [[ ! -d "domains/${CA_DOMAIN}" ]]; then
        print_message $RED "Error: Certificate directory 'domains/${CA_DOMAIN}' not found."
        print_message $YELLOW "Available options:"
        print_message $YELLOW "  1. Run '$0 --list-domains' to see available domains"
        print_message $YELLOW "  2. Use certificate generator to create certificates for this domain"
        print_message $YELLOW "  3. Ensure you're in the correct directory containing 'domains/' folder"
        print_message $YELLOW "  4. Use --url to download certificates from an HTTP server"
        exit 1
    fi
    
    # Install required tools
    install_required_tools
    
    # Verify certificate files
    verify_certificates
    
    # Show certificate information
    show_certificate_info
    
    # Create backup
    create_backup
    
    # Install system certificates
    install_system_ca
    
    # Verify installation
    verify_system_installation
    
    # Show post-installation instructions
    show_post_install_instructions
    
    print_message $GREEN "✓ CA certificate installation completed successfully on $DISTRO!"
}

# Call main function
main "$@"
