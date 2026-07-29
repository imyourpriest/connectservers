#!/bin/sh
#
# ConnectServers
# Select a configured network location and mount its SMB shares on macOS.
#
# The script intentionally uses only POSIX shell syntax and utilities included
# with macOS. Passwords are never accepted in configuration or command-line
# arguments; Finder handles authentication and can retrieve saved credentials
# from the user's Keychain.

set -u
set -f

VERSION="2.0.0"

EXIT_OK=0
EXIT_CONFIG=2
EXIT_PLATFORM=3
EXIT_LOCATION=4
EXIT_MOUNT=5

PROGRAM_NAME=${0##*/}
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P)
DEFAULT_CONFIG_FILE="${HOME:-}/Library/Application Support/connectservers/sites.conf"

CONFIG_FILE=${CONNECTSERVERS_CONFIG:-}
CONFIG_WAS_EXPLICIT=0
SITE_OVERRIDE=""
MOUNT_USER=${USER:-}
TIMEOUT=${CONNECTSERVERS_TIMEOUT:-3}
DRY_RUN=0
QUIET=0
VERBOSE=0
MODE="mount"

SELECTED_SITE=""
SELECTED_PROBE=""
SELECTED_SHARES=""
DNS_DOMAINS=""
MOUNT_STATE=""

# Tests and managed deployments can prepend controlled command locations
# without changing the user's interactive PATH.
PATH=${CONNECTSERVERS_PATH:-/usr/bin:/bin:/usr/sbin:/sbin}
export PATH

if [ -n "$CONFIG_FILE" ]; then
    CONFIG_WAS_EXPLICIT=1
fi

usage() {
    cat <<EOF
Usage:
  $PROGRAM_NAME [options]
  $PROGRAM_NAME --diagnose [options]
  $PROGRAM_NAME --list-sites [--config PATH]
  $PROGRAM_NAME --check-config [--config PATH]

Mount options:
  -c, --config PATH   Read site definitions from PATH.
  -s, --site ID       Select a site explicitly; still verify SMB reachability.
  -u, --user NAME     Use NAME in {user} placeholders (default: macOS user).
  -n, --dry-run       Detect and report without mounting anything.
  -t, --timeout SEC   SMB probe timeout from 1 to 30 seconds (default: 3).
  -v, --verbose       Include detection and mount details.
  -q, --quiet         Suppress routine status messages.

Inspection options:
      --diagnose      Show network evidence and site-match results; do not mount.
      --list-sites    List configured site IDs and probe hosts.
      --check-config  Validate the configuration without requiring macOS.
      --version       Print the program version.
  -h, --help          Show this help.

Exit codes:
  0  Success
  2  Invalid arguments or configuration
  3  Unsupported platform or missing macOS command
  4  No unique reachable site
  5  One or more shares failed to mount
EOF
}

timestamp() {
    date "+%Y-%m-%dT%H:%M:%S%z" 2>/dev/null || printf "unknown-time"
}

info() {
    if [ "$QUIET" -eq 0 ]; then
        printf "%s [INFO] %s\n" "$(timestamp)" "$*" >&2
    fi
}

debug() {
    if [ "$VERBOSE" -eq 1 ]; then
        printf "%s [DEBUG] %s\n" "$(timestamp)" "$*" >&2
    fi
}

error() {
    printf "%s [ERROR] %s\n" "$(timestamp)" "$*" >&2
}

die() {
    die_status=$1
    shift
    error "$*"
    exit "$die_status"
}

