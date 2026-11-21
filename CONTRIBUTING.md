# Contributing to Linux Package Source Manager

Thank you for considering contributing to Linux Package Source Manager! This document provides guidelines and instructions for contributing.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How to Contribute](#how-to-contribute)
- [Development Setup](#development-setup)
- [Code Style](#code-style)
- [Testing](#testing)
- [Pull Request Process](#pull-request-process)
- [Reporting Bugs](#reporting-bugs)
- [Suggesting Features](#suggesting-features)

## Code of Conduct

This project adheres to the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## How to Contribute

### Reporting Bugs

Before creating bug reports, please check existing issues to avoid duplicates.

When creating a bug report, include:

- **Clear title and description**
- **Steps to reproduce**
- **Expected behavior**
- **Actual behavior**
- **OS and Ubuntu version** (`cat /etc/os-release`)
- **Script version** (`bash src/linux-package-source-manager.sh --version`)
- **Network environment** (VPS provider, region, proxy)

### Suggesting Features

Feature suggestions are welcome. Please include:

- **Use case**: Why is this feature needed?
- **Expected behavior**: What should it do?
- **Alternatives considered**: What other approaches did you think about?

### Contributing Code

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes
4. Run tests
5. Submit a pull request

## Development Setup

### Prerequisites

- Bash 4.0+
- ShellCheck
- shfmt
- Ubuntu 20.04+ (for testing)
- curl or wget

### Local Development

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/linux-package-source-manager.git
cd linux-package-source-manager

# Make the script executable
chmod +x src/linux-package-source-manager.sh install.sh

# Run shellcheck
shellcheck -x src/linux-package-source-manager.sh install.sh tests/test_installer.sh

# Run shfmt
shfmt -d src/linux-package-source-manager.sh install.sh tests/test_installer.sh

# Test locally (dry run)
sudo bash src/linux-package-source-manager.sh --dry-run
```

### Testing

```bash
# Run all tests
bash tests/run_tests.sh
bash tests/test_installer.sh

# Run shellcheck
shellcheck -x src/linux-package-source-manager.sh install.sh tests/test_installer.sh

# Run shfmt check
shfmt -d src/linux-package-source-manager.sh install.sh tests/test_installer.sh
```

## Code Style

### Bash

- Use `set -euo pipefail` at the top
- Quote all variables: `"$var"` not `$var`
- Use `[[ ]]` for tests, not `[ ]`
- Use `readonly` for constants
- Use `local` for function variables
- Single blank line between functions
- Two blank lines between major sections
- Functions named with `_lowercase_underscore` (private) or `lowercase_underscore` (public)
- No command substitution in `[[ ]]` — use `$(command)` syntax

### ShellCheck

All code must pass ShellCheck with zero warnings:

```bash
shellcheck -x src/linux-package-source-manager.sh install.sh tests/test_installer.sh
```

### shfmt

All code must be formatted with shfmt:

```bash
# Check formatting
shfmt -d src/linux-package-source-manager.sh

# Auto-fix formatting
shfmt -w src/linux-package-source-manager.sh install.sh tests/test_installer.sh
```

### Comments

- No comments explaining what code does — the code should be self-documenting
- Comments explain **why** something is done, not **what** is done
- Use section headers for major code blocks:

```bash
# === Section Name ===========================================================
```

### Naming Conventions

- **Global variables**: `UPPER_SNAKE_CASE`
- **Local variables**: `lowercase_snake_case`
- **Functions**: `lowercase_snake_case`
- **Constants**: `readonly` + `UPPER_SNAKE_CASE`
- **Private functions**: prefix with `_`

## Pull Request Process

1. **Update documentation** if your change affects user-facing behavior
2. **Add changelog entry** under an `[Unreleased]` section in CHANGELOG.md
3. **Ensure CI passes** — all checks must be green
4. **Write a clear PR description** explaining what and why

### PR Title Convention

Use [Conventional Commits](https://www.conventionalcommits.org/) format:

- `feat: add --parallel flag for concurrent mirror testing`
- `fix: handle missing keyring gracefully`
- `docs: update installation instructions`
- `refactor: extract mirror testing into separate function`
- `test: add integration tests for --restore`

### PR Checklist

- [ ] ShellCheck passes
- [ ] shfmt passes
- [ ] Tests pass
- [ ] Documentation updated (if applicable)
- [ ] Changelog updated
- [ ] No unrelated changes included
- [ ] Commit messages follow conventional commits

## Project Structure

```
linux-package-source-manager/
|-- .github/                              # GitHub workflows and templates
|-- assets/                               # Repository branding
|-- docs/
|   \-- ROADMAP.md
|-- src/
|   \-- linux-package-source-manager.sh  # Main single-file application
|-- tests/                                # Offline regression and installer tests
|-- install.sh                            # Version-pinned verified bootstrap
|-- README.md
|-- CHANGELOG.md
|-- CONTRIBUTING.md
|-- CODE_OF_CONDUCT.md
|-- SECURITY.md
|-- SUPPORT.md
|-- LICENSE
|-- .editorconfig
|-- .gitattributes
|-- .gitignore
|-- .markdownlint.json
\-- .shellcheckrc
```

## Architecture Decisions

### Single-File Design

Linux Package Source Manager keeps its application in one standalone Bash file. The small `install.sh` bootstrap is a separate launcher: it fetches the version-pinned release artifact and checksum, verifies the checksum, checks Bash syntax, and runs the application in the active terminal. The recommended entry point is:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/power0matin/linux-package-source-manager/main/install.sh)
```

The tracked main application lives in `src/` as one Bash file. The release workflow packages it under the stable asset name `linux-package-source-manager.sh`; the bootstrap does not split the application into modules or install a persistent component.

### Deb822 Format

The script writes APT sources in deb822 format (`.sources` files) rather than the legacy `sources.list` format. This is the modern standard used by Ubuntu 24.04+.

### No External Dependencies

The script uses only tools available on a default Ubuntu installation: bash, curl/wget, coreutils, and apt. No Python, Perl, or other runtimes required.

## Questions?

Open a [GitHub Discussion](https://github.com/power0matin/linux-package-source-manager/discussions) or check the [FAQ](README.md#faq) in the README.
