#!/usr/bin/env bash
# Shared source helpers for BE-IIS 10BASE-T1S builds.
#
# One canonical OA-TC6 source/binary set is used by all T1S MAC-PHY drivers.
# Vendor drivers build against the same local oa_tc6.h and Module.symvers.
# No complete Linux kernel tree is cloned.

ADIN1140_BASE_COMMIT="20e69e671070ab0b712b34a0e8977e8a402aa5eb"
S2500_SERIES_VERSION="v8"
S2500_BASE_COMMIT="014d795c73837ea2339a4ea8e8f82c6e959b845d"
S2500_SERIES_MSGID="20260928-s2500-mac-phy-support-v8-0-7e011aacc309@onsemi.com"

t1s_die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
t1s_warn() { printf 'WARNING: %s\n' "$*" >&2; }
t1s_note() { printf '%s\n' "$*"; }
t1s_require() { command -v "$1" >/dev/null 2>&1 || t1s_die "Required command not found: $1"; }

t1s_fetch() {
    local url="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    wget -q -O "$dst.tmp" "$url" || {
        rm -f "$dst.tmp"
        return 1
    }
    mv "$dst.tmp" "$dst"
}

t1s_prepare_s2500_v8_minimal() {
    local repo_root="$1"
    local tree="$repo_root/build/t1s-source/s2500-v8-minimal"
    local work="$repo_root/build/t1s-source/.s2500-v8"
    local mbox path base_url

    t1s_require git
    t1s_require b4
    t1s_require wget

    rm -rf "$tree" "$work"
    mkdir -p "$tree" "$work"

    t1s_note "Downloading S2500 $S2500_SERIES_VERSION patch series (no kernel clone)." >&2
    if ! (cd "$work" && b4 am -o . "$S2500_SERIES_MSGID" >/dev/null); then
        t1s_die "b4 could not download the S2500 $S2500_SERIES_VERSION patch series"
    fi

    mbox="$(find "$work" -maxdepth 1 -type f \( -name '*.mbx' -o -name '*.mbox' \) | head -n1)"
    [[ -n "$mbox" ]] || t1s_die "b4 did not produce an S2500 patch mbox"

    base_url="https://raw.githubusercontent.com/torvalds/linux/$S2500_BASE_COMMIT"

    # Seed the minimal git tree with every *existing* file touched by the
    # series. Parse diff headers as well as ---/+++ because pure renames do not
    # necessarily carry normal patch file markers.
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        mkdir -p "$tree/$(dirname "$path")"
        if wget -q -O "$tree/$path.tmp" "$base_url/$path" 2>/dev/null; then
            mv "$tree/$path.tmp" "$tree/$path"
        else
            # New files in the series do not exist at the base commit.
            rm -f "$tree/$path.tmp"
        fi
    done < <(
        {
            grep -hE '^diff --git a/[^ ]+ b/[^ ]+' "$mbox" |
                sed -E 's#^diff --git a/([^ ]+) b/([^ ]+)$#\1\n\2#'
            grep -hE '^(---|\+\+\+) [ab]/' "$mbox" |
                sed -E 's#^(---|\+\+\+) [ab]/##'
        } |
        grep -v '^/dev/null
    git -C "$tree" init -q
    git -C "$tree" config user.name "BE-IIS T1S build"
    git -C "$tree" config user.email "build@localhost"
    git -C "$tree" add -A
    git -C "$tree" commit -q --allow-empty -m "minimal S2500 base snapshot"

    git -C "$tree" am "$mbox" >/dev/null || {
        git -C "$tree" am --abort >/dev/null 2>&1 || true
        t1s_die "Could not apply S2500 $S2500_SERIES_VERSION series"
    }

    printf '%s\n' "$tree"
}

t1s_ensure_tc6_build() {
    local repo_root="$1"
    local build="$repo_root/build/oa_tc6"

    if [[ ! -f "$build/oa_tc6.ko" || ! -f "$build/Module.symvers" || ! -f "$build/include/linux/oa_tc6.h" ]]; then
        bash "$repo_root/tools/kernel/oa_tc6_mod_build.sh"
    fi

    [[ -f "$build/oa_tc6.ko" ]] || t1s_die "oa_tc6.ko missing after OA-TC6 build"
    [[ -f "$build/Module.symvers" ]] || t1s_die "OA-TC6 Module.symvers missing"
    [[ -f "$build/include/linux/oa_tc6.h" ]] || t1s_die "OA-TC6 header missing"
}

t1s_fetch_upstream_file() {
    local commit="$1" path="$2" dst="$3"
    t1s_fetch "https://raw.githubusercontent.com/torvalds/linux/$commit/$path" "$dst"
}
 |
        sort -u
    )

    git -C "$tree" init -q
    git -C "$tree" config user.name "BE-IIS T1S build"
    git -C "$tree" config user.email "build@localhost"
    git -C "$tree" add -A
    git -C "$tree" commit -q --allow-empty -m "minimal S2500 base snapshot"

    git -C "$tree" am "$mbox" >/dev/null || {
        git -C "$tree" am --abort >/dev/null 2>&1 || true
        t1s_die "Could not apply S2500 $S2500_SERIES_VERSION series"
    }

    printf '%s\n' "$tree"
}

t1s_ensure_tc6_build() {
    local repo_root="$1"
    local build="$repo_root/build/oa_tc6"

    if [[ ! -f "$build/oa_tc6.ko" || ! -f "$build/Module.symvers" || ! -f "$build/include/linux/oa_tc6.h" ]]; then
        "$repo_root/tools/kernel/oa_tc6_mod_build.sh"
    fi

    [[ -f "$build/oa_tc6.ko" ]] || t1s_die "oa_tc6.ko missing after OA-TC6 build"
    [[ -f "$build/Module.symvers" ]] || t1s_die "OA-TC6 Module.symvers missing"
    [[ -f "$build/include/linux/oa_tc6.h" ]] || t1s_die "OA-TC6 header missing"
}

t1s_fetch_upstream_file() {
    local commit="$1" path="$2" dst="$3"
    t1s_fetch "https://raw.githubusercontent.com/torvalds/linux/$commit/$path" "$dst"
}
