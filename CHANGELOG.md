# Changelog

All notable changes to Linux Package Source Manager will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Added the Tux penguin PNG brand logo and matching square icon for the repository and README.

### Fixed

- Replaced Unicode terminal separators, borders, spinner and progress glyphs with ASCII-safe output for SSH compatibility.
- Removed the decorative ASCII monogram from the README.

## [3.0.5] — 2026-11-21

### Added

- Added a short `bash <(curl ...)` bootstrap for new servers. It downloads the pinned release, verifies SHA-256, validates Bash syntax, and opens the interactive menu with privilege escalation when needed.

### Changed

- Updated source version and installation documentation to `v3.0.5`.
- GitHub Release names contain only the version identifier.


## [3.0.4] — 2026-11-21

### Changed

- Replaced the oversized Unicode terminal logo with a compact ASCII-only product banner.
- Added a minimal ASCII LPSM monogram to the README while keeping the product name accessible as the page heading.

### Tests

- Added regression checks for terminal banner content, ASCII-only output and the README monogram.
- Updated the CLI version assertion and public installation references for v3.0.4.


## [3.0.3] — 2026-11-21

### Changed

- Renamed the public standalone script and release asset to `linux-package-source-manager.sh` to match the repository and product name.
- Preserved the legacy `APP_SLUG`, environment variables, managed configuration markers, cache paths, lock paths and backup locations so existing installations remain compatible.

### Fixed

- Corrected the source header version so it matches `APP_VERSION`.
- Rebuilt release notes with a literal `printf` format string. Markdown backticks are no longer interpreted as shell command substitutions during release publication.
- Aligned CI and release workflows, checksum filenames, installation URLs and contributor/support documentation with the renamed entry point.

### Tests

- Updated CLI, source and lint checks to use the new filename and verify the version/help output.
- Retained the Ubuntu 20.04, 22.04 and 24.04 offline regression matrix and mandatory ShellCheck/shfmt gates.

## [3.0.2] — 2026-11-21

### Fixed

- Accept the immutable Ubuntu base-suite InRelease metadata when its signed Date is older than seven days and it does not publish a Valid-Until field; moving updates/security suites retain the seven-day freshness gate.
- Preserve mandatory Ubuntu archive signature verification, suite/codename matching, future-date rejection and explicit Valid-Until expiry checks.

### Tests

- Added regression coverage for the original Ubuntu Noble base Release metadata dated 25 April 2024, plus stale dynamic-suite rejection.

## [3.0.1] — 2026-11-21

### Changed

- Rebranded the public project identity as Linux Package Source Manager across the CLI, documentation, GitHub metadata and release workflow.
- Updated repository links, searchable descriptions and installation guidance for the renamed repository.

### Fixed

- Corrected the CLI help installation URL to use raw.githubusercontent.com.
- Required explicit --yes in every documented non-interactive installation command.

### Compatibility

- Preserved the power-apt-boost.sh artifact name, APP_SLUG, legacy configuration markers, environment variables and existing backup/configuration paths.

## [3.0.0] — 2026-11-21

### Added

- Replaced optional `whiptail` dialogs with a consistent number-driven Bash menu rendered in the active SSH terminal; operation results remain visible until Enter is pressed.
- Added per-item progress and elapsed/estimated-remaining-time feedback to mirror benchmark and list operations, plus numbered progress for Python, Node.js and Docker endpoint checks.
- Added read-only Docker Engine APT source inspection and a separate Docker Hub OCI Registry V2 endpoint probe.
- Added safe `daemon.json` registry-mirror merging with `dockerd --validate`, restricted snapshots, SHA-256 conflict checks and explicit rollback.
- Added a separately confirmed Docker systemd restart command; daemon configuration changes never restart Docker automatically.
- Added APT source inventory for legacy and Deb822 sources, with Ubuntu/third-party classification and duplicate URI/suite reporting.
- Added architecture-aware Ubuntu archive selection, including a separate security pocket on amd64/i386 and ports archive selection on other architectures.
- Added explicit APT proxy set/clear options, APT retry configuration and bounded live DNS/TLS diagnostics.
- Added selective restore scopes and verified backup retention cleanup.
- Added interactive-menu controls for APT retries, proxies, network diagnostics and backup cleanup.
- Added Overview, APT management, mirror benchmark, Backup/Restore, Diagnostics and session Settings screens.
- Added read-only `--status` and `--doctor` commands with a versioned JSON report schema.
- Added explicit `--yes` confirmation for non-interactive apply, restore and custom mirror management.
- Added Python tool inventory for python3, pip, pipx, uv, Poetry, the active virtual environment and PEP 668 external-management state.
- Added read-only HTTPS PEP 503/691 index validation with a metadata request and one advertised distribution endpoint check; no package is installed or downloaded in full.
- Added scoped pip index management for user, active-venv and global configuration, with environment override guards and PEP 668 protection for global changes.
- Added uv index configuration for user, system and project TOML scopes, preserving existing index declarations and explicit project source pins.
- Added Poetry project-source configuration with explicit supplemental, primary and explicit priorities; supplemental is the default.
- Added atomic, marker-scoped TOML writes, preview, reset and conflict-checked Python configuration snapshots.
- Added Python terminal-menu actions and CLI commands for status, index testing, set/reset and snapshot restore. pipx is detected but its managed application environments are not modified.
- Added Node.js registry management for npm, pnpm, Yarn Classic and Yarn Berry, including version detection, user config and explicit project opt-in.
- Added HTTPS npm-compatible metadata checks and tarball-host HEAD checks without downloading packages, plus redacted previews and target-specific snapshots.
- Added conflict-checked registry rollback while preserving scoped registries, auth entries, publish settings and lockfiles.
- Redacted registry output to origins only, rejected conflicting Node.js action flags and honored external absolute XDG config directories for pnpm.
- Added a versioned mirror catalog for built-in, Ubuntu-index and user-defined entries, with strict validation and provenance.
- Added the Ubuntu mirror index as a discovery source with a 24-hour cache, root-only storage, schema validation and last-known-good fallback; HTTP index data is treated only as untrusted discovery input, with HTTPS-only redirects enforced for both curl and wget and mandatory signed-metadata verification of every selectable mirror.
- Added signed Ubuntu Release metadata verification for main, updates and security suites, including suite/codename matching, freshness checks and same-host redirect policy.
- Added bounded benchmark concurrency, configurable retry policy, structured endpoint metrics and deterministic scoring.
- Added region filtering, an official-only profile and confirmed custom mirror add/enable/disable/remove actions.
- Made no-argument execution open the menu only on a TTY; non-interactive default execution exits without changing APT configuration.
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

