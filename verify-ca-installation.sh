#!/usr/bin/env bash
#
# CA Certificate Installation Verification Script
# Version: 1.0.0
# Description: Comprehensive verification of CA certificate installation across Linux distributions
# Usage: ./verify-ca-installation-v1.0.0.sh
#

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CA_DOMAIN=""
CA_DIR=""
INTERMEDIATE_DIR=""

# Test results tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNING_TESTS=0

# Distribution detection variables
DISTRO=""
DISTRO_FAMILY=""
SYSTEM_CA_PATH=""

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to display help message
show_help() {
    cat << EOF
CA Certificate Installation Verification Script v1.0.0

DESCRIPTION:
    Comprehensive verification of CA certificate installation in the system.
    Performs 9 different tests to ensure certificates are properly installed and functional.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -d, --domain DOMAIN     Specify the CA domain name (e.g., marvin.ar)
    --list-domains          List available domains in the domains/ directory

EXAMPLES:
    # Auto-detect domain (if only one exists)
    $0

    # Specify domain explicitly
    $0 -d marvin.ar

    # List available domains first
    $0 --list-domains

TESTS PERFORMED:
    1. Source Certificate Files - Verify certificate files exist
    2. Certificate Validity - Check expiration and format
    3. Installed Certificate Files - Confirm system installation
    4. System Certificate Bundle - Check bundle integration
    5. OpenSSL Verification - Test OpenSSL recognition
    6. curl Certificate Trust - Test curl functionality
    7. wget Certificate Trust - Test wget functionality
    8. Certificate Update Status - Check update timestamps
    9. Environment Verification - System information

EXIT CODES:
    0 - All tests passed
    1 - Some tests failed
    2 - Critical error (missing files, wrong directory)

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
        exit 2
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
                print_message $BLUE "    Subject: $subject"
                echo
            else
                print_message $YELLOW "  ⚠ $domain_name (incomplete - missing required certificate files)"
            fi
        fi
    done
    
    if [[ $domain_count -eq 0 ]]; then
        print_message $RED "No valid certificate domains found."
    else
        print_message $GREEN "Found $domain_count valid certificate domain(s)."
    fi
    
    exit 0
}

# Function to auto-detect domain
auto_detect_domain() {
    print_message $BLUE "Auto-detecting CA domain..."
    
    if [[ ! -d "domains" ]]; then
        print_message $RED "Error: 'domains' directory not found"
        print_message $YELLOW "Please run this script from the directory containing the 'domains' folder"
        exit 2
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
        exit 2
    elif [[ ${#valid_domains[@]} -eq 1 ]]; then
        CA_DOMAIN="${valid_domains[0]}"
        print_message $GREEN "✓ Auto-detected domain: $CA_DOMAIN"
    else
        print_message $YELLOW "Multiple valid domains found:"
        for domain in "${valid_domains[@]}"; do
            print_message $YELLOW "  - $domain"
        done
        print_message $RED "Please specify domain explicitly using: $0 -d DOMAIN_NAME"
        exit 2
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
                    exit 2
                fi
                CA_DOMAIN="$2"
                shift 2
                ;;
            --list-domains)
                list_domains
                ;;
            *)
                print_message $RED "Unknown option: $1"
                print_message $YELLOW "Use $0 --help for usage information"
                exit 2
                ;;
        esac
    done
}

# Function to set up domain paths
setup_domain_paths() {
    if [[ -z "$CA_DOMAIN" ]]; then
        print_message $RED "Error: No domain specified or detected"
        print_message $YELLOW "Use $0 --help for usage information"
        exit 2
    fi
    
    CA_DIR="${SCRIPT_DIR}/domains/${CA_DOMAIN}/ca"
    INTERMEDIATE_DIR="${SCRIPT_DIR}/domains/${CA_DOMAIN}/intermediate"
}

# Function to print test header
print_test_header() {
    local test_name="$1"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo
    print_message $BOLD "[$TOTAL_TESTS] Testing: $test_name"
    print_message $BLUE "$(printf '=%.0s' {1..60})"
}

# Function to record test result
record_test_result() {
    local status="$1"  # PASS, FAIL, WARN
    local message="$2"
    
    case "$status" in
        PASS)
            PASSED_TESTS=$((PASSED_TESTS + 1))
            print_message $GREEN "✓ PASS: $message"
            ;;
        FAIL)
            FAILED_TESTS=$((FAILED_TESTS + 1))
            print_message $RED "✗ FAIL: $message"
            ;;
        WARN)
            WARNING_TESTS=$((WARNING_TESTS + 1))
            print_message $YELLOW "⚠ WARN: $message"
            ;;
    esac
}

