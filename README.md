# Local PKI & Certificate Management Scripts

A collection of Bash scripts for creating and managing a local Public Key
Infrastructure (PKI). These tools allow you to generate certificate
hierarchies, deploy them to remote hosts, and install them on client machines.

> [!WARNING]
> For development, lab, and learning purposes only. Do not use for production
> environments that require publicly trusted certificates.

## Scripts Overview

This project includes the following scripts, designed to be used together:

| Script                                 | Description                                                              |
| -------------------------------------- | ------------------------------------------------------------------------ |
| `certgen.sh`                           | Generates a full certificate hierarchy (Root CA → Intermediate CA → Host). |
| `copy_certs.sh`                        | Copies host certificates (`.crt`, `.key`, `.toml`) to a remote server.     |
| `check_certs.sh`                       | Displays validity, dates, CN, and SANs of a given certificate file.        |
| `install-ca-certificates-universal.sh` | Installs the Root and Intermediate CAs into the system trust store.        |
| `verify-ca-installation.sh`            | Checks if the custom CA is correctly installed and trusted by the system.  |

## Common Workflow

Here is a typical workflow for generating a certificate and deploying it.

---

### 1. Generate Certificates

First, create a certificate hierarchy for your domain. This command generates a new Root CA and Intermediate CA for `yourdomain.lan`, then uses them to sign a wildcard certificate for `*.yourdomain.lan`.

```bash
bash certgen.sh -d yourdomain.lan -n '*'
```

All necessary files are created inside the `domains/yourdomain.lan/` directory, which contains subdirectories for the `ca`, `intermediate`, and `certs`.

<details>
<summary><b>Click to see example output</b></summary>

```
cmiranda@lhome01 ~/Projects/git.certgen (main)$ ./certgen.sh -d lan -n owncloud -y
=== Certificate Generator with CA → Intermediate → Host hierarchy v1.1.2 ===
This script will generate certificates organized by domain
Each domain will have its own CA and certificates structure
===========================================================
Using domain: lan
Domain directory: domains/lan
Certificates will be stored in: domains/lan/certs
CA files for domain lan already exist, using existing ones.
Intermediate CA files for domain lan already exist, using existing ones.
Generating certificate for owncloud.lan...
..+++++++++++++++++++++++++++++++++++++++*.+.......+++++++++++++++++++++++++++++++++++++++*.......
....+.+............+...+.....+.........+.............+..+.+..+.+......+...+...........+....+......
Private key generated: domains/lan/certs/owncloud.lan.key
CSR generated: domains/lan/certs/owncloud.lan.csr
Certificate request self-signature ok
subject=C=AR, ST=Buenos Aires, L=CABA, O=Host Organization, OU=Host Org Unit, CN=owncloud.lan
Certificate signed: domains/lan/certs/owncloud.lan.crt
Full certificate chain generated: domains/lan/certs/owncloud.lan-fullchain.crt
Generating Traefik configuration file...
Traefik configuration generated: domains/lan/certs/owncloud.lan.toml
Process completed! Key files are:
- Private key: domains/lan/certs/owncloud.lan.key
- Certificate: domains/lan/certs/owncloud.lan.crt
- Full chain (host + intermediate + CA): domains/lan/certs/owncloud.lan-fullchain.crt
- Traefik config: domains/lan/certs/owncloud.lan.toml
All certificates have been generated in the domains/lan directory
```
</details>
---

### 2. Deploy Certificate to a Remote Server

Next, copy the generated host certificate files to your server (e.g., a reverse proxy or web server) using its SSH alias. The script dynamically finds the correct files based on the domain name.

```bash
bash copy_certs.sh your-ssh-alias -d wildcard.yourdomain.lan
```
> [!NOTE]
> The remote destination path and file ownership (UID/GID) can be configured as global variables inside the `copy_certs.sh` script.<br />
> UID/GID numbers is because at my destination servers, those files are shared as mount bind directory inside LXC Proxmox container

<details>
<summary><b>Click to see example output</b></summary>

```
cmiranda@lhome01 ~/Projects/git.certgen (main)$ ./copy_certs.sh pve01 -d owncloud.lan
Searching for certificate files for domain 'owncloud.lan'...
  [OK] Found: domains/lan/certs/owncloud.lan-fullchain.crt
  [OK] Found: domains/lan/certs/owncloud.lan.key
  [OK] Found: domains/lan/certs/owncloud.lan.toml

Starting certificate copy to 'pve01' at path '/shared/traefik/config/certs/'...
Copying owncloud.lan-fullchain.crt...
Setting ownership for owncloud.lan-fullchain.crt to 100000:100000...
Copying owncloud.lan.key...
Setting ownership for owncloud.lan.key to 100000:100000...
Copying owncloud.lan.toml...
Setting ownership for owncloud.lan.toml to 100000:100000...

Success! All files have been copied correctly.
```
</details>

---

### 3. Install CA on Your Local/Client Machine

To make browsers and system tools trust your new certificates, install the Root and Intermediate CAs on your client machine. The script detects your Linux distribution and installs the CAs in the correct system-wide location.

```bash
# This command requires sudo privileges
sudo bash install-ca-certificates-universal.sh -d yourdomain.lan
```
You can also use the `--url` flag to install certificates from a remote HTTP server instead of a local directory.

<details>
<summary><b>Click to see example output</b></summary>

```
Universal CA Certificate Installation Script v1.0.0
====================================================

✓ Auto-detected domain: yourdomain.lan
✓ Detected: ubuntu (debian family)
  Package Manager: apt
  CA Path: /usr/local/share/ca-certificates
  Update Command: update-ca-certificates
...
✓ Root CA certificate installed: /usr/local/share/ca-certificates/yourdomain.lan-root-ca.crt
✓ Intermediate CA certificate installed: /usr/pve/local/share/ca-certificates/yourdomain.lan-intermediate-ca.crt
Updating system certificate store using: update-ca-certificates
...
✓ System certificate store updated successfully!

Post-Installation Instructions:
===============================
1. System certificates have been installed for: ubuntu (debian)
...
```
</details>

---

### 4. Verify the Installation

Finally, run the verification script to ensure your system and tools like `curl` and `openssl` correctly trust the newly installed CA.

```bash
bash verify-ca-installation.sh -d yourdomain.lan
```
This script runs a comprehensive suite of tests, from checking file existence to verifying trust in the system's CA bundle.

<details>
<summary><b>Click to see example output</b></summary>

```
CA Certificate Installation Verification v1.0.0
=================================================
✓ Auto-detected domain: yourdomain.lan
Detected: ubuntu (debian family)
...
[1] Testing: Source Certificate Files
============================================================
✓ PASS: All source certificate files found

[2] Testing: Certificate Validity
============================================================
✓ PASS: All certificates are valid and chain correctly
...
VERIFICATION SUMMARY
====================
✓ Passed: 9/9 tests

✓ OVERALL STATUS: ALL TESTS PASSED
Your CA certificates are properly installed and configured!
```
</details>
