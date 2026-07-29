# ConnectServers

[![CI](https://github.com/imyourpriest/connectservers/actions/workflows/ci.yml/badge.svg)](https://github.com/imyourpriest/connectservers/actions/workflows/ci.yml)

ConnectServers detects which configured network location a Mac can currently
reach and mounts the SMB shares assigned to that location.

The project began in 2019 as a short Bash/AppleScript utility. Version 2 keeps
that original purpose while replacing hard-coded hostname checks, ICMP ping,
and Finder UI automation with a configuration-driven and testable design.

## What it does

1. Reads site definitions from a plain-text configuration file.
2. Collects the DNS search domains currently reported by macOS.
3. Checks whether each site's SMB probe accepts TCP connections on port 445.
4. Selects the one site for which both the DNS rule and SMB probe match.
5. Skips shares that macOS has already mounted.
6. Asks Finder to mount the remaining shares.

Finder handles authentication. The configuration contains usernames only as a
placeholder and must never contain passwords. On the first connection, macOS
can prompt for credentials and save them in Keychain.

## Improvements over the original

| Area | Original behavior | Version 2 behavior |
|---|---|---|
| Location | Inferred from the computer name | Determined from DNS context and SMB reachability |
| Connectivity | One ICMP ping | Direct TCP check of the service actually needed |
| Sites and shares | Hard-coded in the script | Defined in an external configuration file |
| Authentication | Finder prompt | Finder prompt with Keychain support; passwords rejected in config |
| Repeat runs | Attempts every mount again | Detects and skips existing SMB mounts |
| Finder settings | Clicks preference-window controls | Does not modify Finder preferences |
| Failure handling | Always exits with status `0` | Distinct configuration, platform, location, and mount errors |
| Inspection | Dialog boxes only | Dry-run, diagnostics, site listing, and verbose logging |
| Verification | None | Deterministic tests plus GitHub Actions |

The detailed engineering decisions are recorded in
[docs/DESIGN.md](docs/DESIGN.md).

## Requirements

- macOS
- Network access to the configured SMB server or the organization's VPN
- A valid account on each configured SMB server
- Standard macOS commands only; Homebrew, Python, and `jq` are not required

The script is written for `/bin/sh` rather than Homebrew Bash. This avoids
requiring a separate runtime and avoids depending on the old Bash version
bundled with some macOS releases.

## Quick start

### 1. Install the script and configuration

Clone or download the repository, then make the script executable:

```sh
chmod 755 ConnectServers.sh
```

Create the per-user configuration directory and copy the example:

```sh
mkdir -p "$HOME/Library/Application Support/connectservers"
cp examples/sites.conf \
  "$HOME/Library/Application Support/connectservers/sites.conf"
```

Edit `sites.conf` for the real locations, DNS suffixes, servers, and shares.
The included `atl` record preserves the server paths used by the original
script, but it should still be reviewed before use.

### 2. Validate before connecting

Configuration validation does not contact a network or mount anything:

```sh
./ConnectServers.sh --check-config
```

Next, inspect what the Mac can currently see:

```sh
./ConnectServers.sh --diagnose
```

Finally, perform a dry run:

```sh
./ConnectServers.sh --dry-run --verbose
```

### 3. Mount the shares

```sh
./ConnectServers.sh
```

The first run may display the standard macOS server-authentication prompt.
Enter the server credentials and choose the option to remember them in
Keychain if that is allowed by organizational policy.

## Configuration at a glance

Each non-comment line contains four pipe-delimited fields:

```text
site_id|dns_suffixes|smb_probe_host|semicolon-separated_smb_urls
```

Example:

```text
atl|atl.example.com,corp.example.com|atlfs01|smb://{user}@atlfs01/users/{user};smb://{user}@atlfs01/shared
```

- `site_id` is the name accepted by `--site`.
- `dns_suffixes` is a comma-separated set. `*` means that reachable SMB alone
  is enough to match the site.
- `smb_probe_host` is tested on TCP port 445.
- `smb_urls` is a semicolon-separated set of Finder-compatible SMB URLs.
- `{user}` is replaced with the current macOS username or `--user NAME`.

Prefer real DNS suffixes over `*` when multiple sites can be reached at once,
such as through a full-tunnel VPN.

See [docs/CONFIGURATION.md](docs/CONFIGURATION.md) for the complete schema,
examples, validation rules, and configuration precedence.

## Commands

```text
ConnectServers.sh [options]
ConnectServers.sh --diagnose [options]
ConnectServers.sh --list-sites [--config PATH]
ConnectServers.sh --check-config [--config PATH]
```

Common examples:

```sh
# Let the script select the single matching site.
./ConnectServers.sh

# Select a configured site but still require its SMB service to be reachable.
./ConnectServers.sh --site atl

# Show decisions and intended mounts without changing the Mac.
./ConnectServers.sh --dry-run --verbose

# Use a different configuration and directory-service username.
./ConnectServers.sh \
  --config "$HOME/Documents/work-sites.conf" \
  --user j.smith

# Print network and mount evidence suitable for troubleshooting.
./ConnectServers.sh --diagnose
```

Run `./ConnectServers.sh --help` for every option and the exit-code reference.

## Automatic use on macOS

For laptops, manual use or a macOS Shortcut is generally the least surprising
choice: a login-time process may run before Wi-Fi or VPN is ready.

To make a double-clickable application:

1. Open Automator and create an **Application**.
2. Add the **Run Shell Script** action.
3. Enter the absolute script and configuration paths, for example:

   ```sh
   /bin/sh "/Users/you/Applications/connectservers/ConnectServers.sh" \
     --config "/Users/you/Library/Application Support/connectservers/sites.conf"
   ```

4. Save the application and run it once to approve any macOS prompts.
5. Optionally add that application under **System Settings > General > Login
   Items & Extensions**.

Apple documents both
[shell scripts in Automator](https://support.apple.com/guide/automator/aut4bb6b2b4f/mac)
and
[Login Items](https://support.apple.com/guide/mac-help/mh15189/mac).

Organizations deploying this broadly should package a signed app and use
Apple's current service-management or device-management mechanisms instead of
silently installing a background script. macOS 13 and later deliberately make
login and background items visible to users.

## Security

- Never put a password, token, or `user:password@host` value in `sites.conf`.
  The validator rejects password-bearing SMB authorities.
- Keep the per-user configuration readable only by the appropriate user if it
  contains internal hostnames.
- Prefer DNS hostnames over IP addresses so directory-backed SMB can use the
  organization's expected authentication and signing configuration.
- Finder may retrieve a saved server password from Keychain. macOS can ask
  whether access should be allowed once, always allowed, or denied.
- Logs deliberately remove the username from displayed SMB URLs. Diagnostics
  still reveal configured hostnames and mounted paths, so review them before
  sharing outside the organization.

Apple's current guidance confirms that SMB is supported through Finder and
that protected server credentials can be retrieved from Keychain:

- [Connect a Mac to shared computers and servers](https://support.apple.com/guide/mac-help/mchlp1140/mac)
- [If you are asked for access to your keychain](https://support.apple.com/guide/keychain-access/kyca1243/mac)

## Troubleshooting and maintenance

Start with:

```sh
./ConnectServers.sh --diagnose
./ConnectServers.sh --dry-run --verbose
```

Then consult [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

The test suite can run without an SMB server because it replaces macOS network
commands with controlled fixtures:

```sh
./tests/test_connectservers.sh
```

Syntax validation:

```sh
sh -n ConnectServers.sh tests/test_connectservers.sh
```

The GitHub Actions workflow runs the syntax check, tests, and ShellCheck on a
macOS runner for every push and pull request.

## Project boundaries

This repository modernizes only the ConnectServers utility. The author's
separate historical PHP and Python CircleCI proof-of-concept repositories are
intentionally outside this project's scope.
