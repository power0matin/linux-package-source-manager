# Power APT Boost — Product & Engineering Roadmap

> **Roadmap version:** 1.0  
> **Prepared:** 2026-11-19  
> **Project:** [power0matin/power-apt-boost](https://github.com/power0matin/power-apt-boost)  
> **Current implementation baseline:** `main` at `56eaf13e76e276bbaae160e59a0aca506490f02d`  
> **Current script version string:** `3.0.0`

This document is the implementation plan for evolving Power APT Boost into an **Ubuntu-first package-source and mirror manager for servers and developer environments**. It expands the existing Ubuntu APT mirror selector to cover the package ecosystems commonly used on Ubuntu servers, including Python, Node.js, Docker/OCI, Go, Rust, PHP, Java and selected additional ecosystems.

This is a product roadmap, not a claim that the listed features already exist. Every unchecked item is planned work. Implementation is deliberately divided into reviewable phases; phases are to be completed and accepted in order unless a dependency is explicitly documented.

### Phase delivery and merge gates

Work is executed strictly in phase order. Each phase must use its own focused branch and pull request. A phase is complete only when its acceptance criteria and applicable tests pass, the PR is reviewed and merged, and the resulting `main` head is re-checked. Do not start implementation work for the next phase while the previous phase PR is open or awaiting changes. A PR must not include unrelated refactors or work from a later phase. If a phase reveals a prerequisite defect, record it and either include the minimal fix within that phase's scope or stop and revise the plan before proceeding.


---

## 1. Product vision

Power APT Boost should help an Ubuntu user answer four questions safely:

1. **What package sources and mirrors does this machine currently use?**
2. **Which compatible and trustworthy alternatives are reachable and healthy from this machine?**
3. **What exact configuration would change if an alternative were selected?**
4. **Can the change be verified and completely reversed?**

The product should become a practical control center for package-source performance and reliability on Ubuntu, while remaining lightweight, scriptable and safe for production VPS environments.

### Product principles

- **Ubuntu first.** Complete and stabilize Ubuntu support before adding other distributions.
- **Safe by default.** Inspection and benchmarking do not change the machine. Changes require a preview and explicit confirmation, except when the caller intentionally selects a non-interactive `--yes` mode.
- **One engine, multiple interfaces.** The interactive menu and CLI must call the same implementation and produce the same results.
- **Ecosystem-aware.** APT, PyPI, npm, Docker Registry, Go modules and other sources are different protocols with different trust and configuration models. Do not treat them as interchangeable URL lists.
- **Preserve existing configuration.** Never overwrite third-party APT sources, private registries, credentials, scopes, project settings or unrelated daemon options.
- **Rollback is a feature, not a best-effort message.** A successful backup and a verifiable restore path are prerequisites for any mutating operation.
- **No silent security downgrade.** Never disable TLS checks, package signatures, checksum databases or repository authentication to make a mirror appear usable.
- **No geographic assumptions.** Do not assume the user's country from an IP address. Offer automatic suggestions only when the user enables that behavior; always allow manual region selection.
- **Portable delivery.** Preserve the simple single-file installation experience. Development source may be modular, but releases should provide a tested, self-contained executable script.
- **No unnecessary services.** Do not install a daemon, scheduled job, package manager, proxy or registry cache by default.

### Out of scope for the initial Ubuntu roadmap

- Replacing or disabling Ubuntu security repositories without explicit user action.
- Installing, upgrading or removing application packages as part of mirror optimization.
- Modifying project dependency files automatically (`pyproject.toml`, `package-lock.json`, `pnpm-lock.yaml`, `Cargo.toml`, `composer.json`, Gradle/Maven files, etc.). Project-level edits must be opt-in and reviewable.
- Changing firewall, routing, DNS, VPN, proxy daemon, SSH or system network settings.
- Starting a local Docker Registry, PyPI proxy or npm cache automatically.
- Supporting Debian, Linux Mint, Pop!_OS or non-APT distributions before the Ubuntu implementation is stable.
- Claiming that a mirror is trustworthy solely because it responds quickly or uses HTTPS.

---

## 2. Current repository baseline

The following reflects the repository inspection performed for this roadmap. It is a static review of the default branch; it is not a substitute for executing the script on real Ubuntu installations.

### Existing implementation

- A single Bash entry point: `power-apt-boost.sh`.
- Ubuntu-only OS detection through `/etc/os-release`.
- A hard-coded list of roughly 29 Ubuntu mirror URLs, including an Iran group and international groups.
- Parallel mirror probing with up to eight workers.
- Probes for `InRelease` under the base, updates and security suites.
- Selection of the passing mirror with the lowest measured probe-batch time.
- deb822 source generation at `/etc/apt/sources.list.d/ubuntu.sources`.
- APT network configuration written to `/etc/apt/apt.conf.d/99-power-apt-boost`.
- Backup and restore commands, rollback after a failed `apt-get update`, dry-run, custom mirror, list, JSON, quiet/verbose, timeout, country, IPv6 and log-file options.
- A small shell test runner, ShellCheck/shfmt CI workflow and tag-triggered release workflow.

### Known inconsistencies and risks to resolve first

These are audit findings to turn into tests and fixes, not assumptions that every runtime path will fail:

1. The script declares `APP_VERSION="3.0.0"`, while the README badge and published Git tag/release metadata inspected during the audit still identify `v2.1.0` as the latest release.
2. The existing `ROADMAP.md` lists capabilities that are already present in the script, including parallel testing, while other planned features remain unimplemented.
3. `tests/run_tests.sh` contains stale version and exit-code expectations and does not adequately test backup, restore, rollback or mirror-selection behavior.
4. The inspected CI workflow performs linting and a limited set of direct CLI checks but does not run the repository's full test runner.
5. `_get_mirrors` filters only hostnames matching a country-code pattern. This does not correctly represent country membership for providers such as Iranian mirror hosts whose domain does not start with `ir.`; unknown country values also need explicit handling.
6. `--timeout` is not consistently applied to the curl probe path; probe timeout constants and the CLI timeout value need one documented source of truth.
7. `--ipv6` affects mirror probing, while the generated APT configuration still forces IPv4. The selected network policy and the applied APT policy can therefore disagree.
8. `--no-spinner` is parsed but the spinner lifecycle is not consistently controlled by that option.
9. `--list` does not use the same complete health criteria as the selection flow.
10. Probe output parsing and timing fields need correction so that HTTP status, failure reason, response time and total elapsed time are distinct values.
11. The `--skip-update` path currently needs review because APT list cleanup occurs before the update-skipped return path. Skipping an update must not unnecessarily destroy the currently available package lists.
12. Backup creation currently tolerates copy failures in places where a failed backup must abort a mutating operation. Restore must also remove files that did not exist in the captured pre-change state.
13. Source/config writes need atomic replacement, permission preservation and recovery from interruption.
14. The current tests do not establish that dry-run is completely side-effect-free or that rollback reconstructs the exact prior configuration.
15. Documentation claims about atomic writes, supported versions, mirror counts and files changed need to be reconciled with the implementation.

### Baseline policy

- Treat current `main` as the source baseline until a fresh read says otherwise.
- Do not rewrite the current implementation wholesale merely to make the architecture look cleaner.
- Fix demonstrated correctness and safety defects with minimal, test-backed changes.
- Do not change the existing public CLI incompatibly without a deprecation path.

---

## 3. Target user experience

### 3.1 Interactive menu

When launched without arguments from a real interactive terminal, the tool should open a numbered menu. When launched non-interactively, it should print help or require an explicit CLI action; it must never block waiting for input in a pipeline or automation job.

Proposed main menu:

```text
Power APT Boost
Ubuntu Package Sources & Mirror Manager

  1. Overview and current status
  2. Optimize Ubuntu APT mirrors
  3. Python package indexes
  4. Node.js package registries
  5. Docker and OCI registries
  6. Go module proxy
  7. Rust crate registries
  8. PHP Composer repositories
  9. Java Maven / Gradle repositories
 10. Other package ecosystems
 11. Benchmark and compare mirrors
 12. Custom mirrors and source profiles
 13. Backup and restore
 14. Diagnostics and logs
 15. Preferences
  0. Exit
```

Menu requirements:

- Show the detected OS release, architecture, active user, root requirement and current source status.
- Use a simple Bash numbered menu as the guaranteed fallback; optionally use `whiptail` when available. `whiptail` must not become a mandatory dependency.
- Every submenu must include Back and Cancel.
- Clearly distinguish **Inspect**, **Test**, **Preview**, **Apply**, **Restore** and **Reset** actions.
- Before a change, show the exact files, environment variables, service actions and scope that will be affected.
- Do not silently elevate a user-scoped action to root.
- If the environment is not interactive, do not start the menu.
- Keep stdout machine-readable in JSON mode; diagnostics and progress belong on stderr or in a log.

### 3.2 Overview / status screen

The status screen should report, without changing anything:

- Ubuntu version, codename, architecture and support status.
- APT source files and enabled Ubuntu suites.
- Current Ubuntu archive and security source URLs.
- Python interpreters found, active virtual environment, pip/uv/Poetry/pipx availability and configured index URLs (credentials masked).
- Node.js/npm/pnpm/Yarn availability and registry/scoped registry values (credentials masked).
- Docker/Podman/containerd availability and registry-mirror state where readable.
- Go, Cargo, Composer, Maven and Gradle availability and effective proxy/repository settings.
- Whether a Power APT Boost configuration or backup already exists.
- Any conflicting settings, unsupported config formats or permissions that prevent safe management.

Status output must not claim that a repository is healthy until the corresponding health probe has run.

### 3.3 Common interaction model

Every ecosystem adapter should offer the same conceptual actions:

1. Detect existing configuration.
2. List known, official, regional and user-defined sources.
3. Test compatible sources from the current machine.
4. Compare measured results and trust/compatibility indicators.
5. Preview the selected configuration change.
6. Back up the exact files/environment state that will change.
7. Apply only the requested scope.
8. Verify using the package manager's own non-installing or metadata-only command where possible.
9. Roll back if verification fails.
10. Show the final state and a restore command.

The UI may differ per package manager, but the safety model must be shared.

---

## 4. Ecosystem coverage and priorities

The following table defines intended scope. "Planned" does not mean implemented.

| Ecosystem | Tools / clients | Source type | Planned priority | Default configuration scope |
|---|---|---|---|---|
| Ubuntu APT | apt, apt-get, apt-cache | Ubuntu archive and security mirrors | P0 — complete first | System, root only |
| Python | pip, venv, pipx | PyPI-compatible Simple API / wheel hosts | P1 | User; optional virtualenv; system only by explicit choice |
| Python modern tooling | uv | PyPI-compatible indexes and named indexes | P1 | User/global; project opt-in |
| Python project tooling | Poetry | Primary/supplemental/explicit project sources | P1 | Project opt-in; user config for credentials only |
| Node.js | npm, pnpm, Yarn Classic/Berry | npm-compatible registries | P2 | User; project opt-in |
| Containers | Docker Engine APT repo, Docker Hub mirror, OCI registries | APT repository / Registry HTTP API | P2 | System; daemon restart requires separate confirmation |
| Go | go command | GOPROXY module protocol | P3 | User environment; private module policy preserved |
| Rust | Cargo | crates.io registry / source replacement | P3 | User; project opt-in |
| PHP | Composer | Packagist / Composer repository | P3 | User or project opt-in |
| Java | Maven, Gradle | Maven repositories and mirrors | P3 | User; project opt-in |
| Ruby | RubyGems, Bundler | RubyGems source | P4 | User; project opt-in |
| Conda | Conda, Mamba, micromamba | Channels | P4 | User; environment/project opt-in |
| Binary/toolchain downloads | selected installers and release hosts | HTTPS download endpoints | P4 | Per-command only; no global URL rewriting |

### Support tiers

- **Tier 1 — Native and tested:** APT, pip, uv, Poetry, npm/pnpm/Yarn, Docker.
- **Tier 2 — Supported adapters:** Go, Cargo, Composer, Maven/Gradle.
- **Tier 3 — Experimental adapters:** RubyGems/Bundler, Conda and selected binary download providers.

Do not advertise an ecosystem as supported until its adapter has configuration parsing, safe backup, verification, rollback and automated tests.

---

## 5. Mirror and package-source catalog

### 5.1 Catalog model

Replace the assumption that every source is a URL in one Bash array with a structured catalog. The release script may embed the catalog, but development and validation should use a structured source file that can be linted and tested.

Each catalog entry should be able to define:

- Stable ID and display name.
- Ecosystem and compatible client/tool versions.
- Provider/operator and canonical upstream.
- Country, region and optional network/provider tags.
- Endpoint URL(s), including metadata and artifact hosts when separate.
- Supported protocol/API version.
- Supported Ubuntu releases, architectures, suites, channels or distributions where relevant.
- Expected health-check paths and response requirements.
- Whether it is official, community-operated, private or user-supplied.
- TLS requirements and expected redirect behavior.
- Freshness/checksum/signature validation method.
- Last catalog verification date and source URL.
- Enable/disable state and optional notes.

A mirror record must not imply that a provider is official merely because it is geographically local or appears in a community list.

### 5.2 Discovery and refresh

- Use the official Ubuntu mirror index as a discovery source for Ubuntu archive mirrors.
- Retain a curated, reviewable list of providers that are useful for common regions and Iranian VPS connectivity.
- Allow user-supplied mirrors even when they are not in the built-in catalog.
- Refresh catalog data separately from applying it to the machine.
- Validate downloaded catalog data before use; do not `source` or execute remote catalog content.
- Cache the last known-good catalog and fall back to it when discovery is unavailable.
- Do not make a live catalog request mandatory for basic operation.
- Keep security archive and release/ports archive semantics separate where the upstream distribution requires it.

### 5.3 Health checks and scoring

Do not rank mirrors by a single HTTP request. A candidate scoring model should include:

- Reachability and protocol compatibility.
- DNS, connection and TLS setup time.
- Median response time across multiple samples; optionally p95 for diagnostics.
- A small, bounded download test when a safe, stable artifact is available.
- Freshness or synchronization age where the ecosystem exposes trustworthy metadata.
- Success ratio across required endpoints.
- Redirect count and final host.
- Architecture, suite, channel and package metadata availability.
- Operator/trust classification.

Initial score can be a documented weighted score, but hard compatibility failures must disqualify a mirror rather than merely reduce its score. Do not make a high download speed compensate for stale packages, invalid metadata, broken signatures or missing security suites.

Benchmark rules:

- Use a bounded number of workers and configurable concurrency.
- Use timeouts per connection and per complete request.
- Avoid downloading large artifacts just to measure speed.
- Do not use a HEAD request as the only health check; some mirrors do not implement it consistently.
- Record UTC timestamp, source URL, test method and tool version.
- Avoid aggressive repeated probing and respect provider limits.
- Clearly distinguish local latency from global mirror quality.

### 5.4 Security and package integrity

- HTTPS is required for the default curated third-party endpoints unless a documented ecosystem protocol explicitly requires otherwise.
- Never disable TLS certificate verification as an automatic fallback.
- For APT, retain signed repository metadata verification and the correct `Signed-By` keyring.
- For Python, preserve wheel hashes and project lockfile hashes; do not bypass hash checking.
- For Go, preserve `GOSUMDB` behavior unless the user explicitly configures a trusted private policy.
- For Rust, use Cargo source replacement only for an equivalent mirror of the original source; do not use it to silently substitute packages.
- Never put credentials in catalog URLs, logs, JSON output or terminal summaries.
- Treat a registry mirror and a package publisher as different trust boundaries.

---

## 6. Ubuntu APT — complete target scope (P0)

APT is the foundation and must be fully reliable before broader ecosystem work begins.

### 6.1 Detection and inventory

- [ ] Detect Ubuntu release, codename, architecture and supported lifecycle status.
- [ ] Detect both deb822 `.sources` and legacy `sources.list` entries.
- [ ] Inventory every file under `/etc/apt/sources.list.d/` without assuming every file belongs to Ubuntu.
- [ ] Identify Ubuntu archive, updates, backports, security, ports and third-party repositories separately.
- [ ] Read current APT proxy, retries, timeouts, ForceIPv4/ForceIPv6 and related Acquire settings.
- [ ] Detect missing or unreadable keyrings and invalid `Signed-By` paths.
- [ ] Detect duplicate or conflicting Ubuntu source definitions.
- [ ] Report disabled (`Enabled: no`) deb822 stanzas without rewriting them.
- [ ] Support architectures such as amd64 and arm64 using the host's actual APT architecture.

### 6.2 Ubuntu mirror discovery and selection

- [ ] Use the official Ubuntu mirror index as one discovery input.
- [ ] Maintain validated regional entries, including Iranian mirror providers, with provider metadata rather than hostname heuristics.
- [ ] Allow country and region selection without IP geolocation.
- [ ] Offer `Auto`, `Iran`, `Europe`, `Asia`, `North America`, `Global` and `Custom` profiles where catalog data supports them.
- [ ] Keep a reliable global fallback.
- [ ] Verify required suites for the detected codename: base release, updates, security and backports when enabled/required.
- [ ] Distinguish `archive.ubuntu.com`, `security.ubuntu.com`, `ports.ubuntu.com` and architecture-specific endpoints.
- [ ] Never route security updates to an endpoint that has not passed the security-suite check.
- [ ] Compare all required endpoints, not only `<codename>/InRelease`.
- [ ] Handle redirects and report the final hostname.
- [ ] Handle 404, 403, 429, 5xx, DNS, TCP, TLS and timeout outcomes separately.
- [ ] Provide an option to prefer official sources over community mirrors.
- [ ] Support per-suite source selection only when all required suite relationships and signing rules remain valid.

### 6.3 APT configuration and safe apply

- [ ] Generate valid deb822 files for supported Ubuntu releases.
- [ ] Preserve third-party source files and unrelated stanzas.
- [ ] Never delete a file simply because its name is `ubuntu.sources` or `sources.list` without parsing its content and recording its exact prior state.
- [ ] Preserve comments and unrelated options where practical; where full preservation is not possible, show a precise diff before applying.
- [ ] Write temporary files in the destination filesystem, validate syntax, set safe permissions and replace atomically.
- [ ] Validate keyring presence and permissions before writing `Signed-By`.
- [ ] Keep Ubuntu security suites enabled unless the user explicitly requests otherwise.
- [ ] Avoid setting `APT::Install-Recommends` or changing installation semantics as an incidental optimization.
- [ ] Make IPv4/IPv6 policy explicit and consistent between probing and APT config.
- [ ] Keep timeout and retry options configurable, bounded and documented.
- [ ] Support APT HTTP/HTTPS proxy settings without exposing credentials.
- [ ] Do not delete `/var/lib/apt/lists` before a successful apply/update path.
- [ ] Do not run `apt-get clean` or remove package caches unless separately requested.
- [ ] Separate mirror selection from cache cleanup and package installation.
- [ ] Show planned file changes and expected effects before mutation.

### 6.4 APT backup, restore and rollback

- [ ] Capture all relevant APT source and configuration files that the operation may change.
- [ ] Record files that did not exist before the operation so rollback can remove newly created files.
- [ ] Preserve ownership, permissions, symlinks and file metadata where relevant.
- [ ] Store a manifest with timestamp, tool version, OS version, operation, checksums and original file state.
- [ ] Use restrictive backup directory permissions and root ownership.
- [ ] Abort before mutation if any required backup step fails.
- [ ] Validate backup integrity before restore.
- [ ] Support full restore and carefully scoped file restore.
- [ ] Restore atomically and verify the restored state.
- [ ] On failed `apt-get update`, restore every touched file and verify the rollback rather than merely copying selected files.
- [ ] Avoid recursively overwriting unrelated files created after the backup.
- [ ] Keep a lock to prevent two Power APT Boost instances from modifying APT simultaneously.
- [ ] Make interrupt behavior deterministic during backup, write, update and rollback.

### 6.5 APT diagnostics

- [ ] `--doctor` reports common APT failure classes and safe remediation suggestions.
- [ ] Detect stale/invalid Release metadata, missing Release files, signature failures and expired metadata.
- [ ] Detect DNS, proxy, TLS certificate, clock-skew and connectivity failures.
- [ ] Detect duplicate sources and suites that do not match the OS codename.
- [ ] Detect missing components and architecture mismatch.
- [ ] Offer a non-mutating diagnostics bundle with credentials and private host details redacted by default.
- [ ] Never auto-run `apt upgrade`, `apt full-upgrade`, `do-release-upgrade` or package removals.

### 6.6 APT CLI target

Preserve all existing supported options and add a consistent command model over time:

```text
power-apt-boost --status
power-apt-boost --doctor
power-apt-boost --list --ecosystem apt
power-apt-boost --test-mirrors --ecosystem apt
power-apt-boost --country ir --dry-run
power-apt-boost --mirror https://mirror.example/ubuntu --dry-run
power-apt-boost --backup
power-apt-boost --restore
power-apt-boost --restore-path /var/backups/power-apt-boost/<snapshot>
```

Exact flag names must be finalized in Phase 2. Avoid adding multiple aliases with conflicting meanings.

---

## 7. Python package sources — complete target scope (P1)

Python support is a major feature, not a single global `pip` URL. Different tools have different configuration semantics and should be detected and managed separately.

### 7.1 Clients to detect

- [ ] `python3` and installed Python interpreters.
- [ ] `python -m pip` / `python3 -m pip` and pip version.
- [ ] Active `venv` / `virtualenv` and the owning interpreter.
- [ ] `pipx` and its configured interpreter.
- [ ] `uv`, including installed version and user/system/project config.
- [ ] Poetry, including version and source definitions.
- [ ] Optional later adapters: PDM, Hatch and Conda/micromamba.
- [ ] Detect PEP 668 externally-managed Python environments and avoid modifying/installing into the OS-managed Python environment.

### 7.2 PyPI mirror catalog

- [ ] Support the canonical PyPI simple API endpoint.
- [ ] Include regionally useful and maintained community mirrors only after checking their current operator, HTTPS, PEP 503/PEP 691 compatibility and availability.
- [ ] Model metadata/index host and distribution-file host separately; a working `/simple/` page does not guarantee wheel downloads will work.
- [ ] Validate representative package metadata and a small artifact download without installing the package.
- [ ] Check that the mirror serves expected file hashes/metadata where available.
- [ ] Measure package metadata latency separately from wheel download speed.
- [ ] Support custom/private indexes with explicit trust labeling.
- [ ] Do not assume a regional mirror is synchronized or suitable for every package, platform or Python version.

### 7.3 pip and virtual environments

- [ ] Inspect effective settings using `pip config debug` and `pip config list` with credential redaction.
- [ ] Support configuration scopes: current virtual environment, user and system/global.
- [ ] Default to user scope when no virtual environment is active; prefer current-venv scope when one is active and the user chooses it.
- [ ] Expose the effective index through a safe `pip config` operation or a scoped config file change.
- [ ] Support reset to the prior value and reset to the canonical PyPI default.
- [ ] Preserve trusted-host and certificate settings; never add `trusted-host` automatically to work around TLS errors.
- [ ] Respect environment-variable overrides such as `PIP_INDEX_URL`, `PIP_EXTRA_INDEX_URL` and `PIP_CONFIG_FILE`.
- [ ] Explain when environment variables override the saved config.
- [ ] Do not overwrite user-specified `find-links`, constraints, `no-index`, certificate, proxy or authentication settings.
- [ ] Do not write the user's token or password into the generated config.
- [ ] Provide a test mode that resolves metadata for a harmless known package without installing it.
- [ ] Preserve `--require-hashes` and lockfile-based reproducibility.

**Security rule:** do not use `extra-index-url` as an automatic "fallback mirror" strategy. pip searches the configured locations and this can create dependency-confusion risk for private package names. Prefer a single trusted compatible index for public packages, or an explicitly managed repository/proxy with a documented private-package policy.

### 7.4 uv

- [ ] Detect user config (`uv.toml`), environment variables and project `pyproject.toml` configuration.
- [ ] Support default index selection and named indexes.
- [ ] Preserve index priority semantics and package-to-index pins.
- [ ] Do not add a public mirror as an unrestricted extra index when the project already relies on an explicit private index.
- [ ] Support user-level settings without modifying project files by default.
- [ ] For project-level changes, show and apply a reviewable `pyproject.toml` diff only after explicit selection.
- [ ] Verify with `uv lock --dry-run` or an appropriate metadata-only resolution path when supported by the installed uv version; do not modify the lockfile during a mirror test.

### 7.5 Poetry

- [ ] Detect Poetry version and existing package sources.
- [ ] Respect primary, supplemental and explicit source priority.
- [ ] Explain that package sources are generally project-specific and are not equivalent to user-specific publishing repository configuration.
- [ ] Do not confuse a publishing repository with an installation source.
- [ ] Never silently make a regional mirror primary if the project has explicit package source constraints.
- [ ] Preserve PyPI behavior and source pins.
- [ ] For project-level source edits, show the exact `pyproject.toml` diff and require confirmation.
- [ ] Keep repository credentials in Poetry's credential mechanism or environment variables; do not store them in the source catalog.

### 7.6 Python-specific acceptance tests

- [ ] pip user-scope change does not modify system or venv configs.
- [ ] venv-scope change does not leak into another venv.
- [ ] system-scope requires root and explicit confirmation.
- [ ] existing `PIP_INDEX_URL` overrides are detected and never silently deleted.
- [ ] `extra-index-url` is not introduced automatically.
- [ ] uv index ordering and explicit package pins remain unchanged.
- [ ] Poetry source priorities and project source pins remain unchanged unless the user explicitly edits them.
- [ ] Private URLs and credentials are masked in terminal, logs and JSON.
- [ ] A failed verification restores the original config byte-for-byte where feasible.
- [ ] No package is installed, upgraded or removed during discovery and benchmarking.

---

## 8. Node.js package registries (P2)

### Clients

- [ ] npm.
- [ ] pnpm.
- [ ] Yarn Classic and Yarn Berry (modern Yarn).
- [ ] Detect Node.js version, package-manager version, Corepack and active project directory.

### Scope

- [ ] Detect default npm registry and scoped registries (`@scope:registry`).
- [ ] Detect user, project and global `.npmrc` values and relevant environment overrides.
- [ ] Detect Yarn Berry `npmRegistryServer`, `npmScopes` and registry authentication configuration.
- [ ] Preserve pnpm's npm-compatible registry/auth settings and pnpm-specific configuration.
- [ ] Detect project lockfiles without changing them.
- [ ] Support tested npm-compatible registry mirrors and private registries.
- [ ] Distinguish registry metadata host from tarball download hosts.
- [ ] Preserve scope-specific private registries and `publishConfig.registry`.
- [ ] Do not overwrite auth tokens or rewrite project `.npmrc` by default.
- [ ] Verify with metadata-only package lookup; do not run `npm install` just to test a registry.
- [ ] Explain that changing a registry can affect package integrity, lockfile resolution and scoped packages.

### Acceptance

- [ ] npm, pnpm and Yarn settings are detected independently.
- [ ] Scoped registries retain their mapping.
- [ ] Authentication values are redacted and preserved.
- [ ] Existing project registry configuration is not changed by a user-level operation.
- [ ] Package lockfiles remain unchanged during test and apply unless the user explicitly requests a dependency operation (which is outside the mirror-manager scope).
- [ ] Rollback restores only files/settings managed by the operation.

---

## 9. Docker and OCI registries (P2)

Docker requires two separate adapters:

1. The **Docker Engine APT repository**, which is an ordinary signed APT source and must be preserved as a third-party repository.
2. The **Docker Hub registry mirror**, which is daemon-level configuration for image pulls and has different behavior from an APT mirror.

### Docker Engine APT repository

- [ ] Detect Docker's repository file, keyring and architecture/suite settings.
- [ ] Test repository metadata and keyring validity without replacing official Docker instructions or keys.
- [ ] Do not merge this repository into Ubuntu's official archive source file.

### Docker Hub mirror

- [ ] Detect Docker Engine and `/etc/docker/daemon.json`.
- [ ] Explain that Docker daemon registry mirrors are for Docker Hub and are not a universal replacement for every OCI registry.
- [ ] Support user-provided and approved mirror endpoints.
- [ ] Merge the `registry-mirrors` key without deleting unrelated daemon options.
- [ ] Validate JSON before writing.
- [ ] Back up daemon configuration and record the current service state.
- [ ] Show that applying the change requires a Docker daemon reload/restart.
- [ ] Never restart Docker automatically as part of a general "optimize everything" action.
- [ ] Require a separate explicit confirmation before restarting Docker.
- [ ] If restart fails, restore the previous daemon configuration and explain the required recovery action; do not silently kill workloads.
- [ ] Do not add insecure registries or disable TLS verification.
- [ ] Do not configure a third-party registry as if it were a Docker Hub mirror.

### Additional container runtimes

- [ ] Treat containerd and Podman as separate future adapters with their own config, validation and restart behavior.
- [ ] Do not edit Kubernetes node runtime settings in the initial Docker phase.

---

## 10. Go modules (P3)

- [ ] Detect Go version and effective `go env GOPROXY`, `GOSUMDB`, `GOPRIVATE`, `GONOPROXY` and `GONOSUMDB` values.
- [ ] Test compatible Go module proxy endpoints using the Go module proxy protocol, not just a homepage GET.
- [ ] Support user-level `go env -w GOPROXY=...` with a captured prior value.
- [ ] Preserve private module patterns and direct-access behavior.
- [ ] Preserve `GOSUMDB` verification; never set it to `off` as an automatic workaround.
- [ ] Explain the difference between comma and pipe fallback separators in GOPROXY chains.
- [ ] Avoid sending private module paths to public proxies.
- [ ] Verify with a known public module metadata query without changing `go.mod` or `go.sum`.
- [ ] Mask private proxy URLs or embedded credentials in logs and reports.

---

## 11. Rust Cargo (P3)

- [ ] Detect Rust/Cargo version and existing `~/.cargo/config.toml` and project `.cargo/config.toml`.
- [ ] Support crates.io-compatible sparse registry and supported mirror/source-replacement configuration.
- [ ] Validate that a source replacement is an equivalent mirror of the original registry, not a way to inject unrelated packages.
- [ ] Preserve checksum verification and Git source configuration.
- [ ] Keep project-specific source overrides untouched unless the user explicitly chooses project scope.
- [ ] Verify registry/index metadata without running a build or changing `Cargo.lock`.
- [ ] Backup and restore the exact Cargo config files changed.

---

## 12. PHP Composer (P3)

- [ ] Detect PHP and Composer versions.
- [ ] Detect global Composer config, project `composer.json`, `composer.lock` and Packagist settings.
- [ ] Support compatible Composer repositories and approved Packagist mirrors.
- [ ] Preserve private repositories and repository priority/order.
- [ ] Explain that repository declarations and priorities can change which package is selected.
- [ ] Do not edit project `composer.json` or lockfiles during global configuration.
- [ ] Do not write authentication tokens into the mirror catalog or diagnostics.
- [ ] Verify repository metadata without installing or updating dependencies.

---

## 13. Java Maven and Gradle (P3)

### Maven

- [ ] Detect Maven version and `${user.home}/.m2/settings.xml`.
- [ ] Support mirror declarations with explicit `mirrorOf` rules.
- [ ] Preserve servers, credentials, profiles, proxies and existing mirrors.
- [ ] Do not replace private or project-defined repositories without an explicit preview.
- [ ] Verify metadata resolution without altering project dependency files.

### Gradle

- [ ] Detect Gradle version, user init scripts and project repository declarations.
- [ ] Prefer a user-level init script for optional global repository routing when supported and appropriate.
- [ ] Preserve plugin repositories, dependency repositories, content filters and exclusive content rules.
- [ ] Warn that repository order and content filters affect dependency resolution.
- [ ] Do not edit build files automatically.
- [ ] Test with a non-mutating dependency metadata operation appropriate to the installed Gradle version.

---

## 14. Additional ecosystems (P4)

These adapters are intentionally lower priority than APT, Python, Node and Docker.

### RubyGems / Bundler

- [ ] Detect `gem sources`, user config and project Gemfile source definitions.
- [ ] Support a validated RubyGems mirror.
- [ ] Preserve private gem sources and Bundler source blocks.
- [ ] Do not change Gemfile.lock during testing.

### Conda / Mamba / micromamba

- [ ] Detect `.condarc`, channels, channel aliases and environment-specific settings.
- [ ] Support validated channel mirrors with correct platform subdirectories and repodata.
- [ ] Preserve channel priority and strict-priority behavior.
- [ ] Do not mix channel content from unrelated providers without explicit approval.
- [ ] Do not rewrite environment lock files.

### Binary and toolchain downloads

- [ ] Support opt-in per-tool download source overrides only where upstream provides a documented mechanism.
- [ ] Cover selected Python, Node.js, Go and Rust toolchain distributions only after signature/checksum verification is designed.
- [ ] Do not use a global `git config url.*.insteadOf` rewrite as a general network accelerator.
- [ ] Do not rewrite arbitrary GitHub/GitLab release URLs or disable checksum/signature checks.

### Snap / Flatpak

- [ ] Keep Snap and Flatpak out of the initial server-focused scope.
- [ ] Revisit only if a supported, documented and safe mirror-management mechanism is available for the relevant client and platform.

---

## 15. Configuration scopes and profiles

All adapters must declare the configuration scope they can safely manage.

| Scope | Meaning | Default policy |
|---|---|---|
| Current command | Environment variables passed only to one process | Safest test/preview option |
| Current user | User config under `$HOME` | Default for language package managers |
| Active environment | Current venv, Conda env or project tool environment | Preferred when explicitly selected |
| Project | Project manifest or local tool config | Never modify without explicit project-scope selection and diff preview |
| System | `/etc`, global package manager or daemon config | Root required, explicit confirmation |
| Service/daemon | Docker/containerd or similar service config | Separate confirmation for restart/reload |

### Profiles

- [ ] `default`: safest non-invasive settings.
- [ ] `iran`: manually selected Iran-focused sources from the validated catalog.
- [ ] `region:<name>`: selected geographic catalog subset.
- [ ] `official-only`: official upstream sources only.
- [ ] `custom`: user-defined endpoints and explicit trust labels.
- [ ] Export/import profiles without secrets.
- [ ] Preview a profile across selected ecosystems before applying it.
- [ ] Profiles must not silently enable an ecosystem that is not installed or detected.

No profile should modify all ecosystems by default. The user selects the ecosystems and scopes to include.

---

## 16. CLI and automation design

The interactive menu is not a replacement for automation. Keep a stable CLI with predictable exit codes and JSON output.

### Proposed command groups

```text
power-apt-boost --help
power-apt-boost --version
power-apt-boost --status [--json]
power-apt-boost --doctor [--json]
power-apt-boost --list --ecosystem <apt|python|node|docker|go|rust|php|java>
power-apt-boost --test-mirrors --ecosystem <name> [--country <code>]
power-apt-boost --select-mirror --ecosystem <name> [--country <code>] [--dry-run]
power-apt-boost --apply-profile <name> --dry-run
power-apt-boost --backup [--ecosystem <name>]
power-apt-boost --restore [--restore-path <path>]
power-apt-boost --reset --ecosystem <name> --scope <scope> --dry-run
```

### Global options

- [ ] `--dry-run` for every mutating operation.
- [ ] `--yes` for explicit non-interactive apply; it must not bypass safety preconditions.
- [ ] `--json` with a documented schema and version.
- [ ] `--quiet`, `--verbose`, `--no-spinner` with consistent behavior.
- [ ] `--timeout`, `--concurrency`, `--ipv4`, `--ipv6`.
- [ ] `--country`, `--region`, `--profile`.
- [ ] `--config`, `--log-file`.
- [ ] `--backup-dir` only if it does not weaken permission defaults.
- [ ] Stable exit codes for usage, privilege, unsupported OS, no compatible source, verification failure, backup failure, rollback failure and partial operation.

### JSON contract

- [ ] Emit valid JSON even when an operation fails, when JSON output was requested and the process reached the structured error handler.
- [ ] Keep progress and diagnostics out of stdout in JSON mode.
- [ ] Include schema version, tool version, operation, ecosystem, scope, selected source, measured results, changed files, backup ID, verification result and rollback result.
- [ ] Redact passwords, tokens, Authorization headers, URL user-info and sensitive private host/path data by default.
- [ ] Add contract tests for every schema version.

---

## 17. Internal architecture and delivery model

### 17.1 Shared engine

The long-term implementation should separate responsibilities conceptually:

- **CLI / Menu layer:** parses user intent and renders the UI.
- **OS detector:** Ubuntu release, codename, architecture and capabilities.
- **Catalog layer:** official/community/custom source definitions and validation.
- **Probe engine:** bounded concurrency, protocol-specific checks, metrics and scoring.
- **Ecosystem adapters:** inspect, preview, backup, apply, verify and restore for each package manager.
- **Backup manager:** manifests, checksums, permissions and transactional restore.
- **Config/profile layer:** validated settings and selected ecosystems/scopes.
- **Output layer:** terminal, logs and versioned JSON.

Do not let each adapter implement a separate, inconsistent backup or confirmation flow.

### 17.2 Single-file release, modular development

- [ ] Keep `power-apt-boost.sh` as the public standalone release artifact.
- [ ] Consider splitting development sources into modules only when the build process is deterministic and tested.
- [ ] Add a build/assembly script that creates the single-file release from source modules.
- [ ] Add a test that generated release content matches the tested source revision.
- [ ] Keep a direct developer path that does not require a complex build system.
- [ ] Do not introduce Python, Node.js or other runtimes as mandatory dependencies for the Bash tool.
- [ ] Optional dependencies such as `whiptail`, `jq`, `dig` or ecosystem clients must be detected and have graceful fallbacks.

### 17.3 Configuration storage

- [ ] Use a documented config location under `/etc/power-apt-boost/` for system defaults and/or `$XDG_CONFIG_HOME/power-apt-boost/` for user preferences.
- [ ] Keep secrets out of the main config and profile export.
- [ ] Validate config syntax and reject unknown security-sensitive fields rather than sourcing config as shell code.
- [ ] Use restrictive permissions for system config and backups.
- [ ] Add schema version and migration behavior before changing config formats.

### 17.4 Concurrency and process safety

- [ ] Use a lock for mutation operations.
- [ ] Use bounded worker pools and wait/cleanup every child process.
- [ ] Ensure interrupt and termination handling cannot leave partial files or orphaned workers.
- [ ] Keep temporary files on the relevant filesystem when atomic rename is required.
- [ ] Never use broad process-kill patterns.
- [ ] Report partial completion accurately when a multi-ecosystem profile fails partway through.

---

## 18. Security and privacy requirements

- [ ] Maintain least privilege: only APT/system/daemon operations require root.
- [ ] Never run a remote script or catalog payload as code.
- [ ] Never disable TLS verification, APT signature verification or package checksums automatically.
- [ ] Preserve upstream signing keys and keyring references.
- [ ] Treat custom mirrors as untrusted until the user marks them trusted; trust labels do not bypass cryptographic verification.
- [ ] Avoid dependency-confusion configurations for pip, uv, Poetry, npm and Composer.
- [ ] Preserve private registry scope and namespace boundaries.
- [ ] Redact credentials in all output channels.
- [ ] Avoid storing secrets in backup manifests; if a changed file contains credentials, protect the backup as sensitive data.
- [ ] Validate URLs and reject unsupported schemes, embedded shell metacharacter execution paths and malformed hostnames.
- [ ] Protect against symlink/path traversal when writing, backing up or restoring files.
- [ ] Use atomic writes and safe permissions.
- [ ] Add a security review checklist for every adapter and mirror catalog update.
- [ ] Document network destinations contacted by each ecosystem probe.

---

## 19. Testing strategy and CI

### Test layers

**Unit tests**

- [ ] Argument parsing, defaults and validation.
- [ ] Country/region/catalog filtering.
- [ ] URL normalization and validation.
- [ ] Probe response classification and scoring.
- [ ] JSON encoding and secret redaction.
- [ ] Config parsing and preserving unknown fields.
- [ ] Backup manifest validation and checksums.

**Offline integration tests**

- [ ] Use a temporary fake root directory instead of touching the runner's real `/etc/apt`.
- [ ] Use local fixture HTTP servers or deterministic command shims for probe tests.
- [ ] Simulate success, 404, 403, 429, 5xx, timeout, TLS failure and abrupt interruption.
- [ ] Test successful backup/apply/verify.
- [ ] Test failure at every mutation step and verify exact rollback.
- [ ] Test missing files, existing third-party files, symlinks, permissions and spaces in paths.
- [ ] Test concurrent executions and lock handling.
- [ ] Assert dry-run performs no writes, deletes, service restarts or package installations.

**Adapter contract tests**

- [ ] Every adapter implements detect, inspect, list, test, preview, backup, apply, verify and restore as applicable.
- [ ] Every adapter declares privilege needs and the exact scope it can modify.
- [ ] Every adapter preserves unrelated keys and values.
- [ ] Every adapter has tests for credential masking.

**Live smoke tests**

- [ ] Optional, rate-limited scheduled tests against a small allowlisted subset of public mirrors.
- [ ] Never make ordinary CI depend on a public mirror being online.
- [ ] Do not run destructive apply/restore operations against the GitHub Actions host.

### CI matrix

- [ ] Ubuntu 22.04 LTS.
- [ ] Ubuntu 24.04 LTS.
- [ ] Ubuntu 26.04 LTS.
- [ ] Ubuntu 26.10 as an optional interim-release compatibility job.
- [ ] Ubuntu 20.04 only as a documented legacy/best-effort job if it remains in the declared support policy.
- [ ] Run ShellCheck, shfmt, the complete test runner, build verification and documentation/link checks.
- [ ] Run Bats or another test framework only if its dependency and maintenance cost are justified; do not leave the current test runner unused.
- [ ] Use pinned action versions or commit SHAs according to the repository's supply-chain policy.
- [ ] Set minimal workflow permissions.
- [ ] Keep release creation separate from ordinary CI.

### Release validation

- [ ] Validate version consistency across script, README, changelog, tag and release metadata.
- [ ] Generate the standalone script from the exact tested source.
- [ ] Run the full test suite against the generated release artifact.
- [ ] Produce SHA256 checksum and publish it with the release.
- [ ] Optionally sign release artifacts when a maintainable signing key/process exists.
- [ ] Include supported Ubuntu versions, known limitations, migration notes and rollback steps.

---

## 20. Documentation and project maintenance

- [ ] Rewrite README around the product's real supported capabilities and safe quick-start options.
- [ ] Keep the README feature list generated or validated against the CLI help where practical.
- [ ] Maintain a complete option reference with privilege, scope and side-effect notes.
- [ ] Add a dedicated interactive-menu guide.
- [ ] Add per-ecosystem guides: APT, Python, Node, Docker, Go, Rust, PHP and Java.
- [ ] Add configuration-scope examples and reset/restore instructions.
- [ ] Add a mirror-provider review policy and source provenance.
- [ ] Define supported Ubuntu versions and EOL/legacy policy.
- [ ] Update SECURITY.md to match real backup, write and rollback guarantees.
- [ ] Update SUPPORT.md with reproducible diagnostics instructions.
- [ ] Keep CHANGELOG entries under Unreleased until a release is actually published.
- [ ] Keep ROADMAP checkboxes honest; move completed features to changelog/release notes.
- [ ] Remove stale version badges, unsupported compatibility claims and old roadmap milestones.
- [ ] Add a known-limitations section, especially for package managers with project-scoped config.

---

## 21. Phased implementation plan

Phases are ordered by dependencies. Each phase should be implemented in a focused branch/PR, reviewed, tested and accepted before starting the next one. Do not bundle unrelated cleanup into a phase.

### Phase 0 — Baseline, versioning and specification

**Goal:** Make the repository's declared behavior match its actual code and establish a testable baseline.

- [ ] Re-read current `main`, default branch, open PRs, tags, releases and recent CI before editing.
- [ ] Capture the current public CLI/help output and exit-code behavior.
- [ ] Resolve the `3.0.0` script vs `2.1.0` public release/tag/badge mismatch.
- [ ] Reconcile README, CHANGELOG, SECURITY, SUPPORT and ROADMAP claims.
- [ ] Decide and document supported Ubuntu releases and architectures.
- [ ] Create a feature inventory: implemented, partially implemented, broken/inconsistent, not implemented.
- [ ] Establish baseline test output and known failures.
- [ ] Freeze existing CLI compatibility expectations before refactoring.

**Acceptance criteria**

- [ ] Every documented option has a tested parse/help behavior.
- [ ] Version and release metadata are internally consistent, without creating a release prematurely.
- [ ] The repository roadmap no longer marks already implemented features as future work.
- [ ] No runtime behavior is changed beyond explicitly approved baseline fixes.

### Phase 1 — Core safety and correctness

**Goal:** Make every existing APT operation predictable and reversible.

- [x] Fix stale test expectations and ensure the full test runner is called by CI.
- [x] Make backup creation fail closed when any required copy/metadata operation fails.
- [x] Add a backup manifest with checksums and prior file-existence state.
- [x] Implement exact restore semantics, including removing files created by the failed operation.
- [x] Make APT writes atomic and permission-aware.
- [x] Add a mutation lock.
- [x] Fix `--skip-update` so it does not remove package lists before skipping the update.
- [x] Unify timeout configuration and correct probe timing/status parsing.
- [x] Make `--ipv6`, ForceIPv4/ForceIPv6 and generated APT config consistent.
- [x] Make `--no-spinner` functional.
- [x] Align `--list` health checks with the selection engine.
- [x] Correct country filtering with structured catalog metadata.
- [x] Define deterministic exit codes and interrupt behavior.
- [x] Prove dry-run is side-effect-free.

**Acceptance criteria**

- [x] Injected backup, atomic-write, APT write, `apt-get update`, restore-install and checksum failures either preserve or restore the original managed APT state, or return the dedicated recovery error.
- [x] The automated regression suite uses mocked probes and no live external mirror.
- [x] ShellCheck, shfmt and all offline tests pass on Ubuntu 20.04, 22.04 and 24.04 (52 tests per matrix job).
- [x] Existing documented CLI options remain available; unsupported country codes and invalid timeout ranges are rejected explicitly.

### Phase 2 — Interactive menu and shared command model

**Goal:** Add an approachable terminal interface without splitting business logic from the CLI.

- [x] Add TTY detection and non-interactive behavior.
- [x] Implement numbered Bash menu fallback.
- [x] Add optional `whiptail` UI when installed.
- [x] Add Overview, APT, Benchmark, Backup/Restore, Diagnostics and Settings screens.
- [x] Add reusable confirmation, preview, cancel and back navigation helpers.
- [x] Ensure every menu action calls the same functions as the CLI.
- [x] Add `--status` and `--doctor` CLI commands.
- [x] Add a consistent JSON output schema and tests.

**Acceptance criteria**

- [x] Piped execution never blocks on menu input.
- [x] Every destructive operation shows the exact scope and files before apply.
- [x] Cancel leaves the system unchanged.
- [x] Menu and CLI produce equivalent operation results.

### Phase 3 — Mirror catalog and benchmark engine

**Goal:** Replace hard-coded URL assumptions with a validated, ecosystem-aware catalog and trustworthy benchmark data.

- [x] Define and validate catalog schema.
- [x] Separate built-in, dynamically discovered and user-defined entries.
- [x] Integrate Ubuntu mirror discovery as one input.
- [x] Add cache of last known-good catalog.
- [x] Add protocol-aware APT probe and Release-metadata verification.
- [x] Add bounded concurrency and configurable timeout/retry policy.
- [x] Record latency, response code, redirect, freshness and availability measurements.
- [x] Add deterministic compatibility gates and documented scoring.
- [x] Add manual region selection and official-only profile.
- [x] Add custom mirror validation and add/remove/disable/enable actions.

**Acceptance criteria**

- [x] Catalog discovery failure falls back to a schema-valid last-known-good cache; a manually supplied mirror can be verified independently of discovery.
- [x] Invalid, stale, incompatible, redirected-to-untrusted or unsigned sources cannot win merely because they are fast.
- [x] Benchmark/list paths remain read-only: no package installation and no APT configuration mutation.

### Phase 4 — Complete Ubuntu APT manager

**Goal:** Finish the APT experience beyond selecting an archive URL.

- [x] Complete APT source inventory and status display across legacy and Deb822 formats, including duplicate URI/suite reporting.
- [x] Add archive/security/ports/suite-aware selection with architecture guards and a separate security pocket where required.
- [x] Preserve third-party source files and legacy source-line options; refuse unsafe rewrites of mixed, modified, symlinked or unclassified managed files.
- [x] Add safe APT proxy set/clear management without accepting embedded credentials.
- [x] Add bounded APT network timeout/retry management.
- [x] Add diagnostics for signature trust prerequisites and insecure overrides, cached metadata age, opt-in DNS/TLS, proxies and duplicate sources.
- [x] Add selective restore scopes and checksum-verified backup cleanup/retention.
- [x] Add explicit apply preview and keep persistent changes scoped to APT source/network configuration.

**Acceptance criteria**

- [x] Supported Ubuntu releases in the CI matrix can be inspected, benchmarked, optimized and restored without destructive changes to third-party source configuration.
- [x] Security repositories remain enabled and the generated Ubuntu sources retain explicit archive keyring verification.
- [x] Apply reports success only after the generated configuration passes APT parser verification (and `apt-get update` succeeds unless explicitly skipped).

### Phase 5 — Python ecosystem manager

**Goal:** Safely inspect and manage Python package indexes for pip, uv and Poetry, while detecting pipx without rewriting its isolated application environments.

- [x] Detect python3, pip, the active virtual environment, pipx, uv and Poetry; detect the PEP 668 externally-managed marker.
- [x] Report pip user/site/global index settings and environment override variable names without exposing their values.
- [x] Validate user-supplied HTTPS PEP 503/691 Simple API endpoints and check one advertised distribution endpoint without installing or downloading a complete package.
- [x] Add pip user, active-venv and global index scopes with environment-override guards and PEP 668 protection for global writes.
- [x] Add uv user, system and project index configuration with explicit default-index conflict checks and preservation of existing source declarations.
- [x] Add Poetry project sources with supplemental, primary and explicit priority semantics.
- [x] Add project TOML preview and opt-in atomic editing; reject symlinked, non-regular, invalid or unsupported TOML targets.
- [x] Add managed-source reset and conflict-checked snapshot restore for pip, uv and Poetry.
- [x] Add offline coverage for credentials, private source preservation, project source pins, PEP 668, environment overrides, TOML parser absence and restore conflicts.
- [ ] Add a curated, provenance-reviewed PyPI mirror catalogue and discovery/refresh workflow.
- [ ] Add a dedicated pipx source adapter after its selected backend and existing venv policy can be managed without changing installed application environments.

**Scope decisions**

- This phase tests and configures a URL explicitly supplied by the user. It does not claim that a built-in list of regional PyPI mirrors is current or trustworthy; catalogue discovery is a separate follow-up.
- pipx is detected and reported only. Its application environments can use different pip/uv backends and are deliberately not rewritten by the shared pip or uv configuration operations.
- uv/Poetry editing requires Python 3.11+ (`tomllib`) or an already-installed `tomli`; the tool never installs a parser automatically.
- The artifact check reports whether SHA-256 metadata is advertised, but does not download a whole distribution to recalculate its digest.

**Acceptance criteria**

- [x] A user-supplied Python mirror can be tested and selected without installing a package.
- [x] Existing private sources and project pins are preserved; dependency files and lockfile hashes are never rewritten.
- [x] No unsupported or PEP 668 externally-managed system Python environment is modified.
- [x] Preview is read-only and reset/restore only affects app-managed configuration after a conflict check.

### Phase 6 — Node.js registries

**Goal:** Support npm, pnpm, Yarn Classic and Yarn Berry.

- [x] Detect Node.js, npm, pnpm and Yarn versions; distinguish Yarn Classic from Berry.
- [x] Validate credential-free HTTPS registry URLs and check npm-compatible package metadata plus the advertised tarball host using HEAD only.
- [x] Add default user-level registry configuration through native npm, pnpm and Yarn commands.
- [x] Preserve scoped registries, authentication values, unrelated config, package.json/publishConfig and Yarn Berry's separate npmPublishRegistry.
- [x] Add explicit project-scope opt-in requiring a project directory and regular package.json, with a redacted current/proposed diff preview.
- [x] Add target-specific snapshots, read-back verification, SHA-256 conflict checks, reset/restore and offline rollback tests.

**Acceptance criteria**

- [x] No package archive is downloaded or installed; package manifests and lockfiles remain untouched.
- [x] Existing private scopes, authentication entries, unrelated config and separate publish settings remain intact.

### Phase 7 — Docker / OCI support

**Goal:** Safely manage Docker Engine repository discovery and optional Docker Hub registry-mirror settings.

- [x] Add read-only Docker Engine APT source inspection, separately classified from OCI image registry mirrors.
- [x] Add a documented Docker Hub cache candidate and HTTPS Registry V2 endpoint verification using `GET /v2/` only.
- [x] Add safe `daemon.json` merge, Docker-native validation, restricted backup, exact restore and SHA-256 conflict checks.
- [x] Add a separate Docker daemon restart action with an explicit confirmation and running-workload warning.
- [x] Add offline failure/recovery tests for malformed config, preservation of existing settings, rollback conflicts and restart gating.

**Acceptance criteria**

- [x] No daemon restart occurs during configuration or restore; a separately confirmed action is required.
- [x] Existing daemon settings and registry-mirror entries are preserved.
- [x] CLI, JSON status and terminal UI clearly distinguish an APT repository from an OCI image registry mirror.

**Implementation:** [PR #8](https://github.com/power0matin/power-apt-boost/pull/8) — open for final CI verification.  
**Exact implementation CI:** Commit `b67dd68f8c25e2ac1ad747721079842aab0953fe` passed ShellCheck, shfmt and the offline matrix: Ubuntu 20.04 (262/262), Ubuntu 22.04 (262/262), Ubuntu 24.04 (280/280). [CI run #110](https://github.com/power0matin/power-apt-boost/actions/runs/44664543497).  
**Live validation boundary:** CI uses an offline Registry V2 probe stub. No public registry, pull-through-cache behavior, image pull, Docker installation or running daemon was tested or changed. `mirror.gcr.io` is documented as a partial cache, not a complete mirror.

### Phase 8 — Go, Rust, PHP and Java adapters

**Goal:** Add developer package ecosystems with integrity-aware configuration.

- [ ] Go GOPROXY with GOSUMDB/private-module preservation.
- [ ] Cargo registry/source replacement with checksum preservation.
- [ ] Composer repository configuration with source-priority preservation.
- [ ] Maven mirrors and Gradle init-script support.
- [ ] Adapter contract tests and isolated rollback for each.

**Acceptance criteria**

- [ ] Every adapter has a non-mutating test path and explicit configuration scope.
- [ ] Private namespaces and authentication are preserved.

### Phase 9 — Additional ecosystems and automation

**Goal:** Add only ecosystems with a clear and safe configuration mechanism.

- [ ] Evaluate RubyGems/Bundler.
- [ ] Evaluate Conda/Mamba channels.
- [ ] Evaluate selected toolchain binary download sources.
- [ ] Add optional scheduled mirror checks only after a clear user opt-in.
- [ ] Export/import profiles without secrets.
- [ ] Add compact diagnostics bundle and benchmark history if useful without installing a daemon.

**Acceptance criteria**

- [ ] No persistent timer/service is installed by default.
- [ ] New adapters meet the same security, testing and rollback contracts.

### Phase 10 — Release hardening and public documentation

**Goal:** Make releases reproducible and the product straightforward to adopt.

- [ ] Decide whether modular development sources are justified; if so, add deterministic single-file assembly.
- [ ] Test the generated standalone script.
- [ ] Complete CI matrix for Ubuntu 22.04, 24.04 and 26.04 LTS, with optional 26.10.
- [ ] Add optional rate-limited live mirror smoke tests.
- [ ] Add release checksum and documented verification procedure.
- [ ] Align README, CLI help, changelog, security policy and release notes.
- [ ] Publish a compatibility/support matrix and migration guide.
- [ ] Tag and release only after all gates pass.

**Acceptance criteria**

- [ ] A clean Ubuntu host can run the documented install and validation workflow.
- [ ] Published script checksum matches the tested artifact.
- [ ] Version, tag, release, README badge and changelog agree.
- [ ] Full offline test suite and CI matrix pass.

---

## 22. Definition of Done for every feature

A feature is not complete merely because its happy path works. Every feature/adapter must satisfy all applicable items:

- [ ] Scope and side effects are documented.
- [ ] Existing configuration is detected before writing.
- [ ] Read-only inspection works without root where possible.
- [ ] Dry-run generates an accurate plan and performs no mutation.
- [ ] Backup is validated before mutation.
- [ ] Writes are atomic and permissions are safe.
- [ ] Existing unrelated settings are preserved.
- [ ] Verification uses the ecosystem's actual protocol/tool.
- [ ] Failure triggers complete rollback or a clearly documented recovery procedure.
- [ ] Secrets are redacted from output/logs/JSON.
- [ ] Unit and offline integration tests cover success and failure paths.
- [ ] CLI help, README and changelog are updated.
- [ ] No unrelated refactor or scope expansion is included.

---

## 23. Phase 0 completion record and execution order

### Phase 0 — Baseline verification and roadmap formalization

**Goal:** establish a reviewed, accurate baseline and a single implementation plan before changing runtime behavior.

- [x] Confirm repository identity, default branch and baseline commit.
- [x] Inspect the current Bash entry point, command-line surface, APT write paths and mirror-selection flow.
- [x] Review README, CHANGELOG, existing roadmap, SECURITY policy, test runner, CI and release workflow.
- [x] Record implementation risks separately from confirmed runtime test results; this phase is a static repository review.
- [x] Define Ubuntu-first boundaries and separate package-ecosystem adapters for APT, Python, Node.js, Docker/OCI and other tools.
- [x] Define phase order, acceptance criteria, safety rules and the per-phase PR/merge gate.
- [x] Publish this roadmap and align public documentation with the current source/release state and observed side effects.
- [ ] Review and merge the Phase 0 pull request.

**Acceptance criteria**

- [ ] The detailed roadmap is present in the default branch.
- [ ] README and security documentation do not claim guarantees that the current implementation does not provide.
- [ ] Current source version and latest published release are clearly distinguished.
- [ ] No runtime behavior or system configuration is changed by Phase 0.

### Recommended implementation order after Phase 0

1. **Phase 1:** fix safety and correctness in the current Ubuntu APT implementation.
2. **Phase 2:** add the interactive menu and status/doctor commands.
3. **Phase 3:** establish the catalog and benchmark engine.
4. **Phase 4:** complete Ubuntu APT management.
5. **Phase 5:** implement Python package-source management.
6. **Phase 6:** implement Node.js registries.
7. **Phase 7:** add Docker/OCI support.
8. Continue with the remaining adapters only after the earlier adapters pass their acceptance gates.

Do not start a later phase simply because its UI item is visible in the menu. A menu option for an unimplemented adapter must be clearly marked unavailable or hidden until the adapter is ready.

---

## 24. Reference documentation

The implementation must follow the current official behavior of each ecosystem. Re-check these documents when implementing an adapter; command-line flags and configuration locations can change between tool versions.

### Ubuntu and APT

- [Ubuntu mirrors index service](https://ubuntu.com/docs/launchpad/developer/reference/services/ubuntu-mirrors-index/)
- [Ubuntu mirror requirements and existing mirrors](https://ubuntu.com/project/docs/release-team/mirrors/)
- [Ubuntu release notes](https://documentation.ubuntu.com/release-notes/)
- [Ubuntu releases and support lifecycle](https://wiki.ubuntu.com/Releases)

### Python

- [pip configuration](https://pip.pypa.io/en/stable/topics/configuration/)
- [pip install and index options](https://pip.pypa.io/en/stable/cli/pip_install/)
- [uv package indexes](https://docs.astral.sh/uv/concepts/indexes/)
- [Poetry repositories and source priorities](https://python-poetry.org/docs/repositories/)
- [Poetry configuration](https://python-poetry.org/docs/configuration/)

### Node.js

- [npm registry configuration](https://docs.npmjs.com/using-npm/registry/)
- [pnpm configuration](https://pnpm.io/cli/config)
- [Yarn configuration](https://yarnpkg.com/configuration/yarnrc)

### Containers and other ecosystems

- [Docker Engine installation on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [Docker Hub registry mirror](https://docs.docker.com/docker-hub/image-library/mirror/)
- [Go Modules Reference](https://go.dev/ref/mod)
- [Cargo source replacement](https://doc.rust-lang.org/cargo/reference/source-replacement.html)
- [Composer repositories](https://getcomposer.org/doc/05-repositories.md)
- [Maven mirror settings](https://maven.apache.org/guides/mini/guide-mirror-settings)
- [Gradle repository configuration](https://docs.gradle.org/current/userguide/centralizing_repositories.html)

---

## 25. Roadmap status

This roadmap is intentionally comprehensive. It does not authorize implementing every phase in one change.

**Current execution state:** Phase 7 Docker Engine / OCI registry support is implemented in [PR #8](https://github.com/power0matin/power-apt-boost/pull/8); PR is open pending final exact-head CI verification.  
**Previous phases:** PRs #1-#7 are merged into `main`; Phase 6 is merged at `9baba4a2ca553c70e7ada89f2148c3d8d862935e`.  
**Phase 7 implementation CI:** Commit `b67dd68f8c25e2ac1ad747721079842aab0953fe` passed ShellCheck, shfmt and offline tests on Ubuntu 20.04 (262/262), 22.04 (262/262) and 24.04 (280/280). [CI run](https://github.com/power0matin/power-apt-boost/actions/runs/44664543497). The final PR head includes a documentation-only roadmap sync and is being checked separately.  
**Next permitted work unit:** Merge PR #8 only after its final exact-head CI is green; then begin Phase 8.  
**Python scope:** pip, uv and Poetry configuration are managed; pipx is detected only; curated PyPI catalogue discovery remains a follow-up.  
**Node.js scope:** npm, pnpm, Yarn Classic and Berry are supported with user scope by default and explicit project scope; scoped registries and auth entries are preserved.  
**Docker / OCI scope:** Docker Engine APT sources are inspected read-only and separately from OCI mirrors. daemon.json changes are backed up, validated and conflict-checked; Docker restart is always a separate confirmed operation. Registry V2 CI tests are offline; no live Docker pull-through cache was validated.  
**Release/deployment status:** No release, tag or deployment has been created.  
**Earlier live validation:** Public Ubuntu mirror discovery/signature checks and live PyPI probes are opt-in runtime checks, not CI prerequisites.
