#!/bin/sh

set -u
set -f

TESTS_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P)
PROJECT_DIR=$(CDPATH='' cd -- "$TESTS_DIR/.." 2>/dev/null && pwd -P)
SCRIPT="$PROJECT_DIR/ConnectServers.sh"
ORIGINAL_PATH=$PATH
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/connectservers-tests.XXXXXX")
STUB_BIN="$TEST_ROOT/bin"
CONFIG_FILE="$TEST_ROOT/sites.conf"
MOUNT_FILE="$TEST_ROOT/mounts.txt"
MOUNT_CALLS="$TEST_ROOT/mount-calls.txt"
RUN_OUTPUT=""
RUN_STATUS=0
PASSED=0
FAILED=0

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup 0 HUP INT TERM

mkdir -p "$STUB_BIN"

cat > "$STUB_BIN/uname" <<'EOF'
#!/bin/sh
printf "Darwin\n"
EOF

cat > "$STUB_BIN/scutil" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "--dns" ]; then
    index=0
    old_ifs=$IFS
    IFS=","
    set -- ${TEST_DNS_DOMAINS:-}
    IFS=$old_ifs
    for domain do
        printf "  search domain[%s] : %s\n" "$index" "$domain"
        index=$((index + 1))
    done
    exit 0
fi

if [ "${1:-}" = "--get" ] && [ "${2:-}" = "ComputerName" ]; then
    printf "%s\n" "${TEST_COMPUTER_NAME:-Test Mac}"
    exit 0
fi

exit 1
EOF

cat > "$STUB_BIN/nc" <<'EOF'
#!/bin/sh
previous=""
host=""
for argument do
    if [ "$argument" = "445" ]; then
        host=$previous
        break
    fi
    previous=$argument
done

case ",${TEST_REACHABLE_HOSTS:-}," in
    *,"$host",*) exit 0 ;;
    *) exit 1 ;;
esac
EOF

cat > "$STUB_BIN/mount" <<'EOF'
#!/bin/sh
if [ -f "${TEST_MOUNT_FILE:-}" ]; then
    cat "$TEST_MOUNT_FILE"
fi
EOF

cat > "$STUB_BIN/osascript" <<'EOF'
#!/bin/sh
last_argument=""
for argument do
    last_argument=$argument
done

printf "%s\n" "$last_argument" >> "$TEST_MOUNT_CALLS"

case "$last_argument" in
    *"${TEST_FAIL_SHARE:-__never__}"*)
        printf "simulated Finder mount failure\n" >&2
        exit 1
        ;;
esac

exit 0
EOF

chmod 755 "$STUB_BIN/uname" "$STUB_BIN/scutil" "$STUB_BIN/nc" \
    "$STUB_BIN/mount" "$STUB_BIN/osascript"

export CONNECTSERVERS_PATH="$STUB_BIN:$ORIGINAL_PATH"
export CONNECTSERVERS_CONFIG="$CONFIG_FILE"
export TEST_MOUNT_FILE="$MOUNT_FILE"
export TEST_MOUNT_CALLS="$MOUNT_CALLS"
export USER="testuser"

reset_state() {
    : > "$MOUNT_FILE"
    : > "$MOUNT_CALLS"
    TEST_DNS_DOMAINS=""
    TEST_REACHABLE_HOSTS=""
    TEST_FAIL_SHARE="__never__"
    export TEST_DNS_DOMAINS TEST_REACHABLE_HOSTS TEST_FAIL_SHARE
}

write_config() {
    printf "%s\n" "$1" > "$CONFIG_FILE"
}

run_script() {
    RUN_OUTPUT=$("$SCRIPT" "$@" 2>&1)
    RUN_STATUS=$?
}

fail_assertion() {
    printf "    %s\n" "$1" >&2
    return 1
}

assert_status() {
    if [ "$RUN_STATUS" -ne "$1" ]; then
        fail_assertion "Expected status $1, got $RUN_STATUS. Output: $RUN_OUTPUT"
        return 1
    fi
}

assert_contains() {
    case "$RUN_OUTPUT" in
        *"$1"*) return 0 ;;
        *)
            fail_assertion "Expected output to contain '$1'. Output: $RUN_OUTPUT"
            return 1
            ;;
    esac
}

assert_mount_call_count() {
    actual=$(wc -l < "$MOUNT_CALLS" | tr -d "[:space:]")
    if [ "$actual" != "$1" ]; then
        fail_assertion "Expected $1 mount call(s), got $actual."
        return 1
    fi
}

test_help_without_configuration() {
    run_script --help
    assert_status 0 || return 1
    assert_contains "Usage:" || return 1
}

test_valid_configuration() {
    reset_state
    write_config "atl|atl.example.com|atlfs01|smb://{user}@atlfs01/shared"
    run_script --check-config
    assert_status 0 || return 1
    assert_contains "Configuration is valid" || return 1
}

