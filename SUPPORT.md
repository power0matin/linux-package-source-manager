# Support

## Getting Help

### Documentation

- [README](README.md) — Full usage guide
- [CHANGELOG](CHANGELOG.md) — Version history
- [CONTRIBUTING](CONTRIBUTING.md) — How to contribute

### Common Issues

### Open the interactive menu on a new server

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/power0matin/linux-package-source-manager/main/install.sh)
```

The bootstrap is pinned to the current release, verifies the downloaded application with its SHA-256 checksum, and requests `sudo` authorization when needed. The one-line command requires Bash and curl; the bootstrap also uses `sha256sum` and a private temporary directory.

### Bootstrap reports a download or checksum error

- Check that the server can reach GitHub Releases over HTTPS.
- Do not bypass a checksum failure or run a partially downloaded script.
- Confirm that the release includes `linux-package-source-manager.sh` and `linux-package-source-manager.sh.sha256`.
- Use the [manual, checksum-verified installation steps](README.md#manual-installation-from-a-pinned-release) when needed.


#### "This script must be run as root"

```bash
sudo bash src/linux-package-source-manager.sh
```

#### "curl or wget is required"

Install curl:

```bash
apt-get install -y curl
```

#### "No working mirror found"

- Check your network connection
- Try with a longer timeout: `sudo bash src/linux-package-source-manager.sh --timeout 60`
- Try a specific mirror: `sudo bash src/linux-package-source-manager.sh --mirror https://archive.ubuntu.com/ubuntu`

#### "apt-get update failed after applying mirror"

The script automatically restores the previous configuration. Check:

```bash
ls -la /var/backups/power-apt-boost/
sudo bash src/linux-package-source-manager.sh --restore
```

#### How to restore a previous configuration

```bash
sudo bash src/linux-package-source-manager.sh --restore
```

Or restore from a specific backup:

```bash
sudo bash src/linux-package-source-manager.sh --restore-path /var/backups/power-apt-boost/2025-01-01_12-00-00
```

## Reporting Issues

- [GitHub Issues](https://github.com/power0matin/linux-package-source-manager/issues) — Bug reports and feature requests
- [GitHub Discussions](https://github.com/power0matin/linux-package-source-manager/discussions) — Questions and ideas

When reporting a bug, include:

1. Ubuntu version (`cat /etc/os-release`)
2. Script version (`bash src/linux-package-source-manager.sh --version`)
3. Exact command you ran
4. Full error output
5. Network environment (VPS provider, region)

## Security Issues

See [SECURITY.md](SECURITY.md) for how to report security vulnerabilities.
