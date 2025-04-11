# Self-signed CA Generator with Intermediate

*Version: 1.3.0 (2025-04-10)*

A Bash script for generating a complete self-signed CA hierarchy with support for wildcard SSL certificates and subdomains.

**For laboratory/learning purposes only.**

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
  - [Basic Usage](#basic-usage)
  - [Usage Examples](#usage-examples)
- [Certificate Structure](#certificate-structure)
- [Generated Files](#generated-files)
- [Options](#options)
- [Subdomains](#subdomains)
- [Notes](#notes)
- [License](#license)

## Overview

This script generates a complete certificate hierarchy:
- Root CA → Intermediate CA → Host Certificate (optional)

It organizes certificates by domain in separate directories, making certificate management easier.

## Features

- Full certificate hierarchy creation (Root CA → Intermediate CA → Host certs)
- Domain-specific certificate organization
- Wildcard certificate support
- Alternative DNS names support
- Parent domain CA reuse for subdomain certificates
- Interactive and non-interactive modes
- OpenSSL 3.x compatibility

## Requirements

- Bash shell environment
- OpenSSL 3.x

## Installation

1. Download the script:
   ```
   curl -O https://raw.githubusercontent.com/Mstaaravin/certgen/main/certgen.sh
   ```

2. Make it executable:
   ```
   chmod +x certgen.sh
   ```

## Usage

### Basic Usage

```
./certgen.sh [options]
```

### Usage Examples

#### Interactive Mode:
```
./certgen.sh
```

#### Generate Only CA Infrastructure for a Domain:
```
./certgen.sh -d example.com
```

#### Generate Certificate for www.example.com Non-interactively:
```
./certgen.sh -d example.com -n www -y
```

#### Generate Wildcard Certificate for *.example.com:
```
./certgen.sh -d example.com -n "*" -y
```

#### Generate Certificate with Alternative Names:
```
./certgen.sh -d example.com -n www -a "api.example.com admin.example.com"
```

#### Generate Certificate Using Parent Domain's CA:
```
./certgen.sh -d dev.example.com -n www -p example.com
```

## Certificate Structure

Certificates are organized by domain in separate directories:
```
domains/[domain]/
  ├── ca/                # Root CA files
  ├── intermediate/      # Intermediate CA files
  └── certs/             # Host certificates
```

## Generated Files

- **ca.key**: Root CA private key
- **ca.crt**: Root CA certificate
- **intermediate.key**: Intermediate CA private key
- **intermediate.crt**: Intermediate CA certificate
- **ca-chain.crt**: Chain of trust (intermediate + root)
- **[host].key**: Host private key
- **[host].crt**: Host certificate
- **[host]-fullchain.crt**: Host certificate + intermediate + root

## Options

| Option | Description |
|--------|-------------|
| `-h`, `--help` | Show help message |
| `-d`, `--domain DOMAIN` | Specify the domain (e.g., example.com) |
| `-n`, `--hostname NAME` | Specify the hostname (e.g., www or * for wildcard) |
| `-a`, `--alt-names "N1 N2"` | Specify alternative DNS names (space-separated) |
| `-p`, `--parent-domain DOM` | Specify a parent domain to use its CA certificates |
| `--country CODE` | Specify the country code (default: AR) |
| `--state STATE` | Specify the state/province (default: Buenos Aires) |
| `--city CITY` | Specify the city (default: CABA) |
| `--org ORG` | Specify the organization (default: Host Organization) |
| `-y`, `--yes` | Non-interactive mode (use defaults) |

## Subdomains

The script supports a parent-child domain relationship for certificate hierarchies, which is useful when you have multiple related domains that should share the same trust infrastructure.

### How Subdomains Work

When you use the `-p` or `--parent-domain` option:

1. The script uses the CA infrastructure (Root CA and Intermediate CA) from the specified parent domain.
2. New certificates for the subdomain are signed using the parent domain's Intermediate CA.
3. This creates a consistent chain of trust across your main domain and all subdomains.

### Directory Structure for Subdomains

When using the parent domain option, the directory structure is optimized:

```
domains/
  ├── example.com/               # Parent domain
  │   ├── ca/                    # Root CA files
  │   ├── intermediate/          # Intermediate CA files
  │   └── certs/                 # Host certificates for parent domain
  │
  └── dev.example.com/           # Subdomain
      └── certs/                 # ONLY host certificates for this subdomain
```

**Important**: When using the `-p` option, the subdomain directory will **only** contain the host certificates. The CA and intermediate certificates/keys are not duplicated but instead referenced from the parent domain directory. This ensures a more efficient and consistent certificate hierarchy.

### Benefits

- **Consistent Trust Chain**: All subdomains share the same root of trust.
- **Simplified Management**: You only need to distribute one Root CA certificate to trust all related domains.
- **Organized Structure**: Each domain maintains its own directory for host certificates while sharing the CA infrastructure.
- **Storage Efficiency**: CA certificates and keys are not duplicated across subdomains.

### Example Scenario

Imagine you have:
- A main domain: `example.com`
- Multiple environments: `dev.example.com`, `staging.example.com`, `test.example.com`

You can first create the CA infrastructure for the main domain:

```
./certgen.sh -d example.com
```

Then generate certificates for each environment using the parent domain's CA:

```
./certgen.sh -d dev.example.com -n www -p example.com
./certgen.sh -d staging.example.com -n www -p example.com
./certgen.sh -d test.example.com -n www -p example.com
```

This ensures all certificates are trusted if the client trusts the main domain's Root CA.

## Notes

- The ca-chain.crt file contains the intermediate certificate concatenated with the root CA certificate.
- Keep your CA private keys secure. The root CA key should ideally be stored offline after initial creation.
- This script can create a complete CA infrastructure from scratch or use existing CA files if found in the appropriate directory.
- You can create only the CA infrastructure without generating host certificates by omitting the hostname parameter.
- Wildcard certificates (*.domain.com) can be created by specifying "*" as the hostname.
- These certificates are self-signed and intended for development, testing, or educational environments only. They will not be trusted by browsers or systems without manually adding the CA certificate to their trust stores.

## License

Copyright (c) 2025. All rights reserved.

## Version History

- **1.3.0 (2025-04-10)** - Updated title and description to better reflect the purpose of the script as a self-signed CA generator. Added warning about usage for laboratory/learning purposes only.
- **1.2.0 (2025-04-10)** - Clarified subdomain directory structure, explaining that subdomain directories only contain host certificates while CA infrastructure remains in the parent domain.
- **1.1.0 (2025-04-10)** - Added detailed section on subdomain functionality with examples and benefits.
- **1.0.0** - Initial documentation release.