test_automatic_site_selection_and_mounts() {
    reset_state
    write_config "atl|atl.example.com|atlfs01|smb://{user}@atlfs01/users/{user};smb://{user}@atlfs01/shared
den|den.example.com|denfs01|smb://{user}@denfs01/shared"
    TEST_DNS_DOMAINS="vpn.atl.example.com"
    TEST_REACHABLE_HOSTS="atlfs01"
    export TEST_DNS_DOMAINS TEST_REACHABLE_HOSTS

    run_script --verbose
    assert_status 0 || return 1
    assert_contains "Selected site 'atl'" || return 1
    assert_contains "2 mounted, 0 already mounted, 0 failed" || return 1
    assert_mount_call_count 2 || return 1
}

test_existing_mounts_are_idempotent() {
    reset_state
    write_config "atl|*|atlfs01|smb://{user}@atlfs01/users/{user};smb://{user}@atlfs01/shared"
    TEST_REACHABLE_HOSTS="atlfs01"
    export TEST_REACHABLE_HOSTS
    printf "%s\n" \
        "//testuser@atlfs01/users on /Volumes/users (smbfs, nodev)" \
        "//testuser@atlfs01/shared on /Volumes/shared (smbfs, nodev)" > "$MOUNT_FILE"

    run_script
    assert_status 0 || return 1
    assert_contains "0 mounted, 2 already mounted, 0 failed" || return 1
    assert_mount_call_count 0 || return 1
}

test_explicit_site_bypasses_dns_only() {
    reset_state
    write_config "den|den.example.com|denfs01|smb://{user}@denfs01/shared"
    TEST_DNS_DOMAINS="atl.example.com"
    TEST_REACHABLE_HOSTS="denfs01"
    export TEST_DNS_DOMAINS TEST_REACHABLE_HOSTS

    run_script --site den --dry-run
    assert_status 0 || return 1
    assert_contains "Selected site 'den'" || return 1
    assert_contains "Would mount: smb://denfs01/shared" || return 1
    assert_mount_call_count 0 || return 1
}

test_no_reachable_site_returns_location_error() {
    reset_state
    write_config "atl|atl.example.com|atlfs01|smb://{user}@atlfs01/shared"
    TEST_DNS_DOMAINS="atl.example.com"
    export TEST_DNS_DOMAINS

    run_script
    assert_status 4 || return 1
    assert_contains "No configured site matches" || return 1
    assert_mount_call_count 0 || return 1
}

test_ambiguous_sites_are_rejected() {
    reset_state
    write_config "atl|*|atlfs01|smb://{user}@atlfs01/shared
den|*|denfs01|smb://{user}@denfs01/shared"
    TEST_REACHABLE_HOSTS="atlfs01,denfs01"
    export TEST_REACHABLE_HOSTS

    run_script
    assert_status 4 || return 1
    assert_contains "Multiple sites match" || return 1
    assert_mount_call_count 0 || return 1
}

test_password_in_url_is_rejected() {
    reset_state
    write_config "atl|*|atlfs01|smb://testuser:secret@atlfs01/shared"

    run_script --check-config
    assert_status 2 || return 1
    assert_contains "appears to contain a password" || return 1
}

test_partial_mount_failure_returns_mount_error() {
    reset_state
    write_config "atl|*|atlfs01|smb://{user}@atlfs01/users/{user};smb://{user}@atlfs01/shared"
    TEST_REACHABLE_HOSTS="atlfs01"
    TEST_FAIL_SHARE="/shared"
    export TEST_REACHABLE_HOSTS TEST_FAIL_SHARE

    run_script --verbose
    assert_status 5 || return 1
    assert_contains "1 mounted, 0 already mounted, 1 failed" || return 1
    assert_contains "simulated Finder mount failure" || return 1
    assert_mount_call_count 2 || return 1
}

test_diagnostics_do_not_mount() {
    reset_state
    write_config "atl|atl.example.com|atlfs01|smb://{user}@atlfs01/shared"
    TEST_DNS_DOMAINS="atl.example.com"
    TEST_REACHABLE_HOSTS="atlfs01"
    export TEST_DNS_DOMAINS TEST_REACHABLE_HOSTS

    run_script --diagnose
    assert_status 0 || return 1
    assert_contains "ConnectServers diagnostics" || return 1
    assert_contains "atl" || return 1
    assert_contains "yes" || return 1
    assert_mount_call_count 0 || return 1
}

run_test() {
    test_name=$1
    test_function=$2
    printf "TEST %s\n" "$test_name"
    if "$test_function"; then
        PASSED=$((PASSED + 1))
        printf "  PASS\n"
    else
        FAILED=$((FAILED + 1))
        printf "  FAIL\n"
    fi
}

run_test "help does not require configuration" test_help_without_configuration
run_test "valid configuration is accepted" test_valid_configuration
run_test "automatic selection mounts the matching site" test_automatic_site_selection_and_mounts
run_test "existing mounts are skipped" test_existing_mounts_are_idempotent
run_test "explicit site bypasses DNS but checks SMB" test_explicit_site_bypasses_dns_only
run_test "no reachable site returns status 4" test_no_reachable_site_returns_location_error
run_test "ambiguous sites are rejected" test_ambiguous_sites_are_rejected
run_test "password-bearing URLs are rejected" test_password_in_url_is_rejected
run_test "partial failure returns status 5" test_partial_mount_failure_returns_mount_error
run_test "diagnostics do not mount" test_diagnostics_do_not_mount

printf "\nRESULT: %s passed, %s failed\n" "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
