# Changelog

All notable changes to Power APT Boost will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Added APT source inventory for legacy and Deb822 sources, with Ubuntu/third-party classification and duplicate URI/suite reporting.
- Added architecture-aware Ubuntu archive selection, including a separate security pocket on amd64/i386 and ports archive selection on other architectures.
- Added explicit APT proxy set/clear options, APT retry configuration and bounded live DNS/TLS diagnostics.
- Added selective restore scopes and verified backup retention cleanup.
- Added interactive-menu controls for APT retries, proxies, network diagnostics and backup cleanup.
- Added an interactive terminal menu with numbered Bash navigation and optional `whiptail` dialogs.
- Added Overview, APT management, mirror benchmark, Backup/Restore, Diagnostics and session Settings screens.
- Added read-only `--status` and `--doctor` commands with a versioned JSON report schema.
- Added explicit `--yes` confirmation for non-interactive apply, restore and custom mirror management.
- Added a versioned mirror catalog for built-in, Ubuntu-index and user-defined entries, with strict validation and provenance.
- Added the Ubuntu mirror index as a discovery source with a 24-hour cache, root-only storage, schema validation and last-known-good fallback; HTTP index data is treated only as untrusted discovery input, with HTTPS-only redirects enforced for both curl and wget and mandatory signed-metadata verification of every selectable mirror.
- Added signed Ubuntu Release metadata verification for main, updates and security suites, including suite/codename matching, freshness checks and same-host redirect policy.
- Added bounded benchmark concurrency, configurable retry policy, structured endpoint metrics and deterministic scoring.
- Added region filtering, an official-only profile and confirmed custom mirror add/enable/disable/remove actions.
- Made no-argument execution open the menu only on a TTY; non-interactive default execution exits without changing APT configuration.

### Testing

- Added coverage for source inventory, duplicate detection, proxy validation, APT retry configuration, ports-archive selection, unmanaged Deb822 preservation, security-suite separation, network-only restore and verified backup pruning.
- Added coverage for menu selection, TTY safety, explicit approval, cancellation, status/doctor reports and JSON escaping.
- Added offline tests for catalog schemas, cache fallback and refresh, custom mirror persistence, Release freshness, compatibility gates and deterministic benchmark selection.

### Fixed

- Made APT snapshots fail closed, checksum-validated and aware of prior path-existence state.
- Added exact restore for new snapshots, including removal of paths that were absent before the change, with staged recovery on restore failure.
- Made deb822 and APT config writes atomic and preserved existing file ownership and mode.
- Added a process-level mutation lock for apply and restore operations.
- Removed manual APT list and archive-cache deletion; `--skip-update` now leaves package indexes untouched.
- Unified probe timeout handling, corrected per-endpoint timing output and aligned `--list` with three-suite health tests.
- Applied IPv6 consistently to mirror probes and generated APT configuration; made `--no-spinner` effective.
- Replaced hostname-pattern country filtering with an explicit country/region mirror catalog.
- Defined stable exit codes and signal-specific interruption codes.

### Testing

- Replaced live-network smoke tests with offline regression tests for backup, restore, atomic writes, dry-run and mirror health criteria.
- Wired the full test runner, ShellCheck and shfmt checks into CI.

### Documentation

- Added an Ubuntu-first product and engineering roadmap covering APT, Python, Node.js, Docker/OCI and additional package ecosystems.
- Clarified the difference between the `3.0.0` source version on `main` and the latest published `v2.1.0` release.
- Corrected documentation for current filesystem side effects, exit codes, benchmark scope and backup/restore limitations.

## [3.0.0] — 2026-07-19

### Added

- Animated braille spinner during mirror testing
- Progress bar support for long-running operations
- Section headers with Unicode box-drawing characters for visual hierarchy
- Step indicators (`[1/3] Creating backup`) during apply phase
- `✓` / `✗` visual status indicators for mirror component results
- Box-drawing tree layout (`┌─ │ └─`) for per-mirror probe output
- Arrow indicators (`▸`) for selected mirror and response time in summary
- `COLOR_MAGENTA`, `COLOR_WHITE`, `COLOR_UL` for richer terminal output
- Parallel mirror testing (up to 8 workers) for 6-8x faster benchmarks

### Changed

