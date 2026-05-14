#!/bin/bash
#
# check-mas-clean.sh
#
# Static check that scans the Swift sources for private-API references
# that would cause an App Store rejection if they leaked into the MAS
# bundle. Every match must be inside a `#if !APP_STORE_SANDBOX` block
# OR inside `Docky/Private/` (the whole directory is gated already).
#
# Fail loudly on a new ungated site so we catch leaks at PR time
# instead of at App Review time.
#
# Usage:
#   scripts/check-mas-clean.sh
#
# Hook into a pre-commit or CI step before submitting the MAS build.
#

set -euo pipefail

cd "$(dirname "$0")/.."

failed=0

#
# Each rule scans a pattern, then re-greps the matched lines for
# `#if` markers in the surrounding context. The conservative version
# below greps a 5-line window around each hit and looks for the gate.
#
check_pattern() {
    local label="$1"
    local pattern="$2"
    local exclude_dirs="${3:-^Docky/Private/}"

    local matches
    matches=$(grep -rn -E "$pattern" Docky --include="*.swift" 2>/dev/null \
        | grep -v -E "$exclude_dirs" || true)

    if [ -z "$matches" ]; then
        echo "  [OK] $label"
        return 0
    fi

    # For each match, look 5 lines above for #if !APP_STORE_SANDBOX
    # gate (or `#if APP_STORE_SANDBOX` with an #else that omits it).
    # Conservative: any match WITHOUT a gating directive in its
    # nearby context is flagged.
    while IFS= read -r line; do
        local file
        file=$(echo "$line" | cut -d: -f1)
        local lineno
        lineno=$(echo "$line" | cut -d: -f2)
        local start=$((lineno - 30))
        if [ $start -lt 1 ]; then start=1; fi

        # Grep a 30-line window above the match for any
        # APP_STORE_SANDBOX directive. Conservative enough to catch
        # most #if/#else/#endif spans authored in this codebase;
        # if a future contributor writes a very long branch and the
        # heuristic misses it, the check fails noisily and the gate
        # needs to be reviewed.
        if ! sed -n "${start},${lineno}p" "$file" | grep -q "APP_STORE_SANDBOX"; then
            echo "  [LEAK] $line"
            failed=1
        fi
    done <<< "$matches"
}

echo "Scanning for ungated private-API surface…"
echo

check_pattern \
    "Private framework path strings" \
    '"/System/Library/PrivateFrameworks'

check_pattern \
    "dlopen / dlsym (typically loading private frameworks)" \
    '\b(dlopen|dlsym)\('

check_pattern \
    "NSClassFromString for known-private classes (NSGlassEffectView, CABackdropLayer, CAFilter)" \
    'NSClassFromString\("(NSGlassEffectView|CABackdropLayer|CAFilter)"'

check_pattern \
    "Subprocess launches to /usr/bin/* (sandbox blocks Process to absolute paths)" \
    'executableURL.*=.*URL\(fileURLWithPath: "/usr/bin/'

check_pattern \
    "launchPath = /usr/bin (legacy Process API)" \
    'launchPath.*=.*"/usr/bin/'

check_pattern \
    "CGS / SkyLight @_silgen_name bindings (entire Private/ dir is already gated)" \
    '@_silgen_name\("(CGS|_SLPS|SLPS|_AXUIElementGetWindow|CGWindowListCreateImage)' \
    '^Docky/Private/'

check_pattern \
    "CFPreferencesSetAppValue to com.apple.dock (sandbox cannot write other apps' prefs)" \
    'CFPreferencesSetAppValue.*"com\.apple\.dock"'

check_pattern \
    "forceTerminate on system processes" \
    '\.forceTerminate\(\)'

echo
if [ $failed -ne 0 ]; then
    echo "FAILED: ungated private-API site(s) above. Wrap each in"
    echo "  #if !APP_STORE_SANDBOX … #endif"
    echo "or move the call into the helper bundle (DockyHelper/)."
    exit 1
fi

echo "OK: no ungated private-API surface detected in MAS build path."
