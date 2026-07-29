# Design and modernization notes

## Purpose

ConnectServers is intentionally small: detect the network context of a Mac and
mount the SMB resources appropriate to that context. The modernization keeps
the utility understandable as a shell script while removing assumptions that
made the 2019 implementation brittle.

## Original implementation review

The original script demonstrated a useful automation idea in very little code,
but several behaviors no longer represented the desired outcome reliably:

1. **Computer name was treated as location.** A name containing `ATL` describes
   device inventory, not the network the device currently uses.
2. **ICMP ping was treated as proof that SMB would work.** Networks commonly
   block ping while allowing SMB, or allow ping while blocking SMB.
3. **A failed connectivity check did not stop mounting.** The `internet`
   variable was changed but never used to gate the site function.
4. **Finder was controlled by menu labels and button names.** UI scripting
   depends on localization, accessibility permission, and preference-window
   layouts that have changed since 2019.
5. **The script always returned success.** Callers could not distinguish a
   completed mount from an unsupported computer, offline network, or failed
   authentication.
6. **Configuration and behavior were coupled.** Adding a site required editing
   program logic and duplicating a function.
7. **Repeat runs were not idempotent.** Already-mounted resources were attempted
   again.
8. **There was no non-destructive inspection path.** Testing required executing
   the actual mount flow.

## Current architecture

```text
configuration
     |
     v
validate records
     |
     v
macOS DNS state -----> DNS suffix match
     |                       |
     |                       v
     +---------------> SMB port 445 probe
                             |
                             v
                     exactly one site?
                       /           \
                     no             yes
                     |               |
                 stop safely     inspect mounts
                                      |
                             +--------+--------+
                             |                 |
                       already mounted     not mounted
                             |                 |
                            skip       Finder/Keychain mount
```

### Location evidence

Automatic selection requires two independent pieces of evidence:

- a configured DNS suffix appears in the active macOS resolver state; and
- the site's SMB probe accepts a TCP connection on port 445.

The DNS rule describes network context. The port probe describes the actual
service needed. Requiring both reduces false positives while supporting Wi-Fi,
Ethernet, and VPN without separate code paths.

A site may use `*` as its DNS rule when a unique probe is enough. This is a
documented compatibility escape hatch, not the preferred multi-site design.

### Mount mechanism

The script invokes AppleScript's `mount volume` command with the SMB URL passed
as an argument, rather than interpolating it into AppleScript source. This has
three useful properties:

- Finder presents the native authentication experience.
- macOS can retrieve previously approved credentials from Keychain.
- user and configuration values do not become executable AppleScript text.

Direct `mount_smbfs` use was considered but not selected. It would require the
script to manage mount points and authentication details itself, increasing
both operational and security complexity.

### Idempotence

Before mounting, the script examines the current mount table for the target
server and top-level SMB share. Existing mounts are skipped. A URI that points
to a subdirectory of an already-mounted share is therefore also treated as
mounted, because SMB mounts occur at the share boundary.

### Configuration format

A pipe-delimited line format was chosen over JSON or YAML because current
macOS installations do not guarantee `jq`, Python, or a YAML parser. The format
supports the required data without executing the configuration as shell code.

The configuration is data, not a sourced script. That prevents an edited site
record from silently becoming arbitrary shell execution.

### Runtime choice

The script targets POSIX `/bin/sh`:

- no Homebrew dependency;
- no dependency on a particular Bash release;
- no Python requirement; and
- straightforward syntax and static analysis.

The project remains a script rather than becoming a signed application. For a
large managed deployment, a signed app using Apple's current service-management
framework would provide a more polished installation, update, and background
execution model.

## Failure model

The exit status is part of the interface:

| Status | Meaning |
|---:|---|
| `0` | Operation or inspection completed successfully |
| `2` | Invalid arguments or configuration |
| `3` | Unsupported platform or missing required command |
| `4` | No unique reachable site |
| `5` | At least one share failed to mount |

Mounts are independent. If one succeeds and another fails, the successful
mount remains and the final status is `5`. The script does not undo valid work
because another server or share is unavailable.

## Security properties

- Passwords in SMB URL authorities are rejected during configuration
  validation.
- Displayed SMB URLs omit the username.
- SMB URLs are passed to AppleScript as arguments, not source text.
- Username placeholder values use a conservative character allowlist.
- Site configuration is not sourced or evaluated.
- Automatic matching requires real network evidence.
- No Finder preferences, system preferences, Keychain entries, or network
  settings are modified directly.

Diagnostics expose network domains, internal hostnames, and mounted SMB paths.
This is useful operational data but may be sensitive. Users should review
diagnostic output before posting it publicly.

## macOS alignment

The design follows Apple's documented user-facing mechanisms:

- Finder supports connections to SMB servers:
  <https://support.apple.com/guide/mac-help/mchlp1140/mac>
- Protected server passwords may be retrieved from Keychain with user approval:
  <https://support.apple.com/guide/keychain-access/kyca1243/mac>
- Login and background items are visible and managed in modern macOS:
  <https://support.apple.com/guide/deployment/depdca572563/web>

The script does not disable SMB signing or negotiate validation. Apple's
current documentation identifies SMB 3 as the default on macOS and describes
its security requirements:
<https://support.apple.com/101956>.

## Verification strategy

The test suite replaces `uname`, `scutil`, `nc`, `mount`, and `osascript` with
temporary controlled commands. It verifies:

- configuration validation;
- automatic and explicit site selection;
- DNS suffix matching;
- SMB reachability requirements;
- ambiguity refusal;
- idempotent mount behavior;
- dry-run and diagnostic behavior;
- password rejection; and
- partial mount failure status.

GitHub Actions runs shell syntax checks, the behavior suite, and ShellCheck on a
macOS runner. Actual access to private SMB infrastructure is intentionally not
part of public CI.

## Deliberate non-goals

- Discovering arbitrary SMB servers
- Storing or rotating passwords
- Installing VPN software or initiating VPN sessions
- Changing Finder desktop/sidebar preferences
- Unmounting shares from a previously selected site
- Silently installing a background daemon
- Replacing organizational MDM or identity policy

Keeping these responsibilities out of the script makes its authority and
failure behavior easier to understand.