need_value() {
    if [ "$#" -lt 2 ] || [ -z "$2" ]; then
        die "$EXIT_CONFIG" "Option $1 requires a value."
    fi
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -c|--config)
            need_value "$@"
            CONFIG_FILE=$2
            CONFIG_WAS_EXPLICIT=1
            shift 2
            ;;
        -s|--site)
            need_value "$@"
            SITE_OVERRIDE=$2
            shift 2
            ;;
        -u|--user)
            need_value "$@"
            MOUNT_USER=$2
            shift 2
            ;;
        -n|--dry-run)
            DRY_RUN=1
            shift
            ;;
        -t|--timeout)
            need_value "$@"
            TIMEOUT=$2
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -q|--quiet)
            QUIET=1
            shift
            ;;
        --diagnose)
            MODE="diagnose"
            DRY_RUN=1
            shift
            ;;
        --list-sites)
            MODE="list"
            shift
            ;;
        --check-config)
            MODE="check"
            shift
            ;;
        --version)
            printf "%s %s\n" "$PROGRAM_NAME" "$VERSION"
            exit "$EXIT_OK"
            ;;
        -h|--help)
            usage
            exit "$EXIT_OK"
            ;;
        --)
            shift
            break
            ;;
        -*)
            die "$EXIT_CONFIG" "Unknown option: $1. Run $PROGRAM_NAME --help."
            ;;
        *)
            die "$EXIT_CONFIG" "Unexpected argument: $1. Run $PROGRAM_NAME --help."
            ;;
    esac
done

if [ "$#" -gt 0 ]; then
    die "$EXIT_CONFIG" "Unexpected argument: $1. Run $PROGRAM_NAME --help."
fi

case "$TIMEOUT" in
    ""|*[!0-9]*)
        die "$EXIT_CONFIG" "Timeout must be a whole number from 1 to 30."
        ;;
esac

if [ "$TIMEOUT" -lt 1 ] || [ "$TIMEOUT" -gt 30 ]; then
    die "$EXIT_CONFIG" "Timeout must be a whole number from 1 to 30."
fi

if [ -z "$MOUNT_USER" ]; then
    MOUNT_USER=$(id -un 2>/dev/null || printf "")
fi

case "$MOUNT_USER" in
    ""|*[!A-Za-z0-9._-]*)
        die "$EXIT_CONFIG" "The mount user may contain only letters, numbers, dots, underscores, and hyphens."
        ;;
esac

resolve_config() {
    if [ -n "$CONFIG_FILE" ]; then
        return
    fi

    if [ -r "$DEFAULT_CONFIG_FILE" ]; then
        CONFIG_FILE=$DEFAULT_CONFIG_FILE
        return
    fi

    if [ -r "$SCRIPT_DIR/sites.conf" ]; then
        CONFIG_FILE=$SCRIPT_DIR/sites.conf
        return
    fi

    CONFIG_FILE=$DEFAULT_CONFIG_FILE
}

validate_share_list() (
    vs_old_ifs=$IFS
    IFS=";"
    # shellcheck disable=SC2086 # Semicolon field splitting is intentional.
    set -- $1
    IFS=$vs_old_ifs

    if [ "$#" -eq 0 ]; then
        error "A site must define at least one SMB share."
        exit 1
    fi

    for vs_uri do
        case "$vs_uri" in
            smb://*) ;;
            *)
                error "Share '$vs_uri' must start with smb://."
                exit 1
                ;;
        esac

        case "$vs_uri" in
            *[[:space:]]*)
                error "Share '$vs_uri' contains whitespace; percent-encode spaces as %20."
                exit 1
                ;;
        esac

        vs_target=${vs_uri#smb://}
        case "$vs_target" in
            */*) ;;
            *)
                error "Share '$vs_uri' must include a server and share name."
                exit 1
                ;;
        esac

        vs_authority=${vs_target%%/*}
        vs_path=${vs_target#*/}
        if [ -z "$vs_authority" ] || [ -z "$vs_path" ]; then
            error "Share '$vs_uri' must include a server and share name."
            exit 1
        fi

        case "$vs_authority" in
            *:*@*)
                error "Share '$vs_uri' appears to contain a password. Store credentials in Keychain instead."
                exit 1
                ;;
        esac
    done
)

