# Configuration reference

ConnectServers keeps environment-specific details outside the executable
script. This makes the behavior reviewable, permits multiple locations, and
allows the script to be upgraded without repeatedly editing code.

## File discovery

The first available source in this order is used:

1. `--config PATH`
2. The `CONNECTSERVERS_CONFIG` environment variable
3. `~/Library/Application Support/connectservers/sites.conf`
4. `sites.conf` in the same directory as `ConnectServers.sh`

The last option is useful for a portable folder. A root-level `sites.conf` is
ignored by Git so that local server information is not committed by accident.

The example file is never selected implicitly. Copy it before use:

```sh
mkdir -p "$HOME/Library/Application Support/connectservers"
cp examples/sites.conf \
  "$HOME/Library/Application Support/connectservers/sites.conf"
```

## Record format

The file is line-oriented UTF-8 text:

```text
site_id|dns_suffixes|smb_probe_host|semicolon-separated_smb_urls
```

Blank lines and lines beginning with `#` are ignored. Do not place spaces
around the pipe delimiters.

### Field 1: site ID

The ID:

- must be unique;
- may contain letters, numbers, dots, underscores, and hyphens;
- is accepted by `--site ID`; and
- appears in logs and diagnostic output.

Examples: `atl`, `denver-office`, `corp.vpn`.

### Field 2: DNS suffixes

Specify one or more comma-separated DNS suffixes:

```text
atl.example.com,corp.example.com
```

A configured suffix matches either the exact current DNS domain or one of its
parent suffixes. For example, `corp.example.com` matches both
`corp.example.com` and `vpn.corp.example.com`.

The special value `*` means the DNS check always succeeds. The site then
depends entirely on SMB probe reachability. This preserves the behavior needed
by simple single-site environments, but a real suffix is safer when multiple
locations or VPN routes may be reachable simultaneously.

ConnectServers reads the resolver state from `scutil --dns`. It does not infer
location from the Wi-Fi network name because:

- Ethernet and VPN connections may have no Wi-Fi SSID;
- SSID access has changed across macOS privacy releases; and
- DNS context plus service reachability describes the capability the script
  actually needs.

### Field 3: SMB probe host

This is a DNS hostname or IP address that should accept SMB on TCP port 445 at
the site:

```text
atlfs01
```

The probe should normally be the server used by the site's shares. The script
does not authenticate during the probe; it only verifies that a TCP connection
can be established within the configured timeout.

The default timeout is three seconds. Override it with `--timeout 1..30` or the
`CONNECTSERVERS_TIMEOUT` environment variable.

### Field 4: SMB URLs

Separate multiple URLs with semicolons:

```text
smb://{user}@atlfs01/users/{user};smb://{user}@atlfs01/shared
```

Rules:

- Every item must begin with `smb://`.
- Every item must contain both a host and share path.
- Literal whitespace is rejected. Percent-encode a space as `%20`.
- `{user}` is replaced everywhere with the selected username.
- Password-bearing authorities such as `user:password@host` are rejected.

The default username comes from the macOS login. Override it when the directory
service uses a different name:

```sh
./ConnectServers.sh --user j.smith
```

Usernames may contain letters, numbers, dots, underscores, and hyphens. This
restriction makes placeholder substitution unambiguous and prevents malformed
URLs.

## Complete examples

### Single office

```text
atl|atl.example.com|atlfs01|smb://{user}@atlfs01/users/{user};smb://{user}@atlfs01/shared
```

The site matches only when the current resolver domain ends in
`atl.example.com` and `atlfs01:445` is reachable.

### Office and VPN

```text
atl-office|atl.example.com|atlfs01|smb://{user}@atlfs01/users/{user};smb://{user}@atlfs01/shared
corp-vpn|vpn.example.com|vpnfs01|smb://{user}@vpnfs01/home/{user};smb://{user}@vpnfs01/projects
```

If both records match, ConnectServers refuses to guess and exits with status
`4`. Use `--site atl-office` or `--site corp-vpn` to resolve the ambiguity.

### Reachability-only fallback

```text
legacy-site|*|fileserver|smb://{user}@fileserver/home/{user}
```

Use `*` only when `fileserver:445` is uniquely reachable in the relevant
network contexts.

### Share name with a space

```text
design|design.example.com|designfs01|smb://{user}@designfs01/Creative%20Assets
```

## Selection semantics

Automatic selection requires:

```text
DNS rule matches AND SMB probe is reachable
```

Exactly one site must satisfy that expression.

`--site ID` bypasses only the DNS rule. It still verifies that the selected
probe is reachable, preventing an offline mount attempt and an unnecessary
credential dialog.

## Validation

Run:

```sh
./ConnectServers.sh --check-config
```

Validation catches:

- missing or unreadable files;
- empty configurations;
- malformed or duplicate site IDs;
- extra pipe-delimited fields;
- missing DNS rules or probe hosts;
- invalid SMB URLs;
- whitespace that should be percent-encoded; and
- embedded passwords.

This mode is intentionally platform-independent, so a configuration can be
checked during continuous integration without contacting an internal network.

## Environment variables

| Variable | Purpose |
|---|---|
| `CONNECTSERVERS_CONFIG` | Default configuration path; overridden by `--config` |
| `CONNECTSERVERS_TIMEOUT` | Default SMB probe timeout in seconds |
| `CONNECTSERVERS_PATH` | Controlled command search path for tests or managed deployment |
| `USER` | Default value for `{user}` |

Command-line options take precedence where an equivalent option exists.
