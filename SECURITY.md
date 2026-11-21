# Security Policy

## Supported Versions

| Version | Support status |
| ------- | -------------- |
| v3.0.x | :white_check_mark: Supported stable release line |
| v2.1.0 and earlier | :x: Unsupported |
| `main` | Development source; may contain unreleased changes |

## Reporting a Vulnerability

If you discover a security vulnerability in Linux Package Source Manager, please report it responsibly.

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

This policy covers the `install.sh` bootstrap, the `linux-package-source-manager.sh` application, their release workflow, and their direct behavior. The following are out of scope:

- Bugs in third-party tools (curl, wget, apt)
- Issues in Ubuntu itself
- Network-level attacks beyond the script's control

## Security Considerations

### What Linux Package Source Manager Does

- Writes to `/etc/apt/sources.list.d/` and `/etc/apt/apt.conf.d/`
- Requires root privileges
- Tests network endpoints (mirrors)
- Creates backups in `/var/backups/power-apt-boost/`

### What Linux Package Source Manager Does NOT Do

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

## Node.js registry operations

- Node.js status reporting displays version information and registry origins only (scheme, host and optional port). URL paths, queries, fragments and embedded credentials are not printed. Environment override names may be listed, but their values are never printed.
- Registry URLs must use HTTPS and cannot contain embedded credentials, query strings or fragments. Redirects must remain credential-free HTTPS. Registry metadata responses are size-limited; the checker reads npm package metadata and sends a HEAD request to the advertised tarball endpoint. It does not download the package archive, run package scripts or install dependencies.
- npm, pnpm, Yarn Classic and Yarn Berry are changed through their own configuration commands. Mutations target one user-level config file by default; project scope requires an explicit project directory with a regular package.json. The adapter refuses symlinked and non-regular config targets.
- The managed operation changes only the default fetch-registry setting. Existing scoped registry entries and authentication values are not rewritten. package.json, publishConfig, workspace metadata and lockfiles are not edited. Yarn Berry's distinct npmPublishRegistry remains intact; for other tools, a default registry can also be used by publish commands when no publish-specific value is configured.
- Known environment overrides for registry/config resolution cause mutating operations to refuse. Status output reports override names without values. The tool does not import or store registry credentials.
- Before mutation, the selected config file is copied into a mode-0700 snapshot directory with mode-0600 contents. Restore checks the post-change SHA-256 and refuses to overwrite later edits. Reset is limited to the exact client, scope and target that Linux Package Source Manager previously managed.
- Non-interactive changes require --yes; --dry-run prints the selected target and redacted current/proposed registry labels without writing configuration. Node.js operations do not require root.


## Docker Engine and OCI registry operations

- Docker Engine APT repositories and OCI image registry mirrors are reported separately. Docker repository inspection is read-only and does not write APT source files or run APT commands.
- The Docker configuration manager targets the rootful Linux daemon at `/etc/docker/daemon.json`; rootless Docker and Docker Desktop are outside scope. Rootless Docker uses a per-user configuration path.
- Registry probes send an unauthenticated HTTPS `GET /v2/` request. Only an HTTP 200 or 401 response carrying `Docker-Distribution-API-Version: registry/2.0` is accepted. Redirects must remain HTTPS and credential-free. The probe does not obtain tokens, send credentials, pull images or download layers.
- A Registry V2 probe confirms protocol compatibility only. It cannot establish that an endpoint is configured as a Docker Hub pull-through cache or validate its cache policy.
- Mirror URLs accepted for configuration are HTTPS origins only; embedded credentials, URL paths, query strings and fragments are rejected. Status output shows registry origins only.
- The manager refuses symlinked or non-regular `daemon.json` targets and requires an existing Docker configuration directory. Existing JSON must be a top-level object, and `registry-mirrors` must be an array of strings when present. Other keys and existing mirror entries are preserved.
- Before mutation, the proposed temporary file is checked using `dockerd --validate --config-file=...`. The final file is validated again after the atomic replacement. If validation fails, the manager attempts to restore the exact snapshot.
- Snapshots are stored in a mode-0700 Docker backup directory with mode-0600 files. Restore compares the current file SHA-256 with the recorded post-change hash and refuses to overwrite external edits.
- Configuring or resetting a registry mirror does not restart Docker. `--docker-restart` is a distinct command, requires root, requires the Docker systemd service to already be active, and requires a separate confirmation (or explicit `--yes` in non-interactive use). Restarting Docker can interrupt running workloads.
- The built-in `mirror.gcr.io` option is a partial cache of frequently requested public Docker Hub images, not a complete mirror. Do not assume arbitrary registry endpoints provide equivalent cache behavior.

## Release status

The `main` branch may contain changes that have not been published as a tagged release. For production use, prefer the latest stable version listed on the [GitHub Releases page](https://github.com/power0matin/linux-package-source-manager/releases) unless you have reviewed and intentionally chosen unreleased source.

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
- Poetry `supplemental` is the default. A `primary` source disables implicit PyPI; an `explicit` source is not automatically used unless a dependency pins that source. Linux Package Source Manager warns about these semantics and never edits dependency declarations or lockfiles.
- Python snapshots are stored under `$XDG_STATE_HOME/power-apt-boost/python` (default: `~/.local/state/power-apt-boost/python`). The snapshot directory is mode `0700` and its files are mode `0600`. A TOML snapshot contains a copy of the complete target file, so protect it as user configuration data; it may contain private repository metadata unrelated to the managed block.
- Snapshot restore compares the current pip value or TOML post-change SHA-256 with the recorded post-change state. If another tool or user edited the configuration afterward, restore refuses to overwrite that newer state.
- uv/Poetry TOML editing needs Python 3.11+ (`tomllib`) or an already-installed `tomli`. The tool does not install a parser, package manager or dependency to enable this feature.
- pipx is detected for inventory only. Its separate application virtual environments are not changed by this phase.

## Best Practices for Users

1. **Review the bootstrap and application** before executing remote code. The one-line command launches `install.sh`, which downloads the pinned application and checksum:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/power0matin/linux-package-source-manager/main/install.sh | less
   curl -fsSL https://raw.githubusercontent.com/power0matin/linux-package-source-manager/v3.0.5/linux-package-source-manager.sh | less
   ```

2. **Use `--dry-run` first** to see what would change:

   ```bash
   curl -fsSL URL | sudo bash -s -- --dry-run
   ```

3. **Check backups** after running:

   ```bash
   ls -la /var/backups/power-apt-boost/
   ```

4. **Verify the downloaded application** against the checksum published with the pinned release. A checksum confirms that the files match each other; it is not a detached signature and does not independently authenticate the publisher:

   ```bash
   sha256sum linux-package-source-manager.sh
   ```
