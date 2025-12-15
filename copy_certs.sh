#!/bin/bash

# ==============================================================================
# Script to securely copy generated certificates to a remote host.
#
# Usage: ./copy_certs.sh <ssh_alias> -d <domain>
#
# Parameters:
#   <ssh_alias> : The alias configured in your ~/.ssh/config for the remote host.
#   -d <domain> : The domain (e.g., immich.lan) whose certificates will be copied.
#
# Configuration:
#   REMOTE_DEST_PATH: Change this variable to point to the destination directory
#                     on the remote server.
# ==============================================================================

# --- GLOBAL CONFIGURATION ---
# IMPORTANT! Modify these paths and values according to your needs.
# Path on the remote server where certificates will be copied.
#REMOTE_DEST_PATH="/shared/traefik/config/certs/"
REMOTE_DEST_PATH="/docker/traefik/certs/"
# UID and GID for the remote files. Leave empty to skip ownership change.
#REMOTE_UID="100000"
#REMOTE_GID="100000"
REMOTE_UID="0"
REMOTE_GID="0"

# --- INPUT VALIDATION AND ARGUMENT PARSING ---

# Function to display help message
show_help() {
    cat << EOF
Usage: ./copy_certs.sh <ssh_alias> [OPTIONS]

Options:
  -d, --domain DOMAIN       Specify the domain (e.g., immich.lan) whose
                            certificates will be copied.
  -h, --help                Show this help message.

Arguments:
  <ssh_alias>               The alias configured in your ~/.ssh/config for
                            the remote host.

Examples:
  ./copy_certs.sh my-server-alias -d immich.lan
  ./copy_certs.sh another-host --domain nextcloud.com
EOF
    exit 0
}

# Parse command line arguments
SSH_ALIAS=""
DOMAIN=""
shift_count=0

for arg in "$@"; do
    shift_count=$((shift_count + 1))
    case $arg in
        -h|--help)
            show_help
            ;;
        -d|--domain)
            # Domain will be read in the next iteration
            ;;
        *)
            if [ -z "$SSH_ALIAS" ]; then
                SSH_ALIAS="$arg"
            elif [ "$prev_arg" = "-d" ] || [ "$prev_arg" = "--domain" ]; then
                DOMAIN="$arg"
            else
                echo "Error: Unknown argument '$arg'" >&2
                show_help
            fi
            ;;
    esac
    prev_arg="$arg"
done

# Validate required arguments
if [ -z "$SSH_ALIAS" ]; then
    echo "Error: SSH alias not specified." >&2
    show_help
fi

if [ -z "$DOMAIN" ]; then
    echo "Error: Domain not specified. Use -d or --domain." >&2
    show_help
fi


# --- FILE DEFINITION & VERIFICATION ---

echo "Searching for certificate files for domain '$DOMAIN'..."

# Helper function to find a file and validate the result
find_and_validate_file() {
    local file_basename=$1
    local file_path

    file_path=$(find domains -name "$file_basename")

    if [ -z "$file_path" ]; then
        echo "Error: Could not find '$file_basename' within the 'domains' directory." >&2
        exit 1
    fi

    if [ $(echo "$file_path" | wc -l) -gt 1 ]; then
        echo "Error: Found multiple possible files for '$file_basename'. Please resolve the ambiguity:" >&2
        echo "$file_path" >&2
        exit 1
    fi

    if [ ! -f "$file_path" ]; then
        # This case is unlikely if find succeeds, but good for safety
        echo "Error: Found path '$file_path' is not a regular file." >&2
        exit 1
    fi

    echo "  [OK] Found: $file_path" >&2
    echo "$file_path"
}

# The find_and_validate_file function prints the path to stdout, so we capture it.
# The script will exit if any file is not found or is ambiguous.
FULLCHAIN_FILE=$(find_and_validate_file "$DOMAIN-fullchain.crt")
KEY_FILE=$(find_and_validate_file "$DOMAIN.key")
TOML_FILE=$(find_and_validate_file "$DOMAIN.toml")

# Array with files to copy
SOURCE_FILES=("$FULLCHAIN_FILE" "$KEY_FILE" "$TOML_FILE")


# --- COPY EXECUTION ---

echo -e "\nStarting certificate copy to '$SSH_ALIAS' at path '$REMOTE_DEST_PATH'..."

# Create remote directory if it doesn't exist
ssh "$SSH_ALIAS" "mkdir -p $REMOTE_DEST_PATH"
if [ $? -ne 0 ]; then
    echo "Error: Failed to create destination directory on remote host."
    exit 1
fi

# Copy each file using scp and set ownership
for file in "${SOURCE_FILES[@]}"; do
    local_filename=$(basename "$file")
    echo "Copying $local_filename..."
    scp -q "$file" "${SSH_ALIAS}:${REMOTE_DEST_PATH}"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to copy $local_filename."
        exit 1
    fi

    # Set ownership on remote file if UID and GID are defined
    if [ -n "$REMOTE_UID" ] && [ -n "$REMOTE_GID" ]; then
        echo "Setting ownership for $local_filename to $REMOTE_UID:$REMOTE_GID..."
        ssh "$SSH_ALIAS" "chown ${REMOTE_UID}:${REMOTE_GID} \"${REMOTE_DEST_PATH}/${local_filename}\""
        if [ $? -ne 0 ]; then
            echo "Warning: Failed to set ownership for $local_filename on remote host."
        fi
    fi
done

echo -e "\nSuccess! All files have been copied correctly."
exit 0
