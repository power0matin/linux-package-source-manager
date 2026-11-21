<h1 align="center">Linux Package Source Manager</h1>

<p align="center">
  <img src="assets/logo.svg" alt="LPSM - Linux Package Source Manager" width="720">
</p>

<!-- repo-badges:start -->
<p align="center">
  <a href="https://hits.sh/github.com/power0matin/linux-package-source-manager/"><img src="https://hits.sh/github.com/power0matin/linux-package-source-manager.svg?style=flat-square&amp;label=Views&amp;labelColor=18181B&amp;color=0EA5E9&amp;logo=github" alt="Repository Views"/></a>
  <a href="https://github.com/power0matin/linux-package-source-manager/stargazers"><img src="https://img.shields.io/github/stars/power0matin/linux-package-source-manager?style=flat-square&amp;label=Stars&amp;labelColor=18181B&amp;color=F59E0B&amp;logo=github&amp;logoColor=white" alt="GitHub Stars"/></a>
  <a href="https://github.com/power0matin/linux-package-source-manager/forks"><img src="https://img.shields.io/github/forks/power0matin/linux-package-source-manager?style=flat-square&amp;label=Forks&amp;labelColor=18181B&amp;color=6366F1&amp;logo=github&amp;logoColor=white" alt="GitHub Forks"/></a>
  <a href="https://github.com/power0matin/linux-package-source-manager/issues"><img src="https://img.shields.io/github/issues/power0matin/linux-package-source-manager?style=flat-square&amp;label=Issues&amp;labelColor=18181B&amp;color=22C55E&amp;logo=github&amp;logoColor=white" alt="GitHub Issues"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/power0matin/linux-package-source-manager?style=flat-square&amp;label=License&amp;labelColor=18181B&amp;color=EF4444&amp;logo=github&amp;logoColor=white" alt="GitHub License"/></a>
</p>
<!-- repo-badges:end -->

