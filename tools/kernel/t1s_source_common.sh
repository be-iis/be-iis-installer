#!/usr/bin/env bash
# Shared source helpers for BE-IIS 10BASE-T1S builds.

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

    if [[ -f "$tree/.beiis-ready" ]]; then
        printf '%s\n' "$tree"
        return
    fi

    rm -rf "$tree" "$work"
    mkdir -p "$tree" "$work"

    t1s_note "Downloading S2500 $S2500_SERIES_VERSION patch series (no kernel clone)." >&2
    if ! (cd "$work" && b4 am -o . "$S2500_SERIES_MSGID" >/dev/null); then
        t1s_die "b4 could not download the S2500 $S2500_SERIES_VERSION patch series"
    fi

    mbox="$(find "$work" -maxdepth 1 -type f \( -name '*.mbx' -o -name '*.mbox' \) | head -n1)"
    [[ -n "$mbox" ]] || t1s_die "b4 did not produce an S2500 patch mbox"

    base_url="https://raw.githubusercontent.com/torvalds/linux/$S2500_BASE_COMMIT"

    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        mkdir -p "$tree/$(dirname "$path")"
        if wget -q -O "$tree/$path.tmp" "$base_url/$path" 2>/dev/null; then
            mv "$tree/$path.tmp" "$tree/$path"
        else
            rm -f "$tree/$path.tmp"
        fi
    done < <(
        {
            grep -hE '^diff --git a/[^ ]+ b/[^ ]+' "$mbox" |
                sed -E 's#^diff --git a/([^ ]+) b/([^ ]+)$#\1\n\2#'
            grep -hE '^(---|\+\+\+) [ab]/' "$mbox" |
                sed -E 's#^(---|\+\+\+) [ab]/##'
        } |
        grep -v '^/dev/null$' |
        sort -u
    )

    git -C "$tree" init -q
    git -C "$tree" config user.name "BE-IIS T1S build"
    git -C "$tree" config user.email "build@localhost"
    git -C "$tree" add -A
    git -C "$tree" commit -q --allow-empty -m "minimal S2500 base snapshot"

    if ! git -C "$tree" am "$mbox" >/dev/null; then
        git -C "$tree" am --abort >/dev/null 2>&1 || true
        t1s_die "Could not apply S2500 $S2500_SERIES_VERSION series"
    fi

    touch "$tree/.beiis-ready"
    printf '%s\n' "$tree"
}

t1s_find_kernel_header() {
    local kdir="$1" kver="$2" header="$3"
    local direct="$kdir/include/linux/$header"
    local rpi_common="/usr/src/linux-headers-${kver%%-rpi-*}-common-rpi/include/linux/$header"

    if [[ -f "$direct" ]]; then
        printf '%s\n' "$direct"
        return 0
    fi

    if [[ -f "$rpi_common" ]]; then
        printf '%s\n' "$rpi_common"
        return 0
    fi

    return 1
}

t1s_native_tc6_is_usable() {
    local kdir="$1" kver="$2"
    local header symvers symbol
    local required_symbols=(
        oa_tc6_init
        oa_tc6_exit
        oa_tc6_write_register
        oa_tc6_write_register_mms
        oa_tc6_read_register
        oa_tc6_read_register_mms
        oa_tc6_start_xmit
        oa_tc6_zero_align_receive_frame_enable
        oa_tc6_mdiobus_read_c45
        oa_tc6_mdiobus_write_c45
    )

    header="$(t1s_find_kernel_header "$kdir" "$kver" oa_tc6.h)" || return 1
    symvers="$kdir/Module.symvers"
    [[ -f "$symvers" ]] || return 1

    # Require the modern OA-TC6 API used by the pinned vendor drivers.
    grep -q 'OA_TC6_BROKEN_PHY' "$header" || return 1
    grep -q 'struct oa_tc6_quirks' "$header" || return 1
    grep -q 'oa_tc6_write_register_mms' "$header" || return 1
    grep -q 'oa_tc6_read_register_mms' "$header" || return 1

    for symbol in "${required_symbols[@]}"; do
        grep -Eq "[[:space:]]$symbol[[:space:]]" "$symvers" || return 1
    done

    return 0
}

t1s_ensure_tc6_build() {
    local repo_root="$1"
    local build="$repo_root/build/oa_tc6"
    local kver
    kver="$(uname -r)"

    if [[ ! -f "$build/.kernel-release" ||
          "$(cat "$build/.kernel-release" 2>/dev/null || true)" != "$kver" ||
          ! -f "$build/include/linux/oa_tc6.h" ||
          ( ! -f "$build/.native" && ! -f "$build/.external" ) ]]; then
        bash "$repo_root/tools/kernel/oa_tc6_mod_build.sh"
    fi

    [[ -f "$build/include/linux/oa_tc6.h" ]] || t1s_die "OA-TC6 header missing"

    if [[ -f "$build/.external" ]]; then
        [[ -f "$build/oa_tc6.ko" ]] || t1s_die "oa_tc6.ko missing after OA-TC6 backport build"
        [[ -f "$build/Module.symvers" ]] || t1s_die "OA-TC6 backport Module.symvers missing"
    elif [[ ! -f "$build/.native" ]]; then
        t1s_die "OA-TC6 mode marker missing"
    fi
}

t1s_fetch_upstream_file() {
    local commit="$1" path="$2" dst="$3"
    t1s_fetch "https://raw.githubusercontent.com/torvalds/linux/$commit/$path" "$dst"
}
