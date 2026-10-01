#!/usr/bin/env bash
# Shared source resolver for BE-IIS 10BASE-T1S driver builds.

S2500_SERIES_VERSION="v8"
S2500_BASE_COMMIT="014d795c73837ea2339a4ea8e8f82c6e959b845d"
S2500_SERIES_MSGID="20260928-s2500-mac-phy-support-v8-0-7e011aacc309@onsemi.com"

t1s_die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
t1s_warn() { printf 'WARNING: %s\n' "$*" >&2; }
t1s_note() { printf '%s\n' "$*"; }
t1s_require() { command -v "$1" >/dev/null 2>&1 || t1s_die "Required command not found: $1"; }

t1s_kernel_branch() {
    local kver="${1:-$(uname -r)}" major minor
    major="${kver%%.*}"
    minor="${kver#*.}"
    minor="${minor%%.*}"
    printf 'rpi-%s.%s.y\n' "$major" "$minor"
}

t1s_has_required_baseline() {
    local tree="$1"
    [[ -f "$tree/drivers/net/ethernet/oa_tc6/oa_tc6.c" ]] &&
    [[ -f "$tree/drivers/net/ethernet/oa_tc6/oa_tc6_tstamp.c" ]] &&
    [[ -f "$tree/drivers/net/ethernet/oa_tc6/oa_tc6_std_def.h" ]] &&
    grep -q 'oa_tc6_read_register_mms' "$tree/include/linux/oa_tc6.h"
}

t1s_has_target() {
    local tree="$1" target="$2"
    t1s_has_required_baseline "$tree" || return 1
    case "$target" in
        lan865x) [[ -f "$tree/drivers/net/ethernet/microchip/lan865x/lan865x.c" ]] ;;
        adin1140) [[ -f "$tree/drivers/net/ethernet/adi/adin1140.c" && -f "$tree/drivers/net/phy/adin1140-phy.c" ]] ;;
        s2500) [[ -f "$tree/drivers/net/ethernet/onsemi/s2500/s2500_main.c" ]] ;;
        *) return 1 ;;
    esac
}

t1s_prepare_upstream_v8() {
    local repo_root="$1"
    local tree="$repo_root/build/t1s-source/net-next-s2500-v8"
    t1s_require git
    t1s_require b4

    if [[ ! -d "$tree/.git" ]]; then
        mkdir -p "$(dirname "$tree")"
        git init -q "$tree"
        git -C "$tree" remote add origin "https://git.kernel.org/pub/scm/linux/kernel/git/netdev/net-next.git"
    fi

    if ! git -C "$tree" cat-file -e "${S2500_BASE_COMMIT}^{commit}" 2>/dev/null; then
        git -C "$tree" fetch --depth 1 origin "$S2500_BASE_COMMIT"
    fi

    git -C "$tree" reset --hard "$S2500_BASE_COMMIT" >/dev/null
    git -C "$tree" clean -fdx >/dev/null

    if ! t1s_has_target "$tree" s2500; then
        local out="$tree/.beiis-mbox" mbox
        rm -rf "$out"; mkdir -p "$out"
        (cd "$tree" && b4 am -o "$out" "$S2500_SERIES_MSGID")
        mbox="$(find "$out" -maxdepth 1 -type f \( -name '*.mbx' -o -name '*.mbox' \) | head -n1)"
        [[ -n "$mbox" ]] || t1s_die "b4 did not produce an S2500 patch mbox"
        git -C "$tree" am "$mbox" || {
            git -C "$tree" am --abort >/dev/null 2>&1 || true
            t1s_die "Could not apply S2500 v8 series"
        }
    fi

    t1s_has_target "$tree" s2500 || t1s_die "S2500 v8 feature set missing after patching"
    printf '%s\n' "$tree"
}

t1s_prepare_source() {
    local repo_root="$1" target="$2" kver="${3:-$(uname -r)}"
    local branch tree
    branch="$(t1s_kernel_branch "$kver")"
    tree="$repo_root/build/t1s-source/raspberrypi-$branch"

    if [[ ! -d "$tree/.git" ]]; then
        mkdir -p "$(dirname "$tree")"
        git clone --depth 1 --branch "$branch" "https://github.com/raspberrypi/linux.git" "$tree" || rm -rf "$tree"
    else
        git -C "$tree" fetch --depth 1 origin "$branch" >/dev/null
        git -C "$tree" reset --hard FETCH_HEAD >/dev/null
    fi

    if [[ -d "$tree/.git" ]] && t1s_has_target "$tree" "$target"; then
        t1s_note "Using Raspberry Pi $branch: required $target and S2500-generation OA-TC6 features are present." >&2
        printf '%s\n' "$tree"
        return
    fi

    t1s_warn "Raspberry Pi $branch lacks $target and/or the required S2500-generation OA-TC6 feature set."
    t1s_warn "Using S2500 v8 baseline $S2500_BASE_COMMIT plus the upstream v8 series."
    t1s_warn "This is a feature baseline, not a raw commit-number comparison, so newer compatible backports are accepted."
    t1s_prepare_upstream_v8 "$repo_root"
}