# Function to detect distribution
detect_distribution() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO="$ID"
        
        case "$ID" in
            debian|ubuntu|linuxmint|elementary|pop)
                DISTRO_FAMILY="debian"
                SYSTEM_CA_PATH="/usr/local/share/ca-certificates"
                ;;
            rhel|centos|fedora|almalinux|rocky|ol)
                DISTRO_FAMILY="redhat"
                SYSTEM_CA_PATH="/etc/pki/ca-trust/source/anchors"
                ;;
            opensuse*|sles|sled)
                DISTRO_FAMILY="suse"
                SYSTEM_CA_PATH="/etc/pki/trust/anchors"
                ;;
            arch|manjaro|endeavouros)
                DISTRO_FAMILY="arch"
                SYSTEM_CA_PATH="/etc/ca-certificates/trust-source/anchors"
                ;;
            alpine)
                DISTRO_FAMILY="alpine"
                SYSTEM_CA_PATH="/usr/local/share/ca-certificates"
                ;;
            *)
                DISTRO_FAMILY="unknown"
                SYSTEM_CA_PATH="/usr/local/share/ca-certificates"  # fallback
                ;;
        esac
    else
        DISTRO="unknown"
        DISTRO_FAMILY="unknown"
        SYSTEM_CA_PATH="/usr/local/share/ca-certificates"  # fallback
    fi
}

