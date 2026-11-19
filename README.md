<h1 align="center">Power APT Boost</h1>

<!-- repo-badges:start -->
<p align="center">
  <a href="https://hits.sh/github.com/power0matin/power-apt-boost/"><img src="https://hits.sh/github.com/power0matin/power-apt-boost.svg?style=flat-square&amp;label=Views&amp;labelColor=18181B&amp;color=0EA5E9&amp;logo=github" alt="Repository Views"/></a>
  <a href="https://github.com/power0matin/power-apt-boost/stargazers"><img src="https://img.shields.io/github/stars/power0matin/power-apt-boost?style=flat-square&amp;label=Stars&amp;labelColor=18181B&amp;color=F59E0B&amp;logo=github&amp;logoColor=white" alt="GitHub Stars"/></a>
  <a href="https://github.com/power0matin/power-apt-boost/forks"><img src="https://img.shields.io/github/forks/power0matin/power-apt-boost?style=flat-square&amp;label=Forks&amp;labelColor=18181B&amp;color=6366F1&amp;logo=github&amp;logoColor=white" alt="GitHub Forks"/></a>
  <a href="https://github.com/power0matin/power-apt-boost/issues"><img src="https://img.shields.io/github/issues/power0matin/power-apt-boost?style=flat-square&amp;label=Issues&amp;labelColor=18181B&amp;color=22C55E&amp;logo=github&amp;logoColor=white" alt="GitHub Issues"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/power0matin/power-apt-boost?style=flat-square&amp;label=License&amp;labelColor=18181B&amp;color=EF4444&amp;logo=github&amp;logoColor=white" alt="GitHub License"/></a>
</p>
<!-- repo-badges:end -->