[![CI](https://github.com/power0matin/linux-package-source-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/power0matin/linux-package-source-manager/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![ShellCheck](https://img.shields.io/badge/ShellCheck-passing-brightgreen.svg)](https://www.shellcheck.net/)
[![Latest release](https://img.shields.io/github/v/release/power0matin/linux-package-source-manager?style=flat-square&label=latest%20release&labelColor=18181B&color=F97316)](https://github.com/power0matin/linux-package-source-manager/releases)

Ubuntu-first Linux package source and mirror manager for APT, Python, Node.js, and Docker/OCI.

Linux Package Source Manager is an Ubuntu-first Linux package source and mirror manager for servers and developer environments. It currently supports Ubuntu APT mirrors, Python indexes for pip, uv and Poetry, Node.js registries for npm, pnpm and Yarn, and Docker/OCI registry mirrors. It provides interactive terminal workflows, read-only diagnostics, safe previews, validated snapshots and conflict-aware restore.

> **Current source version:** `v3.0.5`. The standalone release artifact is `linux-package-source-manager.sh`. Releases through `v3.0.2` retain the historical `power-apt-boost.sh` asset; internal configuration and backup identifiers remain unchanged. The stable bootstrap is `install.sh`; it downloads and verifies the pinned release.

## Quick Start

Open the interactive menu on a new Ubuntu server with one command:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/power0matin/linux-package-source-manager/main/install.sh)
```

The bootstrap downloads the pinned `v3.0.5` release, verifies the application against its published SHA-256 checksum, checks Bash syntax, and opens the menu. It requests `sudo` automatically when the current shell is not already root.

For read-only commands, pass the desired arguments after the bootstrap:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/power0matin/linux-package-source-manager/main/install.sh) --status
bash <(curl -fsSL https://raw.githubusercontent.com/power0matin/linux-package-source-manager/main/install.sh) --doctor
```

For a confirmed non-interactive change, specify the action and add `--yes`. The `--yes` flag alone does not select an action:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/power0matin/linux-package-source-manager/main/install.sh) --mirror https://mirror.example.com/ubuntu --yes
```

Preview a mirror change without modifying APT configuration:

```bash
sudo bash linux-package-source-manager.sh --dry-run
```

The bootstrap is a launcher only. It does not install a daemon, create a systemd unit, or add a scheduled task.

## Features

- Ubuntu codename detection and a versioned catalog of built-in, Ubuntu-index and user-defined mirrors
- Strict mirror URL and catalog-record validation, including provenance and official-host status
- Last-known-good Ubuntu mirror index cache with TTL, schema checks and failure fallback
- Region selection and an official-only benchmark profile
- Bounded parallel probes with configurable worker limits and transient retry policy
- Ubuntu Release origin, suite, codename, metadata-age and archive-signature verification for main, updates and security
- Deterministic benchmark score: average endpoint latency plus 50 ms per redirect
- Plain Bash numbered menu rendered directly in the current SSH terminal; no `whiptail` dependency
- English-only menu prompts, explicit result messages and Enter-to-continue pauses
- Per-mirror benchmark/list progress (`completed/total`) with elapsed time and estimated remaining time
- Step-by-step progress for Python, Node.js and Docker registry endpoint checks
- Python package-source screen for pip, uv and Poetry; pipx is detected but its app environments are not changed
- Read-only Python tool inventory and HTTPS PEP 503/691 index plus artifact checks without installing packages
- Scoped pip index configuration and managed uv/Poetry TOML source blocks with preview, snapshots and conflict-safe restore
- Node.js registry manager for npm, pnpm, Yarn Classic and Yarn Berry
- Read-only Node.js/package-manager detection and HTTPS registry metadata plus tarball-host checks using HEAD only
- User-level registry changes and explicit project-scope changes with redacted previews, snapshots and conflict-checked rollback
- Scoped registries, authentication entries, Yarn Berry publish registry, package manifests and lockfiles are preserved
- Overview, APT management, mirror benchmark, Backup/Restore, Diagnostics and session Settings screens
- Safe apply and restore previews with confirmation; `--yes` is required to bypass prompts in non-interactive sessions
- Fail-closed APT snapshots with SHA-256 validation and exact restore for new snapshots
- Atomic APT configuration writes and a mutation lock
- IPv4/IPv6-aware probing and matching APT network configuration
- Read-only `--status` and `--doctor` commands
- Versioned JSON reports for CLI automation
- `--skip-update` preserves existing package lists and downloaded package archives
- Offline regression suite across Ubuntu 20.04, 22.04 and 24.04

## Installation

### Recommended: interactive one-liner

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/power0matin/linux-package-source-manager/main/install.sh)
```

This command requires Bash and curl. The bootstrap downloads the standalone script and checksum from the pinned `v3.0.5` GitHub Release, verifies SHA-256, runs `bash -n`, and starts the interactive menu in the current terminal. It does not require cloning the repository or manually writing a script file.

The application is run with root privileges because its APT and Docker system-management features require them. When launched as a regular user, the bootstrap checks that `sudo` is available and requests authorization. When launched as root, it runs without an additional `sudo` prompt.

### Pass CLI arguments

The bootstrap forwards arguments to the main application. Read-only status and diagnostics can be run without opening the menu:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/power0matin/linux-package-source-manager/main/install.sh) --status
bash <(curl -fsSL https://raw.githubusercontent.com/power0matin/linux-package-source-manager/main/install.sh) --doctor
```

For non-interactive changes, include the specific action and `--yes` to approve it. `--yes` alone does not select an action:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/power0matin/linux-package-source-manager/main/install.sh) --mirror https://mirror.example.com/ubuntu --yes
```

### Manual installation from a pinned release

To inspect and verify the release artifact yourself, download both files, verify the checksum, then launch the menu:

```bash
VERSION="v3.0.5"
curl -fL "https://github.com/power0matin/linux-package-source-manager/releases/download/${VERSION}/linux-package-source-manager.sh" -o linux-package-source-manager.sh
curl -fL "https://github.com/power0matin/linux-package-source-manager/releases/download/${VERSION}/linux-package-source-manager.sh.sha256" -o linux-package-source-manager.sh.sha256
sha256sum -c linux-package-source-manager.sh.sha256
sudo bash linux-package-source-manager.sh --menu
```

For a source checkout instead:

```bash
git clone https://github.com/power0matin/linux-package-source-manager.git
cd linux-package-source-manager
git checkout v3.0.5
sudo bash linux-package-source-manager.sh --menu
```

### Inspect the bootstrap before execution

The bootstrap is a small, readable Bash file and is also attached to each release. Review it before running:

```bash
curl -fsSL https://raw.githubusercontent.com/power0matin/linux-package-source-manager/main/install.sh | less
```

### What the bootstrap verifies

- Downloads `linux-package-source-manager.sh` and its SHA-256 file from the same pinned GitHub Release.
- Checks the application against the published checksum and stops on a mismatch.
- Runs `bash -n` before executing the application.
- Uses a private temporary directory and removes it on exit.
- Forwards CLI arguments and preserves the caller's terminal input for the interactive menu.
- Does not install a daemon, create a systemd unit, or alter shell startup files.

A SHA-256 checksum detects an incomplete or altered application when it does not match the published checksum. It is not a detached cryptographic signature; review the script and release provenance when your threat model requires independent authenticity verification.

## Mirror catalog and benchmark

The mirror catalog combines three sources:

- **Built-in:** reviewed archive hosts bundled with the script. The official-only profile uses only entries explicitly marked as official in this catalog.
- **Ubuntu index:** candidates returned by `http://mirrors.ubuntu.com/mirrors.txt`. Ubuntu publishes this discovery list over HTTP; the response is treated only as an untrusted candidate list, never as an official-host assertion or executable configuration. Fetch redirects are restricted to HTTPS in both the curl and wget paths, and every candidate must independently pass the local Ubuntu Release metadata and archive-signature checks before it can be selected. Discovery is refreshed at most once per 24 hours unless `--refresh-catalog` is requested. The last-known-good cache is stored at `/var/cache/power-apt-boost/ubuntu-index-v1.tsv` with root-only permissions.
- **Custom:** user-managed entries stored at `/etc/power-apt-boost/custom-mirrors-v1.tsv`, with root-only permissions. Adding a custom entry requires a successful live verification of all three Ubuntu suites.

A candidate is eligible only when the main, updates and security `InRelease` files return HTTP 200, identify the expected Ubuntu origin/suite/codename, have metadata no older than seven days (and a non-expired `Valid-Until` when present), and pass `gpgv` verification with the local Ubuntu archive keyring. Redirects must remain on the same host and cannot downgrade HTTPS to HTTP. Missing signature-verification support fails closed.

The deterministic ranking score is:

`average(InRelease endpoint latency) + 0.050 seconds × redirect count`

Only eligible mirrors are ranked. Benchmark workers are bounded to 1–8 and transient probe retries to 0–3. Benchmark and list operations do not install packages or edit APT configuration.

## Usage

### Interactive menu

Run without arguments in a terminal:

```bash
sudo bash linux-package-source-manager.sh
```

The menu provides Overview, APT management, Benchmark, Backup/Restore, Diagnostics and session Settings. It always renders numbered options directly in the current SSH terminal; users select actions with numbers. The screen is cleared only when a new menu is shown, while operation output remains visible until the user presses Enter to continue. No `whiptail` or additional dialog package is required.

### Read-only status and diagnostics

```bash
sudo bash linux-package-source-manager.sh --status
sudo bash linux-package-source-manager.sh --doctor
sudo bash linux-package-source-manager.sh --status --json
sudo bash linux-package-source-manager.sh --doctor --json
```

`--status` reports the detected OS, APT source files, current managed mirror and available backups. `--doctor` checks local dependencies, permissions, the Ubuntu archive keyring and backup visibility. These commands do not change the system.

### Python package sources

Python package-source commands do not require root for user or project scopes. They never install packages, edit dependency declarations, or update lockfiles.

Inspect detected tools and pip index scopes:

```bash
bash linux-package-source-manager.sh --python-status
bash linux-package-source-manager.sh --python-status --json
```

Test a PyPI-compatible Simple API endpoint without installing a package. The check reads the `pip` project metadata and verifies one advertised distribution endpoint:

```bash
bash linux-package-source-manager.sh --python-test-index https://pypi.org/simple/
```

Preview and then configure the pip user index:

```bash
bash linux-package-source-manager.sh --python-set-index https://pypi.org/simple/ --python-client pip --python-scope user --dry-run
bash linux-package-source-manager.sh --python-set-index https://pypi.org/simple/ --python-client pip --python-scope user
```

For an active virtual environment, use `--python-scope site`; `auto` selects the active venv when present and otherwise selects user scope. The global scope requires root and is blocked when PEP 668 marks the interpreter as externally managed.

Configure uv in user or project scope:

```bash
bash linux-package-source-manager.sh --python-set-index https://pypi.org/simple/ --python-client uv --python-scope user --dry-run
bash linux-package-source-manager.sh --python-set-index https://pypi.org/simple/ --python-client uv --python-scope project --python-project pyproject.toml --dry-run
```

Add a Poetry source to a project file. Supplemental is the default and preserves the implicit PyPI source:

```bash
bash linux-package-source-manager.sh --python-set-index https://pypi.org/simple/ --python-client poetry --python-scope project --python-project pyproject.toml --python-priority supplemental --dry-run
```

Poetry `primary` sources disable implicit PyPI; `explicit` sources require package-specific source pins. The tool never edits those dependency pins. Existing private sources and project index declarations are preserved; a duplicate source name or an existing uv default index causes a safe refusal.

Reset only a source managed by Linux Package Source Manager, or restore a snapshot after checking that the target has not changed since the snapshot:

```bash
bash linux-package-source-manager.sh --python-reset-index --python-client pip --python-scope user
bash linux-package-source-manager.sh --python-reset-index --python-client uv --python-scope project --python-project pyproject.toml
bash linux-package-source-manager.sh --python-restore /path/to/python/snapshot
```

uv and Poetry editing requires Python 3.11+ (`tomllib`) or an already-installed `tomli` module. No TOML parser or package manager is installed automatically. pipx is included in tool detection only; this phase deliberately does not rewrite the separate virtual environments managed by pipx.


### Node.js package registries

Node.js registry operations do not require root. Linux Package Source Manager detects Node.js, npm, pnpm and Yarn Classic/Berry without installing any package manager.

Inspect the available tools and effective registry hosts:

```bash
bash linux-package-source-manager.sh --node-status
bash linux-package-source-manager.sh --node-status --json
```

Test an npm-compatible registry using package metadata and a HEAD request to the advertised tarball URL. The check does not download the archive:

```bash
bash linux-package-source-manager.sh --node-test-registry https://registry.npmjs.org/
bash linux-package-source-manager.sh --node-test-registry https://registry.npmjs.org/ --node-test-package @acme/example
```

Preview and then configure the user-level registry:

```bash
bash linux-package-source-manager.sh --node-set-registry https://registry.npmjs.org/ --node-client npm --dry-run
bash linux-package-source-manager.sh --node-set-registry https://registry.npmjs.org/ --node-client npm --yes
```

The default scope is the selected package manager's user configuration. Project configuration is opt-in and requires both --node-scope project and an explicit directory containing package.json:

```bash
bash linux-package-source-manager.sh --node-set-registry https://registry.npmjs.org/ \\
  --node-client pnpm --node-scope project --node-project /path/to/project --dry-run
```

Only the default fetch-registry key is changed. Existing scoped registries, authentication settings and unrelated options are retained. The tool does not edit package.json, publishConfig, workspace files or lockfiles. Yarn Berry's separate npmPublishRegistry is not changed; other package-manager publish commands may fall back to the default registry when no explicit publish registry is configured.

Reset only the app-managed setting or restore a snapshot after checking for external edits:

```bash
bash linux-package-source-manager.sh --node-reset-registry --node-client npm --yes
bash linux-package-source-manager.sh --node-restore /path/to/nodejs/snapshot
```

Node.js registry URLs must use HTTPS and cannot contain embedded credentials, query strings or fragments. Existing environment overrides cause mutating operations to refuse rather than write a configuration that would be shadowed. --yes is required for non-interactive changes; --dry-run previews the target without writing it.


### Docker Engine and OCI registries

Linux Package Source Manager treats the Docker Engine **APT repository** and Docker Hub **OCI image registry mirrors** as separate systems. The first provides Docker Engine packages through APT; the second changes where the daemon looks when pulling container images. This manager currently targets the system/rootful Linux daemon at `/etc/docker/daemon.json`; rootless Docker and Docker Desktop are outside this phase.

Inspect the current setup without changing it:

```bash
sudo bash linux-package-source-manager.sh --docker-status
sudo bash linux-package-source-manager.sh --docker-status --json
sudo bash linux-package-source-manager.sh --docker-catalog
```

Test an HTTPS Docker Registry V2 endpoint. This sends an unauthenticated `GET /v2/` request only; it does not authenticate, pull an image or download image layers:

```bash
sudo bash linux-package-source-manager.sh --docker-test-mirror https://mirror.gcr.io
```

Preview and configure the Docker daemon mirror list:

```bash
sudo bash linux-package-source-manager.sh --docker-set-mirror https://mirror.gcr.io --dry-run
sudo bash linux-package-source-manager.sh --docker-set-mirror https://mirror.gcr.io --yes
```

Configuration merges the selected origin into `/etc/docker/daemon.json` under `registry-mirrors`. Existing JSON settings and mirror entries are preserved. The operation requires an existing `/etc/docker` directory and an installed `dockerd` that accepts `--validate`; malformed JSON, unsupported mirror-list types and invalid daemon configuration are rejected. A restricted snapshot is created before writing, and rollback refuses to overwrite edits made after the change.

**The Docker daemon is not restarted by configuration.** Review workload impact, then request a separate restart:

```bash
sudo bash linux-package-source-manager.sh --docker-restart
```

The restart command requires a separate confirmation and only operates on an already-active Docker systemd service. A restart can interrupt running workloads. To restore the previous configuration without restarting Docker:

```bash
sudo bash linux-package-source-manager.sh --docker-reset-mirror
sudo bash linux-package-source-manager.sh --docker-restore /var/backups/power-apt-boost/docker/snapshot.xxxxxxxx
```

The built-in `mirror.gcr.io` candidate is Google's cache of frequently requested public Docker Hub images, not a complete mirror. A cache miss may fall back to Docker Hub. Passing a Registry V2 endpoint probe confirms protocol compatibility only; it does not prove that an arbitrary endpoint is configured as a pull-through cache.

References: [Docker daemon configuration and validation](https://docs.docker.com/reference/cli/dockerd/), [Google Artifact Registry cached Docker Hub images](https://docs.cloud.google.com/artifact-registry/docs/pull-cached-dockerhub-images), [Docker Registry API V2](https://github.com/distribution/distribution/blob/main/docs/content/spec/api.md).

### Apply a mirror

```bash
sudo bash linux-package-source-manager.sh --mirror https://mirror.example.com/ubuntu
```

In a terminal, review the preview and confirm before applying. In a non-interactive session, pass `--yes` explicitly.

### Test without changing anything

```bash
sudo bash linux-package-source-manager.sh --dry-run
```

### Restore from backup

```bash
sudo bash linux-package-source-manager.sh --restore
```

Restore displays the selected snapshot and managed paths before confirmation. Use `--restore-path PATH` to select a specific snapshot.

### List and test all mirrors

```bash
sudo bash linux-package-source-manager.sh --list
```

### Machine-readable output

```bash
sudo bash linux-package-source-manager.sh --status --json
sudo bash linux-package-source-manager.sh --doctor --json
sudo bash linux-package-source-manager.sh --yes --json
```

All JSON reports use schema version 1. `--json` suppresses interactive decoration; list details are written to stderr while its summary report is written to stdout.

### Filter mirrors by country

```bash
sudo bash linux-package-source-manager.sh --country us
```

### Verbose output for debugging

```bash
sudo bash linux-package-source-manager.sh --verbose
```

## Options

| Option | Description |
|--------|-------------|
| `-h`, `--help` | Show help message |
| `-v`, `--version` | Show version |
| `-m`, `--mirror URL` | Test and use a specific mirror |
| `-r`, `--restore` | Restore APT config from latest backup |
| `--restore-path PATH` | Restore from a specific backup |
| `--restore-scope SCOPE` | Restore all APT config, sources only, or network settings only |
| `--prune-backups N` | Keep N newest verified snapshots; remove older verified snapshots |
| `--dry-run` | Test mirrors and preview without changing config |
| `--skip-update` | Apply config but skip `apt-get update`; preserve existing APT lists and archive cache |
| `--list` | List available mirrors and test all three repository suites |
| `--menu` | Open the interactive terminal menu |
| `--status` | Show read-only system and APT status |
| `--doctor` | Run read-only local health checks |
| `--network-diagnostics` | Run bounded live DNS/TLS checks; requires `--doctor` |
| `-y`, `--yes` | Explicitly confirm apply/restore/cleanup in non-interactive mode |
| `--json` | Output reports using JSON schema version 1 |
| `--verbose` | Show detailed output |
| `--quiet` | Suppress non-essential output |
| `--no-spinner` | Disable spinner |
| `--timeout SECS` | Probe and APT network timeout in seconds (1-300, default 20) |
| `--apt-retries N` | APT network retries (0-10, default 3) |
| `--proxy URL` | Set HTTP/HTTPS APT proxy (no embedded credentials) |
| `--clear-proxy` | Explicitly bypass APT proxies with `DIRECT` |
| `--workers N` | Mirror benchmark concurrency (1-8) |
| `--retries N` | Retry transient mirror probe failures (0-3) |
| `--refresh-catalog` | Refresh Ubuntu mirror discovery before listing/benchmarking |
| `--official-only` | Limit the catalog to built-in official Ubuntu archive hosts |
| `--add-mirror URL` | Verify and save a custom mirror |
| `--remove-mirror ID` | Remove a saved custom mirror |
| `--disable-mirror ID` | Disable a saved custom mirror |
| `--enable-mirror ID` | Enable a saved custom mirror |
| `--country CODE` | Filter mirrors by supported two-letter country code |
| `--ipv6` | Use IPv6 for mirror testing and generated APT config |
| `--log-file PATH` | Write log to file |
| `--python-status` | Inspect Python, pip, pipx, uv, Poetry, venv and pip index scopes |
| `--python-test-index URL` | Test HTTPS PEP 503/691 metadata and one distribution endpoint without installing it |
| `--python-set-index URL` | Set the selected pip/uv/Poetry source after preview and confirmation |
| `--python-reset-index` | Restore/remove only a source previously managed by this tool |
| `--python-restore PATH` | Restore a conflict-checked Python configuration snapshot |
| `--python-client NAME` | Select `pip`, `uv` or `poetry` (default `pip`) |
| `--python-scope SCOPE` | Select `auto`, `user`, `site`, `global` or `project` |
| `--python-project PATH` | Select the `uv.toml` / `pyproject.toml` target |
| `--python-source-name NAME` | Name the managed uv/Poetry source |
| `--python-priority VALUE` | Poetry priority: `supplemental`, `primary` or `explicit` |

## What It Does

1. **Inspects** active APT source records from `sources.list`, `.list` and `.sources` files, including third-party and duplicate records.
2. **Detects** Ubuntu codename and system architecture.
3. **Builds** an architecture-compatible catalog: standard archive plus a separate security pocket on amd64/i386, or the Ubuntu ports archive on other architectures.
4. **Tests** mirror `InRelease` endpoints for main, updates and security; checks suite/codename, metadata freshness, redirect policy and Ubuntu archive signatures.
5. **Ranks** only verified candidates using average endpoint latency plus a fixed redirect penalty.
6. **Previews** the exact managed APT source and network configuration before an approved apply.
7. **Creates** a checksum-validated snapshot, writes managed files atomically and verifies the generated configuration with APT's own parser.
8. **Runs** `apt-get update` unless `--skip-update` is selected; a failed write or update restores the previous APT configuration.

## What It Changes

| File | Action |
|------|--------|
| `/etc/apt/sources.list.d/ubuntu.sources` | Created or updated only when tool-managed or containing only recognized Ubuntu archive entries; unexpected repositories cause a safe refusal |
| `/etc/apt/apt.conf.d/99-power-apt-boost` | Created or updated only when tool-managed; symlinks and unmanaged files are refused |
| `/etc/apt/sources.list` | Removed only when every active source is a recognized Ubuntu archive; third-party, ESM and unclassified entries are preserved |
| Other `sources.list.d/*.list` and `*.sources` files | Read for inventory, otherwise left untouched |
| `/var/backups/power-apt-boost/` | Validated APT snapshots (archive, manifest and SHA-256 checksum) |
| `/run/lock/power-apt-boost.lock` | Mutation lock file |

## Backup & Restore

### Automatic backups

Backups are created at:

```
/var/backups/power-apt-boost/YYYY-MM-DD_HH-MM-SS/
```

Each new-format backup contains:
- `apt-config.tar`: a metadata-preserving archive of the managed APT source/config paths
- `manifest`: prior path-existence state and snapshot format version
- `archive.sha256`: checksum used to validate the archive before restore

Legacy snapshots remain readable, but they do not record absent paths and therefore cannot guarantee exact reconstruction of files that were not present when they were created.

### Restore from latest backup

```bash
sudo bash linux-package-source-manager.sh --restore
```

### Restore from specific backup

```bash
sudo bash linux-package-source-manager.sh --restore-path /var/backups/power-apt-boost/2025-01-01_12-00-00
```

### Manual restore

Prefer the script's `--restore` / `--restore-path` command. New snapshots record the existence state of the complete managed APT source/config directories, include a SHA-256 checksum, and restore those paths as a unit. Legacy snapshots remain readable but cannot guarantee exact removal of files that did not exist when they were created.

## Ubuntu APT source safety and network controls

### Source inventory

`--status` and `--status --json` report the number of active source records, recognized Ubuntu archive records, third-party records and duplicate URI/suite pairs. The inventory reads legacy `sources.list` plus `.list` and Deb822 `.sources` files. It does not change them.

### Archive, security and architecture handling

On amd64/i386, the selected mirror serves the release, updates and backports suites; the security suite stays on `security.ubuntu.com`. On other architectures, the ports archive serves all four suites. Generated entries retain `Signed-By` pointing to the local Ubuntu archive keyring. The apply path checks the source layout and asks APT to parse the resulting configuration before reporting success.

### Third-party source preservation

Linux Package Source Manager does not rewrite separate third-party source files. It refuses to replace an unmanaged or mixed `ubuntu.sources` file, and refuses to replace a managed file if an additional repository stanza has been added to it. It also preserves `sources.list` when it contains non-archive, ESM or unclassified entries. Move unrelated repositories into their own `.list` or `.sources` file rather than combining them with the tool-managed Ubuntu file.

### APT proxy and retry configuration

```bash
sudo bash linux-package-source-manager.sh --proxy http://127.0.0.1:3128 --timeout 45 --apt-retries 5
sudo bash linux-package-source-manager.sh --clear-proxy
```

The proxy URL accepts only an HTTP(S) host and optional port. Usernames, passwords, paths, query strings and fragments are rejected; use an APT-supported credential mechanism separately when authentication is required. With no proxy option, an existing proxy directive in the managed file and settings in other APT config files are preserved. `--clear-proxy` explicitly writes `DIRECT`.

### Diagnostics

```bash
sudo bash linux-package-source-manager.sh --doctor
sudo bash linux-package-source-manager.sh --doctor --network-diagnostics
```

The default doctor checks local APT trust prerequisites, suspicious insecure-source overrides, duplicate source records, cached InRelease file age and configured proxy presence. Live DNS and TLS checks run only when `--network-diagnostics` is supplied.

### Selective restore and backup cleanup

```bash
sudo bash linux-package-source-manager.sh --restore --restore-scope sources
sudo bash linux-package-source-manager.sh --restore --restore-scope network
sudo bash linux-package-source-manager.sh --prune-backups 5 --yes
```

Restore scope can be `all`, `sources` or `network`. A network-only restore does not run `apt-get update`; source and full restores do. Backup cleanup considers only format-1 snapshots with a valid SHA-256 manifest, retains the requested number of newest snapshots and asks for confirmation. Non-interactive cleanup requires `--yes`. Legacy or invalid snapshots are not deleted by the cleanup command.

## What It Does NOT Change

The tool does not:

- Install, upgrade or remove application packages or Python dependencies.
- Edit dependency declarations, package pins, hashes or lockfiles.
- Rewrite pipx-managed application environments; pipx is detected for inventory only.
- Change firewall rules, routes, DNS resolver configuration, VPN settings or SSH configuration.
- Manage Go, Rust, PHP, Java or other ecosystems not listed in the current feature set.

**Filesystem effects outside `/etc/apt`:** the tool creates validated snapshots under `/var/backups/power-apt-boost/` and a mutation lock under `/run/lock/`. It no longer manually deletes APT package lists or clears the archive cache. `apt-get update` still performs its normal package-index maintenance.

## Mirror Testing

Linux Package Source Manager tests each mirror against three endpoints:

```
/dists/<codename>/InRelease
/dists/<codename>-updates/InRelease
/dists/<codename>-security/InRelease
```

A candidate is eligible only when all three endpoints return HTTP 200, match the expected Ubuntu origin/suite/codename, pass freshness and same-host redirect checks, and verify against the local Ubuntu archive keyring. The selector measures endpoint response time; it is not a sustained bandwidth benchmark. The deterministic score is the average endpoint latency plus 50 ms per redirect. Concurrency is bounded to 1-8 workers, and `--list` uses the same compatibility checks.

### Default mirrors

Iranian mirrors are tested first for geographic optimization, then international mirrors as fallback.

| Region | Mirrors |
|--------|---------|
| Iran | `ir.archive.ubuntu.com`, `mirror.arvancloud.ir`, `mirror.iranserver.com`, `ubuntu.hostiran.ir`, `mirror.hostbaran.com`, `mirror.aminidc.com`, `archive.ito.gov.ir`, `archive.ubuntu.petiak.ir`, `mirror.mobinhost.com`, `linuxmirrors.ir`, `mirror.kubarcloud.com` |
| Global | `archive.ubuntu.com`, `mirrors.kernel.org` |
| US | `us.archive.ubuntu.com`, `mirror.math.princeton.edu`, `mirror.cs.uchicago.edu`, `mirror.csclub.uwaterloo.ca`, `mirror.rit.edu`, `mirror.arizona.edu` |
| UK | `uk.archive.ubuntu.com` |
| Europe | `de.archive.ubuntu.com`, `fr.archive.ubuntu.com`, `it.archive.ubuntu.com`, `nl.archive.ubuntu.com` |
| Asia-Pacific | `au.archive.ubuntu.com`, `jp.archive.ubuntu.com`, `kr.archive.ubuntu.com`, `in.archive.ubuntu.com` |
| Americas | `br.archive.ubuntu.com` |

### Iranian Ubuntu Mirrors

Linux Package Source Manager includes a dedicated **Iranian mirror pool** for users located in Iran. These mirrors are tested first for geographic optimization — reducing benchmark time for Iranian users.

Iranian mirrors included in the default pool:

| Mirror | URL |
|--------|-----|
| Ubuntu Iran Archive | `https://ir.archive.ubuntu.com/ubuntu` |
| ArvanCloud | `https://mirror.arvancloud.ir/ubuntu` |
| IranServer | `https://mirror.iranserver.com/ubuntu` |
| HostIran | `https://ubuntu.hostiran.ir/ubuntu` |
| HostBaran | `https://mirror.hostbaran.com/ubuntu` |
| AminiDC | `https://mirror.aminidc.com/ubuntu` |
| ITO | `https://archive.ito.gov.ir/ubuntu` |
| Petiak | `https://archive.ubuntu.petiak.ir/ubuntu` |
| MobinHost | `https://mirror.mobinhost.com/ubuntu` |
| LinuxMirrors | `https://linuxmirrors.ir/ubuntu` |
| KubarCloud | `https://mirror.kubarcloud.com/ubuntu` |

To filter mirrors by Iran specifically:

```bash
sudo bash linux-package-source-manager.sh --country ir
```

To use a specific Iranian mirror:

```bash
sudo bash linux-package-source-manager.sh --mirror https://mirror.arvancloud.ir/ubuntu
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error (unexpected execution or lock failure) |
| 2 | Usage error (invalid or unknown arguments) |

| 3 | Network or `apt-get update` failure |
| 4 | Root privileges required |
| 5 | Unsupported operating system |
| 6 | No working mirror found |
| 7 | Backup creation failed |
| 8 | Restore or rollback failed |

## Troubleshooting

### "This script must be run as root"

```bash
sudo bash linux-package-source-manager.sh
```

### "curl or wget is required"

```bash
apt-get install -y curl
```

### "No working mirror found"

- Check your network connection
- Try with a longer timeout: `--timeout 60`
- Try a specific mirror: `--mirror https://archive.ubuntu.com/ubuntu`

### "apt-get update failed after applying mirror"

The script automatically restores the previous configuration. To restore manually:

```bash
sudo bash linux-package-source-manager.sh --restore
```

### Third-party sources warning

If you have third-party APT sources in `/etc/apt/sources.list`, Linux Package Source Manager preserves them and only removes the file if it contains only Ubuntu sources.

## Compatibility

| Ubuntu Version | Current CI coverage |
|---------------|---------------------|
| 24.04 LTS Noble | 186 offline tests (includes TOML edit/restore coverage) |
| 22.04 LTS Jammy | 168 offline tests (TOML parser unavailable path) |
| 20.04 LTS Focal | 168 offline tests (TOML parser unavailable path) |

CI also runs ShellCheck and shfmt. Offline tests cover APT parsing, inventory, backup/restore, config ownership, proxy validation, architecture-specific archive selection, rollback, mirror compatibility, Python index validation, PEP 668, private-source preservation and snapshot conflict handling. TOML edit/restore paths run where Python 3.11+ `tomllib` or an existing `tomli` is available; older images verify fail-closed behavior. Live public mirror reachability, real archive-signature checks, external DNS/TLS and live PyPI mirror/artifact reachability are not CI prerequisites. [Latest Phase 5 CI run](https://github.com/power0matin/linux-package-source-manager/actions/runs/44647360924). Requires Bash 4.0+ and one of: curl, wget.

## Security

- See [SECURITY.md](SECURITY.md) for reporting vulnerabilities
- Review the script before running from a URL
- Use `--dry-run` to preview changes
- A checksum-validated snapshot is required before APT configuration changes. File writes are atomic; failed writes or `apt-get update` restore the previous managed APT configuration.
- Snapshots cover APT source/configuration paths only. They do not snapshot installed packages or restore package-index/cache side effects performed internally by `apt-get update`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

```bash
# Development setup
git clone https://github.com/power0matin/linux-package-source-manager.git
cd linux-package-source-manager
chmod +x linux-package-source-manager.sh

# Lint
shellcheck -x linux-package-source-manager.sh install.sh tests/test_installer.sh
shfmt -d linux-package-source-manager.sh install.sh tests/test_installer.sh

# Test
bash tests/run_tests.sh
bash tests/test_installer.sh
```

## Roadmap

See [ROADMAP.md](ROADMAP.md) for planned features.

## License

[MIT](LICENSE)

## Author

**Matin Shahabadi** — [@power0matin](https://github.com/power0matin)

## Contact

**Matin Shahabadi**

- Website: [matinshahabadi.ir](https://matinshahabadi.ir)
- Email: [me@matinshahabadi.ir](mailto:me@matinshahabadi.ir)
- GitHub: [power0matin](https://github.com/power0matin)
- LinkedIn: [matin-shahabadi](https://www.linkedin.com/in/matin-shahabadi)

<p align="center">
  <b>If this helped you, consider giving it a star!</b><br>
  <sub>Your support keeps the project alive and helps others find it.</sub>
</p>

<!-- Copy-paste in your Readme.md file -->
<p align="center">
  <a href="https://next.ossinsight.io/widgets/official/analyze-repo-stars-history?repo_id=1238487780" target="_blank" style="display: block" align="center">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://next.ossinsight.io/widgets/official/analyze-repo-stars-history/thumbnail.png?repo_id=1238487780&amp;image_size=auto&amp;color_scheme=dark" width="721" height="auto">
      <img alt="Star History of power0matin/linux-package-source-manager" src="https://next.ossinsight.io/widgets/official/analyze-repo-stars-history/thumbnail.png?repo_id=1238487780&amp;image_size=auto&amp;color_scheme=light" width="721" height="auto">
    </picture>
  </a>
</p>

<!-- Made with [OSS Insight](https://ossinsight.io/) -->

<p align="center">
  Created by <a href="https://github.com/power0matin">power0matin</a>
</p>