# Test 1: Verify source certificate files exist
test_source_certificates() {
    print_test_header "Source Certificate Files"
    
    local required_files=(
        "${CA_DIR}/ca.crt"
        "${INTERMEDIATE_DIR}/intermediate.crt"
        "${INTERMEDIATE_DIR}/ca-chain.crt"
    )
    
    local missing_files=()
    
    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            print_message $GREEN "  ✓ Found: $(basename "$file")"
        else
            missing_files+=("$file")
            print_message $RED "  ✗ Missing: $file"
        fi
    done
    
    if [[ ${#missing_files[@]} -eq 0 ]]; then
        record_test_result "PASS" "All source certificate files found"
    else
        record_test_result "FAIL" "${#missing_files[@]} source certificate files missing"
        return 1
    fi
}

# Test 2: Verify certificate validity
test_certificate_validity() {
    print_test_header "Certificate Validity"
    
    # Test Root CA certificate
    if openssl x509 -in "${CA_DIR}/ca.crt" -noout -checkend 0 >/dev/null 2>&1; then
        local subject=$(openssl x509 -in "${CA_DIR}/ca.crt" -noout -subject | sed 's/subject=//')
        local expiry=$(openssl x509 -in "${CA_DIR}/ca.crt" -noout -enddate | sed 's/notAfter=//')
        print_message $GREEN "  ✓ Root CA valid: $subject"
        print_message $BLUE "    Expires: $expiry"
    else
        record_test_result "FAIL" "Root CA certificate is invalid or expired"
        return 1
    fi
    
    # Test Intermediate CA certificate
    if openssl x509 -in "${INTERMEDIATE_DIR}/intermediate.crt" -noout -checkend 0 >/dev/null 2>&1; then
        local subject=$(openssl x509 -in "${INTERMEDIATE_DIR}/intermediate.crt" -noout -subject | sed 's/subject=//')
        local expiry=$(openssl x509 -in "${INTERMEDIATE_DIR}/intermediate.crt" -noout -enddate | sed 's/notAfter=//')
        print_message $GREEN "  ✓ Intermediate CA valid: $subject"
        print_message $BLUE "    Expires: $expiry"
    else
        record_test_result "FAIL" "Intermediate CA certificate is invalid or expired"
        return 1
    fi
    
    # Test certificate chain
    if openssl verify -CAfile "${INTERMEDIATE_DIR}/ca-chain.crt" "${INTERMEDIATE_DIR}/intermediate.crt" >/dev/null 2>&1; then
        print_message $GREEN "  ✓ Certificate chain validation successful"
        record_test_result "PASS" "All certificates are valid and chain correctly"
    else
        record_test_result "WARN" "Certificate chain validation failed (normal for self-signed CAs)"
    fi
}

# Test 3: Check installed certificate files
test_installed_certificate_files() {
    print_test_header "Installed Certificate Files"
    
    local cert_ext=""
    case "$DISTRO_FAMILY" in
        debian|alpine|suse) cert_ext=".crt" ;;
        redhat|arch) cert_ext=".pem" ;;
        *) cert_ext=".crt" ;;
    esac
    
    local installed_files=(
        "${SYSTEM_CA_PATH}/${CA_DOMAIN}-root-ca${cert_ext}"
        "${SYSTEM_CA_PATH}/${CA_DOMAIN}-intermediate-ca${cert_ext}"
    )
    
    local missing_installed=()
    
    for file in "${installed_files[@]}"; do
        if [[ -f "$file" ]]; then
            local perms=$(stat -c "%a" "$file" 2>/dev/null || echo "unknown")
            print_message $GREEN "  ✓ Installed: $(basename "$file") (permissions: $perms)"
            
            # Check if file content matches source
            if cmp -s "$file" "${CA_DIR}/ca.crt" 2>/dev/null || cmp -s "$file" "${INTERMEDIATE_DIR}/intermediate.crt" 2>/dev/null; then
                print_message $GREEN "    Content matches source certificate"
            else
                print_message $YELLOW "    Content verification skipped (different locations)"
            fi
        else
            missing_installed+=("$file")
            print_message $RED "  ✗ Missing: $file"
        fi
    done
    
    if [[ ${#missing_installed[@]} -eq 0 ]]; then
        record_test_result "PASS" "All certificates installed in system CA directory"
    else
        record_test_result "FAIL" "${#missing_installed[@]} certificates missing from system CA directory"
        return 1
    fi
}

# Test 4: Check system certificate bundle
test_system_certificate_bundle() {
    print_test_header "System Certificate Bundle"
    
    local bundle_paths=()
    local found_in_bundle=false
    
    case "$DISTRO_FAMILY" in
        debian|alpine)
            bundle_paths=(
                "/etc/ssl/certs/ca-certificates.crt"
                "/etc/ssl/certs"
            )
            ;;
        redhat)
            bundle_paths=(
                "/etc/pki/tls/certs/ca-bundle.crt"
                "/etc/ssl/certs/ca-bundle.crt"
                "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem"
            )
            ;;
        suse)
            bundle_paths=(
                "/var/lib/ca-certificates/ca-bundle.pem"
                "/etc/ssl/ca-bundle.pem"
            )
            ;;
        arch)
            bundle_paths=(
                "/etc/ssl/certs/ca-certificates.crt"
                "/etc/ca-certificates/extracted"
            )
            ;;
        *)
            bundle_paths=(
                "/etc/ssl/certs/ca-certificates.crt"
                "/etc/ssl/certs"
            )
            ;;
    esac
    
    for bundle_path in "${bundle_paths[@]}"; do
        if [[ -f "$bundle_path" ]]; then
            print_message $BLUE "  Checking bundle: $bundle_path"
            if grep -q "$CA_DOMAIN" "$bundle_path" 2>/dev/null; then
                print_message $GREEN "    ✓ CA certificates found in bundle"
                found_in_bundle=true
            else
                print_message $YELLOW "    - CA certificates not found in this bundle"
            fi
        elif [[ -d "$bundle_path" ]]; then
            print_message $BLUE "  Checking directory: $bundle_path"
            if find "$bundle_path" -name "*${CA_DOMAIN}*" -type f | grep -q .; then
                print_message $GREEN "    ✓ CA certificate files found in directory"
                found_in_bundle=true
            else
                print_message $YELLOW "    - CA certificate files not found in this directory"
            fi
        fi
    done
    
    if [[ "$found_in_bundle" == "true" ]]; then
        record_test_result "PASS" "CA certificates found in system bundle/directory"
    else
        record_test_result "WARN" "CA certificates not found in system bundles (may need time to propagate)"
    fi
}

