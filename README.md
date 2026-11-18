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

Power APT Boost tests Ubuntu mirrors, selects a reachable candidate, writes APT sources, applies network settings, and runs `apt-get update`. The current implementation is still undergoing safety hardening; see the [roadmap](ROADMAP.md) before using it on production systems.

> **Version status:** The `main` source currently declares `3.0.0`, while the latest published GitHub release is `v2.1.0`. There is no published `v3.0.0` tag/release yet. The recommended install command below is pinned to `v2.1.0`; use `main` only when you intentionally want unreleased source.

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/power0matin/power-apt-boost/v2.1.0/power-apt-boost.sh | sudo bash
```

Or test first without changes:

```bash
sudo bash power-apt-boost.sh --dry-run
```

## Features

- Auto-detects Ubuntu codename
- Tests 20+ global Ubuntu mirrors
- Selects the fastest working mirror
- Rollback attempt if `apt-get update` fails (full restoration is being hardened; see [ROADMAP](ROADMAP.md))
- Backs up APT configuration before changes
- Writes modern deb822-format APT sources
- Configures APT network optimizations
- Machine-readable JSON output for CI/CD
- Country filtering (current country matching has known limitations; see [ROADMAP](ROADMAP.md))
- IPv6 probe option (the generated APT configuration currently still forces IPv4)
- Persistent logging to file
- Safe `Ctrl+C` interruption
- Shell-based CLI test runner; backup/restore and mirror-selection integration coverage is being expanded

## Installation

### One-liner (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/power0matin/power-apt-boost/v2.1.0/power-apt-boost.sh | sudo bash
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
curl -fsSL https://raw.githubusercontent.com/power0matin/power-apt-boost/v2.1.0/power-apt-boost.sh | less
# Review the script, then:
curl -fsSL https://raw.githubusercontent.com/power0matin/power-apt-boost/v2.1.0/power-apt-boost.sh | sudo bash
```

## Usage

### Auto-select fastest mirror

```bash
sudo bash power-apt-boost.sh
```

### Test without changing anything

```bash
sudo bash power-apt-boost.sh --dry-run
```

### Use a specific mirror

```bash
sudo bash power-apt-boost.sh --mirror https://mirror.example.com/ubuntu
```

### Restore from backup

```bash
sudo bash power-apt-boost.sh --restore
```

### List and test all mirrors

```bash
sudo bash power-apt-boost.sh --list
```

### Machine-readable output (CI/CD)

```bash
sudo bash power-apt-boost.sh --json --quiet
```

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
| `-m`, `--mirror URL` | Use a specific mirror |
| `-r`, `--restore` | Restore APT config from latest backup |
| `--restore-path PATH` | Restore from a specific backup |
| `--dry-run` | Test mirrors without changing config |
| `--skip-update` | Write config but skip `apt-get update` |
| `--list` | List available mirrors and test them |
| `--json` | Output as JSON (sets `--quiet --no-spinner`) |
| `--verbose` | Show detailed output |
| `--quiet` | Suppress non-essential output |
| `--no-spinner` | Disable spinner (for CI/CD) |
| `--timeout SECS` | Probe timeout in seconds (default: 20) |
| `--country CODE` | Filter mirrors by country code |
| `--ipv6` | Use IPv6 for mirror testing |
| `--log-file PATH` | Write log to file |

## What It Does

1. **Detects** Ubuntu version codename
2. **Tests** multiple Ubuntu mirrors for reachability and speed
3. **Selects** the fastest working mirror
4. **Backs up** current APT configuration to `/var/backups/power-apt-boost/`
5. **Writes** modern deb822-format APT sources to `/etc/apt/sources.list.d/ubuntu.sources`
6. **Configures** APT network optimizations (IPv4, retries, timeouts)
7. **Cleans** stale package lists
8. **Runs** `apt-get update`

## What It Changes

| File | Action |
|------|--------|
| `/etc/apt/sources.list.d/ubuntu.sources` | Created/overwritten |
| `/etc/apt/apt.conf.d/99-power-apt-boost` | Created/overwritten |
| `/etc/apt/sources.list` | Removed (if no third-party repos) |
| `/var/lib/apt/lists/*` | Removed before the update step (currently also when `--skip-update` is used) |
| `/var/cache/apt/archives/*` | Cleaned by `apt-get clean` |
| `/var/backups/power-apt-boost/` | Backup directory and snapshots created |

## Backup & Restore

### Automatic backups

Backups are created at:

```
/var/backups/power-apt-boost/YYYY-MM-DD_HH-MM-SS/
```

Each backup contains copies of:
- `ubuntu.sources` (deb822 format)
- `sources.list` (legacy format)
- `sources.list.d/`
- `apt.conf.d/`

### Restore from latest backup

```bash
sudo bash power-apt-boost.sh --restore
```

### Restore from specific backup

```bash
sudo bash power-apt-boost.sh --restore-path /var/backups/power-apt-boost/2025-01-01_12-00-00
```

### Manual restore

Prefer the script's `--restore` / `--restore-path` command and inspect the selected snapshot before restoring it. The current restore implementation does not yet guarantee an exact reconstruction of every pre-existing or newly created file; complete snapshot/restore semantics are a Phase 1 requirement. Do not use a broad manual directory copy as a substitute for a verified restore on a production host.

## What It Does NOT Change

The current tool is an APT source/configuration utility. It does not:

- Install, upgrade or remove application packages.
- Change firewall rules, routes, DNS resolver configuration, VPN settings or SSH configuration.
- Manage Python, Node.js, Docker registry, Go, Rust or other non-APT package-manager configuration.

**Important filesystem effects outside `/etc/apt`:** the current apply path removes APT list data under `/var/lib/apt/lists/`, runs `apt-get clean` (which clears the APT archive cache), and creates snapshots under `/var/backups/power-apt-boost/`. In the current implementation, list cleanup also happens when `--skip-update` is selected. These behaviors are recorded for correction in Phase 1 of the [roadmap](ROADMAP.md).

## Mirror Testing

Power APT Boost tests each mirror against three endpoints:

```
/dists/<codename>/InRelease
/dists/<codename>-updates/InRelease
/dists/<codename>-security/InRelease
```

Only mirrors that return HTTP 200 for all three are considered. The current selector compares the wall-clock duration of the three parallel HTTP probes; this is a basic reachability/response-time proxy, not a sustained bandwidth benchmark or a mirror-freshness check.

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
| 1 | General error (including root/OS/network/apply/restore failures in the current implementation) |
| 2 | Usage error (invalid or unknown arguments) |

The implementation currently uses only exit codes 0, 1 and 2. More specific stable error codes are a planned CLI improvement, not a current guarantee.

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

These are limited container-based CLI checks, not full integration validation of APT source mutation, backup, restore or rollback. Requires Bash 4.0+ and one of: curl, wget.

## Security

- See [SECURITY.md](SECURITY.md) for reporting vulnerabilities
- Review the script before running from a URL
- Use `--dry-run` to preview changes
- A backup is attempted before changes, but complete backup validation and exact rollback are not yet guaranteed; see Phase 1 in [ROADMAP.md](ROADMAP.md)

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