validate_config() {
    [ -r "$CONFIG_FILE" ] || {
        if [ "$CONFIG_WAS_EXPLICIT" -eq 1 ]; then
            die "$EXIT_CONFIG" "Configuration is not readable: $CONFIG_FILE"
        fi
        die "$EXIT_CONFIG" "No configuration found. Copy examples/sites.conf to '$DEFAULT_CONFIG_FILE' and edit it."
    }

    vc_line_number=0
    vc_site_count=0
    vc_seen=" "
    vc_cr=$(printf "\r")

    while IFS="|" read -r vc_site vc_domains vc_probe vc_shares vc_extra ||
          [ -n "$vc_site$vc_domains$vc_probe$vc_shares$vc_extra" ]; do
        vc_line_number=$((vc_line_number + 1))

        case "$vc_shares" in
            *"$vc_cr") vc_shares=${vc_shares%"$vc_cr"} ;;
        esac

        if [ -z "$vc_site$vc_domains$vc_probe$vc_shares$vc_extra" ]; then
            continue
        fi

        case "$vc_site" in
            \#*) continue ;;
        esac

        if [ -n "$vc_extra" ]; then
            die "$EXIT_CONFIG" "Configuration line $vc_line_number has more than four pipe-delimited fields."
        fi

        case "$vc_site" in
            ""|*[!A-Za-z0-9._-]*)
                die "$EXIT_CONFIG" "Invalid site ID on configuration line $vc_line_number."
                ;;
        esac

        case "$vc_seen" in
            *" $vc_site "*)
                die "$EXIT_CONFIG" "Duplicate site ID '$vc_site' on configuration line $vc_line_number."
                ;;
        esac
        vc_seen="$vc_seen$vc_site "

        if [ -z "$vc_domains" ]; then
            die "$EXIT_CONFIG" "Site '$vc_site' must define DNS suffixes or *."
        fi

        case "$vc_probe" in
            ""|*[!A-Za-z0-9._:-]*)
                die "$EXIT_CONFIG" "Site '$vc_site' has an invalid SMB probe host."
                ;;
        esac

        if ! validate_share_list "$vc_shares"; then
            die "$EXIT_CONFIG" "Invalid share list for site '$vc_site' on configuration line $vc_line_number."
        fi

        vc_site_count=$((vc_site_count + 1))
    done < "$CONFIG_FILE"

    if [ "$vc_site_count" -eq 0 ]; then
        die "$EXIT_CONFIG" "Configuration contains no site definitions: $CONFIG_FILE"
    fi
}

list_sites() {
    printf "%-20s %-30s %s\n" "SITE" "SMB PROBE" "DNS SUFFIXES"
    while IFS="|" read -r ls_site ls_domains ls_probe _; do
        case "$ls_site" in
            ""|\#*) continue ;;
        esac
        printf "%-20s %-30s %s\n" "$ls_site" "$ls_probe" "$ls_domains"
    done < "$CONFIG_FILE"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        die "$EXIT_PLATFORM" "Required command is unavailable: $1"
}

verify_macos_runtime() {
    require_command uname
    if [ "$(uname -s 2>/dev/null)" != "Darwin" ]; then
        die "$EXIT_PLATFORM" "ConnectServers mounts shares only on macOS."
    fi

    require_command awk
    require_command date
    require_command mount
    require_command nc
    require_command scutil
    require_command sed
    require_command tr

    if [ "$MODE" = "mount" ] && [ "$DRY_RUN" -eq 0 ]; then
        require_command osascript
    fi
}

load_network_state() {
    DNS_DOMAINS=$(
        scutil --dns 2>/dev/null |
            awk -F": " '
                /^[[:space:]]*(search )?domain(\[[0-9]+\])?[[:space:]]*:/ {
                    if ($2 != "") print $2
                }
            ' |
            tr "[:upper:]" "[:lower:]"
    )
    MOUNT_STATE=$(mount 2>/dev/null || printf "")
}

dns_matches() (
    dm_wanted=$1
    [ "$dm_wanted" = "*" ] && exit 0

    dm_old_ifs=$IFS
    IFS=","
    # shellcheck disable=SC2086 # Comma field splitting is intentional.
    set -- $dm_wanted
    IFS=$dm_old_ifs

    for dm_suffix do
        dm_suffix=$(printf "%s" "$dm_suffix" | tr "[:upper:]" "[:lower:]")
        [ -n "$dm_suffix" ] || continue

        while IFS= read -r dm_current; do
            case "$dm_current" in
                "$dm_suffix"|*."$dm_suffix") exit 0 ;;
            esac
        done <<EOF
$DNS_DOMAINS
EOF
    done

    exit 1
)

probe_reachable() {
    nc -G "$TIMEOUT" -w "$TIMEOUT" -z "$1" 445 >/dev/null 2>&1
}