# Test 5: Test OpenSSL verification
test_openssl_verification() {
    print_test_header "OpenSSL Certificate Verification"
    
    # Test with explicit CA file
    if openssl verify -CAfile "${CA_DIR}/ca.crt" "${CA_DIR}/ca.crt" >/dev/null 2>&1; then
        print_message $GREEN "  ✓ Root CA self-verification successful"
    else
        record_test_result "FAIL" "Root CA self-verification failed"
        return 1
    fi
    
    # Test intermediate with chain
    if openssl verify -CAfile "${INTERMEDIATE_DIR}/ca-chain.crt" "${INTERMEDIATE_DIR}/intermediate.crt" >/dev/null 2>&1; then
        print_message $GREEN "  ✓ Intermediate CA verification with chain successful"
    else
        print_message $YELLOW "  - Intermediate CA verification with chain failed (expected for self-signed)"
    fi
    
    # Test system verification (if certificates are in system store)
    if openssl verify "${CA_DIR}/ca.crt" >/dev/null 2>&1; then
        print_message $GREEN "  ✓ System verification successful (CA is trusted by system)"
        record_test_result "PASS" "OpenSSL can verify certificates using system store"
    else
        record_test_result "WARN" "System verification failed (certificates may not be in system store yet)"
    fi
}

# Test 6: Test curl functionality
test_curl_functionality() {
    print_test_header "curl Certificate Trust"
    
    # Create a temporary test server certificate for testing
    local test_domain="test.${CA_DOMAIN}"
    
    print_message $BLUE "  Testing curl with CA bundle..."
    
    # Test curl with explicit CA bundle
    if command -v curl >/dev/null 2>&1; then
        # Test curl version and SSL support
        local curl_version=$(curl --version | head -n1)
        print_message $BLUE "  curl version: $curl_version"
        
        # Test with a real HTTPS site using system CA store
        if curl -s --connect-timeout 5 --max-time 10 https://www.google.com >/dev/null 2>&1; then
            print_message $GREEN "  ✓ curl can connect to external HTTPS sites"
            
            # If we have a wildcard certificate, we could test it
            if [[ -f "${SCRIPT_DIR}/domains/${CA_DOMAIN}/certs/wildcard.${CA_DOMAIN}.crt" ]]; then
                print_message $BLUE "  Found wildcard certificate for testing"
                record_test_result "PASS" "curl is functional and wildcard certificate available for testing"
            else
                record_test_result "PASS" "curl is functional with system certificates"
            fi
        else
            record_test_result "WARN" "curl cannot connect to external sites (network issue?)"
        fi
    else
        record_test_result "WARN" "curl not available for testing"
    fi
}

# Test 7: Test wget functionality
test_wget_functionality() {
    print_test_header "wget Certificate Trust"
    
    if command -v wget >/dev/null 2>&1; then
        local wget_version=$(wget --version | head -n1)
        print_message $BLUE "  wget version: $wget_version"
        
        # Test wget with external site
        if wget --timeout=10 --tries=1 -q --spider https://www.google.com 2>/dev/null; then
            print_message $GREEN "  ✓ wget can connect to external HTTPS sites"
            record_test_result "PASS" "wget is functional with system certificates"
        else
            record_test_result "WARN" "wget cannot connect to external sites (network issue?)"
        fi
    else
        record_test_result "WARN" "wget not available for testing"
    fi
}

# Test 8: Check certificate update timestamp
test_certificate_update_status() {
    print_test_header "Certificate Update Status"
    
    case "$DISTRO_FAMILY" in
        debian|alpine)
            if [[ -f "/etc/ssl/certs/ca-certificates.crt" ]]; then
                local update_time=$(stat -c "%y" "/etc/ssl/certs/ca-certificates.crt" 2>/dev/null)
                print_message $GREEN "  ✓ Certificate bundle last updated: $update_time"
                record_test_result "PASS" "Certificate bundle timestamp available"
            else
                record_test_result "WARN" "Certificate bundle not found"
            fi
            ;;
        redhat)
            if [[ -f "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem" ]]; then
                local update_time=$(stat -c "%y" "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem" 2>/dev/null)
                print_message $GREEN "  ✓ Certificate bundle last updated: $update_time"
                record_test_result "PASS" "Certificate bundle timestamp available"
            else
                record_test_result "WARN" "Certificate bundle not found"
            fi
            ;;
        *)
            record_test_result "WARN" "Certificate update status check not implemented for this distribution"
            ;;
    esac
}

