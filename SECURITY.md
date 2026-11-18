# Security Policy

## Supported Versions

| Version | Support status |
| ------- | -------------- |
| v2.1.0 | :white_check_mark: Latest published release |
| v2.0.x and earlier | :x: Unsupported |
| `main` / script version `3.0.0` | Development source; not a published release |

## Reporting a Vulnerability

If you discover a security vulnerability in Power APT Boost, please report it responsibly.

**Do NOT open a public GitHub issue for security vulnerabilities.**

### How to Report

Send an email to the maintainer with:

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### What to Expect

- **Acknowledgment**: Within 48 hours
- **Assessment**: Within 1 week
- **Fix or mitigation**: Depending on severity, within 1-2 weeks
- **Disclosure**: After a fix is available, a security advisory will be published

### Scope

This policy covers the `power-apt-boost.sh` script and its direct behavior. The following are out of scope:

- Bugs in third-party tools (curl, wget, apt)
- Issues in Ubuntu itself
- Network-level attacks beyond the script's control

## Security Considerations

### What Power APT Boost Does

- Writes to `/etc/apt/sources.list.d/` and `/etc/apt/apt.conf.d/`
- Requires root privileges
- Tests network endpoints (mirrors)
- Creates backups in `/var/backups/power-apt-boost/`

### What Power APT Boost Does NOT Do

- Exfiltrates data
- Downloads or executes remote code
- Changes unrelated system settings such as firewall rules, routes, DNS resolver configuration, VPN settings or SSH configuration.
- Probes arbitrary external endpoints unless the user explicitly supplies a custom `--mirror` URL. During `apt-get update`, APT contacts the repositories configured on the host.

### Integrity and current limitations

- The script uses `set -euo pipefail`; strict shell options do not by themselves provide transactional file operations.
- The current source/config writes are not all atomic.
- Backup copy failures are not consistently treated as fatal, and restore does not yet guarantee exact reconstruction of files that existed or did not exist before the operation.
- Rollback after a failed `apt-get update` is best-effort in the current source and must not be treated as a guaranteed full-system restore.
- `--dry-run` is intended to test mirror selection without applying persistent APT configuration changes.
- Atomic writes, validated snapshots, exact restore and verified rollback are mandatory Phase 1 work. Until that work is merged, inspect the script and maintain an independent recovery path before applying it to a production host.

## Release status

The `main` branch currently declares script version `3.0.0`, but that version has not been published as a Git tag/release. The latest published release is `v2.1.0`. For production use, prefer the tagged release unless you have reviewed and intentionally chosen the unreleased source.

## Best Practices for Users

1. **Review the script** before running from a URL:

   ```bash
   curl -fsSL URL | less
   ```

2. **Use `--dry-run` first** to see what would change:

   ```bash
   curl -fsSL URL | sudo bash -s -- --dry-run
   ```

3. **Check backups** after running:

   ```bash
   ls -la /var/backups/power-apt-boost/
   ```

4. **Verify the script** matches the repository:

   ```bash
   sha256sum power-apt-boost.sh
   ```