[![CI](https://github.com/power0matin/power-apt-boost/actions/workflows/ci.yml/badge.svg)](https://github.com/power0matin/power-apt-boost/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![ShellCheck](https://img.shields.io/badge/ShellCheck-passing-brightgreen.svg)](https://www.shellcheck.net/)
[![Latest release](https://img.shields.io/github/v/release/power0matin/power-apt-boost?style=flat-square&label=latest%20release&labelColor=18181B&color=F97316)](https://github.com/power0matin/power-apt-boost/releases)

Fast Ubuntu APT mirror selector and network optimizer.

Power APT Boost is an Ubuntu APT mirror manager with an interactive terminal menu, safe configuration previews, validated backups, exact restore, and read-only diagnostics. Its apply path tests repository endpoints, selects a working mirror, writes managed APT configuration atomically, and verifies the result with `apt-get update`.

> **Version status:** The `main` source currently declares `3.0.0`, while the latest published GitHub release is `v2.1.0`. There is no published `v3.0.0` tag/release yet. The recommended install command below is pinned to `v2.1.0`; use `main` only when you intentionally want unreleased source.

## Quick Start

On a terminal, clone the repository and open the interactive menu:

```bash
git clone https://github.com/power0matin/power-apt-boost.git
cd power-apt-boost
sudo bash power-apt-boost.sh
```

For an intentional non-interactive apply from a pipe or CI job, pass `--yes` explicitly:

```bash
curl -fsSL https://raw.githubusercontent.com/power0matin/power-apt-boost/main/power-apt-boost.sh | sudo bash -s -- --yes
```

Preview a mirror change without modifying APT configuration:

```bash
sudo bash power-apt-boost.sh --dry-run
```

## Features

- Ubuntu codename detection and a versioned catalog of built-in, Ubuntu-index and user-defined mirrors
- Strict mirror URL and catalog-record validation, including provenance and official-host status
- Last-known-good Ubuntu mirror index cache with TTL, schema checks and failure fallback
- Region selection and an official-only benchmark profile
- Bounded parallel probes with configurable worker limits and transient retry policy
- Ubuntu Release origin, suite, codename, metadata-age and archive-signature verification for main, updates and security
- Deterministic benchmark score: average endpoint latency plus 50 ms per redirect
- Numbered terminal menu, with optional `whiptail` dialogs when installed
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

### One-liner (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/power0matin/power-apt-boost/main/power-apt-boost.sh | sudo bash
```

### Manual

```bash
git clone https://github.com/power0matin/power-apt-boost.git
cd power-apt-boost
git checkout v2.1.0
sudo bash power-apt-boost.sh
```

### Verify before running

```bash
curl -fsSL https://raw.githubusercontent.com/power0matin/power-apt-boost/main/power-apt-boost.sh | less
# Review the script, then launch an interactive menu after saving it locally:
sudo bash power-apt-boost.sh
# Or explicitly approve a non-interactive run:
curl -fsSL https://raw.githubusercontent.com/power0matin/power-apt-boost/main/power-apt-boost.sh | sudo bash -s -- --yes
```

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
sudo bash power-apt-boost.sh
```

The menu provides Overview, APT management, Benchmark, Backup/Restore, Diagnostics and session Settings. It uses a numbered Bash menu by default and `whiptail` dialogs when that tool is already installed. No extra package is installed automatically.

### Read-only status and diagnostics

```bash
sudo bash power-apt-boost.sh --status
sudo bash power-apt-boost.sh --doctor
sudo bash power-apt-boost.sh --status --json
sudo bash power-apt-boost.sh --doctor --json
```

`--status` reports the detected OS, APT source files, current managed mirror and available backups. `--doctor` checks local dependencies, permissions, the Ubuntu archive keyring and backup visibility. These commands do not change the system.

### Apply a mirror

```bash
sudo bash power-apt-boost.sh --mirror https://mirror.example.com/ubuntu
```

In a terminal, review the preview and confirm before applying. In a non-interactive session, pass `--yes` explicitly.

### Test without changing anything

```bash
sudo bash power-apt-boost.sh --dry-run
```

### Restore from backup

```bash
sudo bash power-apt-boost.sh --restore
```

Restore displays the selected snapshot and managed paths before confirmation. Use `--restore-path PATH` to select a specific snapshot.

### List and test all mirrors

```bash
sudo bash power-apt-boost.sh --list
```

### Machine-readable output

```bash
sudo bash power-apt-boost.sh --status --json
sudo bash power-apt-boost.sh --doctor --json
sudo bash power-apt-boost.sh --yes --json
```

All JSON reports use schema version 1. `--json` suppresses interactive decoration; list details are written to stderr while its summary report is written to stdout.

### Filter mirrors by country

```bash
sudo bash power-apt-boost.sh --country us
```

### Verbose output for debugging

```bash
sudo bash power-apt-boost.sh --verbose
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
sudo bash power-apt-boost.sh --restore
```

### Restore from specific backup

```bash
sudo bash power-apt-boost.sh --restore-path /var/backups/power-apt-boost/2025-01-01_12-00-00
```

### Manual restore

Prefer the script's `--restore` / `--restore-path` command. New snapshots record the existence state of the complete managed APT source/config directories, include a SHA-256 checksum, and restore those paths as a unit. Legacy snapshots remain readable but cannot guarantee exact removal of files that did not exist when they were created.

## Ubuntu APT source safety and network controls

### Source inventory

`--status` and `--status --json` report the number of active source records, recognized Ubuntu archive records, third-party records and duplicate URI/suite pairs. The inventory reads legacy `sources.list` plus `.list` and Deb822 `.sources` files. It does not change them.

### Archive, security and architecture handling

On amd64/i386, the selected mirror serves the release, updates and backports suites; the security suite stays on `security.ubuntu.com`. On other architectures, the ports archive serves all four suites. Generated entries retain `Signed-By` pointing to the local Ubuntu archive keyring. The apply path checks the source layout and asks APT to parse the resulting configuration before reporting success.

### Third-party source preservation

Power APT Boost does not rewrite separate third-party source files. It refuses to replace an unmanaged or mixed `ubuntu.sources` file, and refuses to replace a managed file if an additional repository stanza has been added to it. It also preserves `sources.list` when it contains non-archive, ESM or unclassified entries. Move unrelated repositories into their own `.list` or `.sources` file rather than combining them with the tool-managed Ubuntu file.

### APT proxy and retry configuration

```bash
sudo bash power-apt-boost.sh --proxy http://127.0.0.1:3128 --timeout 45 --apt-retries 5
sudo bash power-apt-boost.sh --clear-proxy
```

The proxy URL accepts only an HTTP(S) host and optional port. Usernames, passwords, paths, query strings and fragments are rejected; use an APT-supported credential mechanism separately when authentication is required. With no proxy option, an existing proxy directive in the managed file and settings in other APT config files are preserved. `--clear-proxy` explicitly writes `DIRECT`.

### Diagnostics

```bash
sudo bash power-apt-boost.sh --doctor
sudo bash power-apt-boost.sh --doctor --network-diagnostics
```

The default doctor checks local APT trust prerequisites, suspicious insecure-source overrides, duplicate source records, cached InRelease file age and configured proxy presence. Live DNS and TLS checks run only when `--network-diagnostics` is supplied.

### Selective restore and backup cleanup

```bash
sudo bash power-apt-boost.sh --restore --restore-scope sources
sudo bash power-apt-boost.sh --restore --restore-scope network
sudo bash power-apt-boost.sh --prune-backups 5 --yes
```

Restore scope can be `all`, `sources` or `network`. A network-only restore does not run `apt-get update`; source and full restores do. Backup cleanup considers only format-1 snapshots with a valid SHA-256 manifest, retains the requested number of newest snapshots and asks for confirmation. Non-interactive cleanup requires `--yes`. Legacy or invalid snapshots are not deleted by the cleanup command.

## What It Does NOT Change

The current tool is an APT source/configuration utility. It does not:

- Install, upgrade or remove application packages.
- Change firewall rules, routes, DNS resolver configuration, VPN settings or SSH configuration.
- Manage Python, Node.js, Docker registry, Go, Rust or other non-APT package-manager configuration.

**Filesystem effects outside `/etc/apt`:** the tool creates validated snapshots under `/var/backups/power-apt-boost/` and a mutation lock under `/run/lock/`. It no longer manually deletes APT package lists or clears the archive cache. `apt-get update` still performs its normal package-index maintenance.

## Mirror Testing

Power APT Boost tests each mirror against three endpoints:

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

Power APT Boost includes a dedicated **Iranian mirror pool** for users located in Iran. These mirrors are tested first for geographic optimization — reducing benchmark time for Iranian users.

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
sudo bash power-apt-boost.sh --country ir
```

To use a specific Iranian mirror:

```bash
sudo bash power-apt-boost.sh --mirror https://mirror.arvancloud.ir/ubuntu
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
sudo bash power-apt-boost.sh
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
sudo bash power-apt-boost.sh --restore
```

### Third-party sources warning

If you have third-party APT sources in `/etc/apt/sources.list`, Power APT Boost preserves them and only removes the file if it contains only Ubuntu sources.

## Compatibility

| Ubuntu Version | Current CI coverage |
|---------------|---------------------|
| 24.04 LTS Noble | CLI smoke checks |
| 22.04 LTS Jammy | CLI smoke checks |
| 20.04 LTS Focal | CLI smoke checks |

CI runs ShellCheck, shfmt and an offline regression suite on Ubuntu 20.04, 22.04 and 24.04. Offline tests cover source parsing, inventory, backup/restore, config ownership, proxy validation, architecture-specific archive selection, rollback and mirror compatibility. Live mirror connectivity and external DNS/TLS availability are not CI prerequisites. Requires Bash 4.0+ and one of: curl, wget.

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
git clone https://github.com/power0matin/power-apt-boost.git
cd power-apt-boost
chmod +x power-apt-boost.sh

# Lint
shellcheck -x power-apt-boost.sh
shfmt -d power-apt-boost.sh

# Test
bash tests/run_tests.sh
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
      <img alt="Star History of power0matin/power-apt-boost" src="https://next.ossinsight.io/widgets/official/analyze-repo-stars-history/thumbnail.png?repo_id=1238487780&amp;image_size=auto&amp;color_scheme=light" width="721" height="auto">
    </picture>
  </a>
</p>

<!-- Made with [OSS Insight](https://ossinsight.io/) -->

<p align="center">
  Created by <a href="https://github.com/power0matin">power0matin</a>
</p>