site_matches() {
    sm_domains=$1
    sm_probe=$2

    SITE_DNS_MATCH=0
    SITE_REACHABLE=0
    SITE_MATCH=0

    if dns_matches "$sm_domains"; then
        SITE_DNS_MATCH=1
    fi

    if probe_reachable "$sm_probe"; then
        SITE_REACHABLE=1
    fi

    if [ "$SITE_DNS_MATCH" -eq 1 ] && [ "$SITE_REACHABLE" -eq 1 ]; then
        SITE_MATCH=1
    fi
}

select_site() {
    if [ -n "$SITE_OVERRIDE" ]; then
        ss_found=0
        while IFS="|" read -r ss_site ss_domains ss_probe ss_shares _; do
            case "$ss_site" in
                ""|\#*) continue ;;
            esac
            if [ "$ss_site" = "$SITE_OVERRIDE" ]; then
                SELECTED_SITE=$ss_site
                SELECTED_PROBE=$ss_probe
                SELECTED_SHARES=$ss_shares
                ss_found=1
                break
            fi
        done < "$CONFIG_FILE"

        if [ "$ss_found" -eq 0 ]; then
            die "$EXIT_CONFIG" "Unknown site '$SITE_OVERRIDE'. Run $PROGRAM_NAME --list-sites."
        fi

        if ! probe_reachable "$SELECTED_PROBE"; then
            die "$EXIT_LOCATION" "Site '$SELECTED_SITE' was selected, but $SELECTED_PROBE:445 is unreachable."
        fi

        debug "Explicit site '$SELECTED_SITE' is reachable through $SELECTED_PROBE:445."
        return
    fi

    ss_match_count=0
    ss_matched_ids=""

    while IFS="|" read -r ss_site ss_domains ss_probe ss_shares _; do
        case "$ss_site" in
            ""|\#*) continue ;;
        esac

        site_matches "$ss_domains" "$ss_probe"
        debug "Site '$ss_site': DNS match=$SITE_DNS_MATCH, SMB reachability=$SITE_REACHABLE."

        if [ "$SITE_MATCH" -eq 1 ]; then
            ss_match_count=$((ss_match_count + 1))
            ss_matched_ids="${ss_matched_ids}${ss_matched_ids:+, }$ss_site"
            SELECTED_SITE=$ss_site
            SELECTED_PROBE=$ss_probe
            SELECTED_SHARES=$ss_shares
        fi
    done < "$CONFIG_FILE"

    case "$ss_match_count" in
        0)
            die "$EXIT_LOCATION" "No configured site matches the current DNS state and reachable SMB services. Run $PROGRAM_NAME --diagnose."
            ;;
        1)
            return
            ;;
        *)
            die "$EXIT_LOCATION" "Multiple sites match ($ss_matched_ids). Re-run with --site ID."
            ;;
    esac
}

render_uri() {
    printf "%s\n" "$1" | sed "s/{user}/$MOUNT_USER/g"
}