- ASCII art banner replaces plain text header
- Mirror results now show PASS/FAIL with total probe time per mirror
- Benchmark summary uses aligned key-value pairs with colored values
- Error messages now include actionable "Fix:" suggestions and examples
- Help output reorganized with compact exit codes table and section headers
- `--list` output uses checkmarks/crosses and dimmed column headers
- Backup warning now notes "non-standard setup" hint
- Restore error provides manual inspection command
- JSON output includes `files` object with deb822 and config paths
- Third-party source warning provides more context
- Argument validation errors show example usage
- Unknown/unexpected argument errors display help command hint
- apt-get update failure message explains the system was restored
- "No working mirror" error lists causes and suggests `--mirror` flag

### Fixed

- Spinner properly cleaned up on INT/TERM/HUP signals
- Interrupt handler stops spinner before printing cleanup message
- Exit trap calls `_stop_spinner` to prevent orphaned processes
- BASH_SOURCE handling for older bash versions and curl piped execution
- ShellCheck and shfmt compliance for CI
- Kill 0 removed from cleanup to avoid killing parent process

## [2.1.0] — 2025-07-12

### Added

- 17 Iranian Ubuntu mirrors to the default mirror pool for users in Iran

## [2.0.0] — 2025-07-10

### Added

- `--restore` / `--restore-path` for automatic backup restoration
- `--list` to test and display all available mirrors
- `--json` for machine-readable output (CI/CD friendly)
- `--verbose` / `--quiet` modes for output control
- `--timeout` to configure probe timeout
- `--country` to filter mirrors by country code
- `--ipv6` for IPv6 mirror testing
- `--log-file` for persistent logging
- Automatic rollback on `apt-get update` failure
- Global mirror list (not Iran-specific)
- Proper deb822 format with `Signed-By` keyring validation
- Third-party source detection (won't delete `sources.list` with third-party repos)
- Colored terminal output with auto-detection
- Structured exit codes (0-8)
- Backup directory in `/var/backups/power-apt-boost/`
- Comprehensive ShellCheck-clean codebase
- GitHub Actions CI (ShellCheck, shfmt, Ubuntu matrix)
- GitHub Actions release workflow
- Issue and PR templates
- CONTRIBUTING.md, SECURITY.md, SUPPORT.md, CODE_OF_CONDUCT.md, ROADMAP.md
- .editorconfig, .shellcheckrc, .markdownlint.json
- Integration test suite

### Changed

- `APT::Install-Recommends` is no longer set by default (was opt-out, now not set)
- Mirror list is now global (removed regional bias)
- Backups stored in `/var/backups/power-apt-boost/` instead of `/root/`
- Spinner no longer inherits EXIT trap in subshells
- All functions use local variables (no more global return values)
- `--no-spinner` is the default in `--json` and `--quiet` modes

### Fixed

- EXIT trap firing in spinner subshell, killing parent process
- `rm -f /etc/apt/sources.list` no longer unconditional (checks for third-party repos)
- Missing keyring file now produces a warning instead of silent failure
- `mktemp` usage now uses `$TMPDIR` with proper fallback
- Floating-point comparison no longer spawns unnecessary subprocesses

### Removed

- `--keep-recommends` flag (use `--keep-recommends` equivalent in apt config directly)
- Unnecessary coreutils dependency checks (awk, date, mkdir, etc.)
- Iran-specific mirror bias from default mirror list

## [1.2.0] — Safe Interrupts and Stable Spinner

- Fixed `Ctrl+C` handling during mirror tests
- Fixed spinner cleanup when the script is interrupted
- Removed fragile command substitution around full mirror test functions
- Added safer child process tracking for mirror probes
- Added cancellable `apt-get update` execution
- Added cleanup for running spinner and child processes on `INT` and `TERM`
- Improved reliability when running via `curl | sudo bash`

## [1.1.0] — Loading Spinner and Better Mirror Test Output

- Added loading spinner while testing mirror endpoints
- Added `--no-spinner` option for CI/CD and log-only environments
- Moved mirror test logs to `stderr` to keep internal output parsing clean
- Improved mirror test visibility for users
- Added clearer OK/FAIL status output for repository checks

## [1.0.0] — Initial Release

- Added automatic Ubuntu codename detection
- Added mirror speed testing
- Added fastest mirror selection
- Added APT source backup
- Added APT network optimization
- Added cache cleanup
- Added branded banner

[Unreleased]: https://github.com/power0matin/power-apt-boost/compare/v3.0.0...HEAD
[3.0.0]: https://github.com/power0matin/power-apt-boost/compare/v2.1.0...v3.0.0
[2.1.0]: https://github.com/power0matin/power-apt-boost/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/power0matin/power-apt-boost/compare/v1.2.0...v2.0.0
[1.2.0]: https://github.com/power0matin/power-apt-boost/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/power0matin/power-apt-boost/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/power0matin/power-apt-boost/releases/tag/v1.0.0