- Serialized Docker daemon reset and restart operations with the Docker configuration lock.
- Kept Docker backup permissions scoped to its dedicated directory instead of changing the shared APT backup parent.
- Made APT snapshots fail closed, checksum-validated and aware of prior path-existence state.
- Added exact restore for new snapshots, including removal of paths that were absent before the change, with staged recovery on restore failure.
- Made deb822 and APT config writes atomic and preserved existing file ownership and mode.
- Added a process-level mutation lock for apply and restore operations.
- Removed manual APT list and archive-cache deletion; `--skip-update` now leaves package indexes untouched.
- Unified probe timeout handling, corrected per-endpoint timing output and aligned `--list` with three-suite health tests.
- Applied IPv6 consistently to mirror probes and generated APT configuration; made `--no-spinner` effective.
- Replaced hostname-pattern country filtering with an explicit country/region mirror catalog.
- Defined stable exit codes and signal-specific interruption codes.
- Spinner properly cleaned up on INT/TERM/HUP signals
- Interrupt handler stops spinner before printing cleanup message
- Exit trap calls `_stop_spinner` to prevent orphaned processes
- BASH_SOURCE handling for older bash versions and curl piped execution
- ShellCheck and shfmt compliance for CI
- Kill 0 removed from cleanup to avoid killing parent process

### Testing

- Added coverage for source inventory, duplicate detection, proxy validation, APT retry configuration, ports-archive selection, unmanaged Deb822 preservation, security-suite separation, network-only restore and verified backup pruning.
- Added Python coverage for HTTPS/index URL validation, credential-safe display, pip environment overrides, PEP 668 global-scope blocking, pip snapshot conflict detection, uv/Poetry private-source preservation, project-pin preservation and marker-only reset.
- Added fail-closed tests for TOML editing when neither tomllib nor an already-installed tomli is available.
- Added offline Node.js adapter tests for URL/package validation, npm/pnpm/Yarn Classic/Berry configuration preservation, snapshot restore conflicts and project-scope boundaries.
- Added coverage for menu selection, TTY safety, explicit approval, cancellation, status/doctor reports and JSON escaping.
- Added offline tests for catalog schemas, cache fallback and refresh, custom mirror persistence, Release freshness, compatibility gates and deterministic benchmark selection.
- Replaced live-network smoke tests with offline regression tests for backup, restore, atomic writes, dry-run and mirror health criteria.
- Wired the full test runner, ShellCheck and shfmt checks into CI.

### Documentation

- Added an Ubuntu-first product and engineering roadmap covering APT, Python, Node.js, Docker/OCI and additional package ecosystems.
- Clarified the source-version and published-release relationship in the public documentation.
- Corrected documentation for current filesystem side effects, exit codes, benchmark scope and backup/restore limitations.
- Pin recommended install commands to the immutable `v3.0.0` release tag.
- Publish a SHA-256 checksum beside the standalone Bash release artifact and document checksum verification.

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

[Unreleased]: https://github.com/power0matin/linux-package-source-manager/compare/v3.0.5...HEAD
[3.0.5]: https://github.com/power0matin/linux-package-source-manager/compare/v3.0.4...v3.0.5
[3.0.4]: https://github.com/power0matin/linux-package-source-manager/compare/v3.0.3...v3.0.4
[3.0.3]: https://github.com/power0matin/linux-package-source-manager/compare/v3.0.2...v3.0.3
[3.0.2]: https://github.com/power0matin/linux-package-source-manager/compare/v3.0.1...v3.0.2
[3.0.1]: https://github.com/power0matin/linux-package-source-manager/compare/v3.0.0...v3.0.1
[3.0.0]: https://github.com/power0matin/linux-package-source-manager/compare/v2.1.0...v3.0.0
[2.1.0]: https://github.com/power0matin/linux-package-source-manager/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/power0matin/linux-package-source-manager/compare/v1.2.0...v2.0.0
[1.2.0]: https://github.com/power0matin/linux-package-source-manager/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/power0matin/linux-package-source-manager/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/power0matin/linux-package-source-manager/releases/tag/v1.0.0