sanitized_uri() (
    su_target=${1#smb://}
    su_authority=${su_target%%/*}
    su_path=${su_target#*/}
    su_host=${su_authority##*@}
    printf "smb://%s/%s\n" "$su_host" "$su_path"
)

is_share_mounted() (
    ism_mount_state=$1
    ism_uri=$2
    ism_target=${ism_uri#smb://}
    ism_authority=${ism_target%%/*}
    ism_path=${ism_target#*/}
    ism_host=${ism_authority##*@}
    ism_share=${ism_path%%/*}

    printf "%s\n" "$ism_mount_state" |
        awk -v with_user="@${ism_host}/${ism_share} on " \
            -v without_user="//${ism_host}/${ism_share} on " '
            {
                line = tolower($0)
                if (index(line, tolower(with_user)) || index(line, tolower(without_user))) {
                    found = 1
                }
            }
            END { exit(found ? 0 : 1) }
        '
)

mount_uri() {
    osascript \
        -e "on run argv" \
        -e "mount volume (item 1 of argv)" \
        -e "end run" \
        "$1"
}

mount_selected_site() {
    ms_old_ifs=$IFS
    IFS=";"
    # shellcheck disable=SC2086 # Semicolon field splitting is intentional.
    set -- $SELECTED_SHARES
    IFS=$ms_old_ifs

    ms_mounted=0
    ms_existing=0
    ms_failed=0

    for ms_template do
        ms_uri=$(render_uri "$ms_template")
        ms_display=$(sanitized_uri "$ms_uri")

        if is_share_mounted "$MOUNT_STATE" "$ms_uri"; then
            info "Already mounted: $ms_display"
            ms_existing=$((ms_existing + 1))
            continue
        fi

        if [ "$DRY_RUN" -eq 1 ]; then
            info "Would mount: $ms_display"
            ms_mounted=$((ms_mounted + 1))
            continue
        fi

        info "Mounting: $ms_display"
        if ms_output=$(mount_uri "$ms_uri" 2>&1); then
            ms_mounted=$((ms_mounted + 1))
            MOUNT_STATE=$(mount 2>/dev/null || printf "")
        else
            ms_failed=$((ms_failed + 1))
            error "Failed to mount: $ms_display"
            if [ -n "$ms_output" ]; then
                debug "$ms_output"
            fi
        fi
    done

    if [ "$DRY_RUN" -eq 1 ]; then
        info "Dry run complete for '$SELECTED_SITE': $ms_mounted share(s) would mount, $ms_existing already mounted."
    else
        info "Finished '$SELECTED_SITE': $ms_mounted mounted, $ms_existing already mounted, $ms_failed failed."
    fi

    [ "$ms_failed" -eq 0 ] || return "$EXIT_MOUNT"
}

diagnose() {
    dg_computer_name=$(scutil --get ComputerName 2>/dev/null || printf "unavailable")

    printf "ConnectServers diagnostics\n"
    printf "  version:       %s\n" "$VERSION"
    printf "  computer name: %s\n" "$dg_computer_name"
    printf "  mount user:    %s\n" "$MOUNT_USER"
    printf "  configuration: %s\n" "$CONFIG_FILE"
    printf "  probe timeout: %ss\n" "$TIMEOUT"
    printf "\nDNS domains reported by macOS:\n"

    if [ -n "$DNS_DOMAINS" ]; then
        while IFS= read -r dg_domain; do
            printf "  - %s\n" "$dg_domain"
        done <<EOF
$DNS_DOMAINS
EOF
    else
        printf "  (none)\n"
    fi

    printf "\nConfigured site checks:\n"
    printf "%-20s %-10s %-14s %s\n" "SITE" "DNS MATCH" "SMB REACHABLE" "PROBE"
    while IFS="|" read -r dg_site dg_domains dg_probe _; do
        case "$dg_site" in
            ""|\#*) continue ;;
        esac
        site_matches "$dg_domains" "$dg_probe"
        if [ "$SITE_DNS_MATCH" -eq 1 ]; then dg_dns="yes"; else dg_dns="no"; fi
        if [ "$SITE_REACHABLE" -eq 1 ]; then dg_smb="yes"; else dg_smb="no"; fi
        printf "%-20s %-10s %-14s %s:445\n" "$dg_site" "$dg_dns" "$dg_smb" "$dg_probe"
    done < "$CONFIG_FILE"

    printf "\nMounted SMB filesystems:\n"
    dg_found_mount=0
    while IFS= read -r dg_mount; do
        case "$dg_mount" in
            *smbfs*)
                printf "  %s\n" "$dg_mount"
                dg_found_mount=1
                ;;
        esac
    done <<EOF
$MOUNT_STATE
EOF

    if [ "$dg_found_mount" -eq 0 ]; then
        printf "  (none)\n"
    fi
}

resolve_config
validate_config

case "$MODE" in
    check)
        printf "Configuration is valid: %s\n" "$CONFIG_FILE"
        exit "$EXIT_OK"
        ;;
    list)
        list_sites
        exit "$EXIT_OK"
        ;;
esac

verify_macos_runtime
load_network_state

if [ "$MODE" = "diagnose" ]; then
    diagnose
    exit "$EXIT_OK"
fi

select_site
info "Selected site '$SELECTED_SITE' using SMB probe $SELECTED_PROBE:445."

if mount_selected_site; then
    exit "$EXIT_OK"
fi

exit "$EXIT_MOUNT"