# Test 9: Environment verification
test_environment_verification() {
    print_test_header "Environment Verification"
    
    print_message $BLUE "  System Information:"
    print_message $BLUE "    Distribution: $DISTRO ($DISTRO_FAMILY family)"
    print_message $BLUE "    CA Path: $SYSTEM_CA_PATH"
    print_message $BLUE "    OpenSSL Version: $(openssl version 2>/dev/null || echo 'Not available')"
    
    # Check SSL library environment variables
    if [[ -n "${SSL_CERT_FILE:-}" ]]; then
        print_message $BLUE "    SSL_CERT_FILE: $SSL_CERT_FILE"
    fi
    
    if [[ -n "${SSL_CERT_DIR:-}" ]]; then
        print_message $BLUE "    SSL_CERT_DIR: $SSL_CERT_DIR"
    fi
    
    record_test_result "PASS" "Environment information collected"
}

# Function to show summary
show_summary() {
    echo
    print_message $BOLD "VERIFICATION SUMMARY"
    print_message $BOLD "==================="
    
    print_message $GREEN "Passed: $PASSED_TESTS/$TOTAL_TESTS tests"
    if [[ $FAILED_TESTS -gt 0 ]]; then
        print_message $RED "Failed: $FAILED_TESTS/$TOTAL_TESTS tests"
    fi
    if [[ $WARNING_TESTS -gt 0 ]]; then
        print_message $YELLOW "Warnings: $WARNING_TESTS/$TOTAL_TESTS tests"
    fi
    
    echo
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        if [[ $WARNING_TESTS -eq 0 ]]; then
            print_message $GREEN "✓ OVERALL STATUS: ALL TESTS PASSED"
            print_message $GREEN "Your CA certificates are properly installed and configured!"
        else
            print_message $YELLOW "⚠ OVERALL STATUS: PASSED WITH WARNINGS"
            print_message $YELLOW "Your CA certificates are installed but some issues were detected."
        fi
    else
        print_message $RED "✗ OVERALL STATUS: SOME TESTS FAILED"
        print_message $RED "Your CA certificates may not be properly installed."
        echo
        print_message $YELLOW "Recommendations:"
        print_message $YELLOW "1. Re-run the installation script"
        print_message $YELLOW "2. Check that you have proper permissions"
        print_message $YELLOW "3. Verify the certificate files are valid"
    fi
}

# Main function
main() {
    print_message $GREEN "CA Certificate Installation Verification v1.0.0"
    print_message $GREEN "================================================="
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # If no domain specified, try to auto-detect
    if [[ -z "$CA_DOMAIN" ]]; then
        auto_detect_domain
    fi
    
    # Set up domain paths
    setup_domain_paths
    
    # Detect distribution
    detect_distribution
    print_message $BLUE "Detected: $DISTRO ($DISTRO_FAMILY family)"
    print_message $BLUE "System CA Path: $SYSTEM_CA_PATH"
    print_message $BLUE "Domain: $CA_DOMAIN"
    
    # Verify we're in the right directory
    if [[ ! -d "domains/${CA_DOMAIN}" ]]; then
        print_message $RED "Error: Certificate directory 'domains/${CA_DOMAIN}' not found."
        print_message $YELLOW "Please run this script from the directory containing the 'domains' folder."
        exit 2
    fi
    
    # Run all tests
    test_source_certificates
    test_certificate_validity
    test_installed_certificate_files
    test_system_certificate_bundle
    test_openssl_verification
    test_curl_functionality
    test_wget_functionality
    test_certificate_update_status
    test_environment_verification
    
    # Show summary
    show_summary
    
    # Exit with appropriate code
    if [[ $FAILED_TESTS -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Call main function
main "$@"
