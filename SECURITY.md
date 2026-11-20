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

- APT source and network configuration writes use atomic replacement. Existing file ownership and mode are preserved when a managed file is replaced.
- Apply and restore operations use a mutation lock. A validated format-1 snapshot with a SHA-256 checksum is required before an apply operation.
- Restore validates the snapshot before staging the current APT paths. New snapshots record whether each managed path existed, so restore can recreate or remove those paths exactly.
- If a source/config write or `apt-get update` fails, the tool attempts to restore the previous APT configuration from the validated snapshot. If rollback itself fails, the recovery snapshot/staging path is reported for manual recovery.
- Snapshots cover `/etc/apt/sources.list`, `sources.list.d` and `apt.conf.d`. They do not snapshot installed packages, package lists or downloaded archives. In particular, the ordinary package-index maintenance performed by `apt-get update` is not rolled back.
- Legacy backups remain readable but do not contain the full prior path-existence manifest; selective restore is supported only for validated manifest-based snapshots.
- The tool refuses to replace unmanaged or mixed source files, non-tool-owned managed-config files and symlinked targets. Separate third-party source files are read for inventory but are not rewritten.
- `--dry-run` benchmarks and previews without applying persistent APT configuration changes.

## Release status

The `main` branch currently declares script version `3.0.0`, but that version has not been published as a Git tag/release. The latest published release is `v2.1.0`. For production use, prefer the tagged release unless you have reviewed and intentionally chosen the unreleased source.

### Network and proxy diagnostics

- `--doctor` performs local checks without changing APT configuration.
- Live DNS and HTTPS/TLS probes are opt-in through `--doctor --network-diagnostics`.
- APT proxy URLs supplied through `--proxy` cannot contain usernames or passwords; do not place credentials in command-line arguments or shell history.
- `--clear-proxy` explicitly writes `DIRECT`; leaving proxy options unset preserves existing external APT proxy settings and existing proxy directives in the tool-managed file.

## Python package-source operations

- Python status reporting is read-only. Environment override **names** are shown without their values, and configured pip index URLs are displayed as host/path labels rather than raw strings.
- User-supplied Simple API URLs must use HTTPS and cannot contain URL-embedded usernames/passwords, query strings or fragments. The tester checks metadata and one advertised distribution endpoint; it does not install packages or download a package archive in full.
- pip configuration writes are limited to the selected user, active-virtualenv or global scope. A pre-existing `PIP_INDEX_URL` or `PIP_CONFIG_FILE` override causes a safe refusal instead of writing an ineffective configuration. Existing `PIP_EXTRA_INDEX_URL` and trusted-host settings are left untouched.
- Global pip configuration is blocked when the selected interpreter reports the PEP 668 `EXTERNALLY-MANAGED` marker. The tool does not use `--break-system-packages`.
- uv and Poetry edits are limited to one explicitly selected TOML file. Existing files are parsed before and after the change, app-managed blocks are uniquely marked, writes use atomic replacement, and symlinked or non-regular targets are refused. Existing private sources, project pins and unrelated TOML entries are preserved.
- Poetry `supplemental` is the default. A `primary` source disables implicit PyPI; an `explicit` source is not automatically used unless a dependency pins that source. Power APT Boost warns about these semantics and never edits dependency declarations or lockfiles.
- Python snapshots are stored under `$XDG_STATE_HOME/power-apt-boost/python` (default: `~/.local/state/power-apt-boost/python`). The snapshot directory is mode `0700` and its files are mode `0600`. A TOML snapshot contains a copy of the complete target file, so protect it as user configuration data; it may contain private repository metadata unrelated to the managed block.
- Snapshot restore compares the current pip value or TOML post-change SHA-256 with the recorded post-change state. If another tool or user edited the configuration afterward, restore refuses to overwrite that newer state.
- uv/Poetry TOML editing needs Python 3.11+ (`tomllib`) or an already-installed `tomli`. The tool does not install a parser, package manager or dependency to enable this feature.
- pipx is detected for inventory only. Its separate application virtual environments are not changed by this phase.

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
