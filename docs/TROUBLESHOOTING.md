# Troubleshooting

## Start with diagnostics

Run these commands from Terminal:

```sh
./ConnectServers.sh --diagnose
./ConnectServers.sh --dry-run --verbose
```

Diagnostics do not authenticate or mount shares. They show:

- the configuration path;
- macOS DNS search domains;
- DNS and SMB results for every configured site; and
- the current SMB mount table.

The output can contain internal domain names, server names, and share paths.
Review it before sharing it outside the organization.

## “No configuration found”

Create the default directory and copy the example:

```sh
mkdir -p "$HOME/Library/Application Support/connectservers"
cp examples/sites.conf \
  "$HOME/Library/Application Support/connectservers/sites.conf"
```

Then validate it:

```sh
./ConnectServers.sh --check-config
```

If the configuration lives somewhere else, use `--config PATH`.

## “No configured site matches”

The script could not find a site for which both conditions were true:

1. the site's DNS rule matched; and
2. the site's SMB probe accepted a connection on port 445.

Check `--diagnose`:

- **DNS match = no:** Confirm the suffix in `sites.conf` appears in the DNS
  list. Connect the expected VPN if the suffix is VPN-provided.
- **SMB reachable = no:** Confirm the VPN or office network is connected,
  verify the probe hostname, and make sure TCP port 445 is permitted.
- **Both = no:** The Mac is likely outside the configured network context.

To test one record without relying on its DNS rule:

```sh
./ConnectServers.sh --site SITE_ID --dry-run --verbose
```

An explicit site still requires its SMB probe to be reachable.

## “Multiple sites match”

More than one record matched the current network. This can happen when:

- multiple records use `*`;
- a VPN exposes several site file servers; or
- DNS suffix rules overlap.

Prefer more specific DNS suffixes and unique probe hosts. For an intentional
overlap, choose explicitly:

```sh
./ConnectServers.sh --site SITE_ID
```

The script refuses to choose arbitrarily because mounting the wrong site's
resources can expose data in the wrong context.

## Authentication prompt appears every time

On the next standard server-authentication prompt:

1. choose **Registered User**;
2. verify the account name;
3. enter the server password; and
4. select the option to remember the password in Keychain, if organizational
   policy allows it.

If Keychain asks whether the process may retrieve the stored item, select the
access level appropriate to the environment. Apple explains the **Allow Once**,
**Always Allow**, and **Deny** choices in
[Keychain Access Help](https://support.apple.com/guide/keychain-access/kyca1243/mac).

Do not work around the prompt by adding a password to the SMB URL. The
configuration validator deliberately blocks that pattern.

## “Failed to mount”

Re-run with `--verbose` to include the Finder/AppleScript error:

```sh
./ConnectServers.sh --site SITE_ID --verbose
```

Common causes:

- the username differs from the Mac login; use `--user NAME`;
- the account lacks permission to the share;
- the share name is misspelled;
- a space was not encoded as `%20`;
- stored Keychain credentials are obsolete;
- the SMB server requires directory or Kerberos conditions the Mac does not
  currently meet; or
- network policy permits TCP establishment but blocks later SMB negotiation.

Use DNS server names instead of IP addresses when the organization relies on
directory-backed authentication. Apple's SMB guidance notes that Kerberos
authentication requires the server to be specified using DNS.

## A share is reported as already mounted

ConnectServers checks the server and top-level SMB share in the macOS mount
table. For:

```text
smb://server/users/j.smith
```

the SMB share boundary is `server/users`; `j.smith` is a subdirectory. If that
share is mounted by another URL, it is still considered mounted.

To reconnect with different credentials, eject the existing volume in Finder
and run the script again.

## The script runs too early at login

Wi-Fi and VPN may not be ready when a login item starts. Recommended options:

- run the Automator application manually after the network is ready;
- create a Shortcut or menu-bar action for one-click use; or
- use an organization-managed, signed helper that responds to network changes.

Avoid an aggressive timer that repeatedly triggers authentication prompts.
The script is idempotent after a successful mount, but failed authentication is
still a user-visible event.

## Finder does not show mounted servers on the desktop

The original script changed this preference through UI automation. Version 2
does not modify Finder preferences.

Use Finder settings to choose whether connected servers appear on the desktop.
The volumes remain available through Finder's sidebar and `/Volumes`
regardless of the desktop-icon preference.

## Configuration error involving whitespace

Do not use literal spaces inside an SMB URL. Percent-encode them:

```text
Wrong: smb://server/Creative Assets
Right: smb://server/Creative%20Assets
```

Spaces are allowed in the configuration file's path because path arguments are
quoted normally.

## Unsupported platform

Mount and diagnostic modes require macOS. `--check-config`, `--list-sites`,
`--help`, and `--version` are platform-independent.

## Exit status for automation

| Status | Meaning | Suggested response |
|---:|---|---|
| `0` | Success | No action |
| `2` | Configuration or usage error | Correct arguments or `sites.conf` |
| `3` | Platform/runtime error | Run on macOS and verify system commands |
| `4` | No unique reachable site | Connect network/VPN or select a site |
| `5` | Partial or complete mount failure | Review verbose authentication/share errors |
