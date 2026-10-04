#!/usr/bin/env bash
# Shared source resolver for BE-IIS 10BASE-T1S driver builds.
#
# Important: this helper never clones a Linux kernel tree.  It downloads only
# the source files required for the selected T1S driver.  If Raspberry Pi's
# matching kernel branch does not contain the S2500-generation OA-TC6 API, the
# upstream S2500 patch series is downloaded with b4 and applied to a tiny local
# snapshot containing only files touched by that series.

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

t1s_fetch() {
    local url="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    wget -q -O "$dst.tmp" "$url" || {
        rm -f "$dst.tmp"
        return 1
    }
    mv "$dst.tmp" "$dst"
}

t1s_common_files() {
    cat <<'EOF'
include/linux/oa_tc6.h
drivers/net/ethernet/oa_tc6/oa_tc6.c
drivers/net/ethernet/oa_tc6/oa_tc6_tstamp.c
drivers/net/ethernet/oa_tc6/oa_tc6_std_def.h
EOF
}

t1s_target_files() {
    case "$1" in
        lan865x)
            cat <<'EOF'
drivers/net/ethernet/microchip/lan865x/lan865x.c
drivers/net/phy/microchip_t1s.c
EOF
            ;;
        adin1140)
            cat <<'EOF'
drivers/net/ethernet/adi/adin1140.c
drivers/net/phy/adin1140-phy.c
EOF
            ;;
        s2500)
            cat <<'EOF'
drivers/net/ethernet/onsemi/s2500/s2500_main.c
drivers/net/ethernet/onsemi/s2500/s2500_ethtool.c
drivers/net/ethernet/onsemi/s2500/s2500_ptp.c
drivers/net/ethernet/onsemi/s2500/s2500_hw_def.h
drivers/net/phy/ncn26000.c
drivers/net/ethernet/oa_tc6/oa_tc6_ptp.c
EOF
            ;;
        *)
            return 1
            ;;
    esac
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
        lan865x)
            [[ -f "$tree/drivers/net/ethernet/microchip/lan865x/lan865x.c" &&
               -f "$tree/drivers/net/phy/microchip_t1s.c" ]]
            ;;
        adin1140)
            [[ -f "$tree/drivers/net/ethernet/adi/adin1140.c" &&
               -f "$tree/drivers/net/phy/adin1140-phy.c" ]]
            ;;
        s2500)
            [[ -f "$tree/drivers/net/ethernet/onsemi/s2500/s2500_main.c" &&
               -f "$tree/drivers/net/phy/ncn26000.c" ]]
            ;;
        *)
            return 1
            ;;
    esac
}

t1s_prepare_rpi_files() {
    local repo_root="$1" target="$2" branch="$3"
    local tree="$repo_root/build/t1s-source/raspberrypi-$branch-$target"
    local base="https://raw.githubusercontent.com/raspberrypi/linux/refs/heads/$branch"
    local path

    rm -rf "$tree"
    mkdir -p "$tree"

    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        t1s_fetch "$base/$path" "$tree/$path" || {
            rm -rf "$tree"
            return 1
        }
    done < <({ t1s_common_files; t1s_target_files "$target"; } | awk '!seen[$0]++')

    t1s_has_target "$tree" "$target" || {
        rm -rf "$tree"
        return 1
    }

    printf '%s\n' "$tree"
}

t1s_prepare_upstream_v8() {
    local repo_root="$1"
    local tree="$repo_root/build/t1s-source/net-next-s2500-v8-minimal"
    local work="$repo_root/build/t1s-source/.s2500-v8"
    local mbox path base_url

    t1s_require git
    t1s_require b4
    t1s_require wget

    rm -rf "$tree" "$work"
    mkdir -p "$tree" "$work"

    t1s_note "Downloading S2500 $S2500_SERIES_VERSION patch series (no kernel clone)." >&2
    (cd "$work" && b4 am -o . "$S2500_SERIES_MSGID" >/dev/null)
    mbox="$(find "$work" -maxdepth 1 -type f \( -name '*.mbx' -o -name '*.mbox' \) | head -n1)"
    [[ -n "$mbox" ]] || t1s_die "b4 did not produce an S2500 patch mbox"

    # Download only pre-existing files touched by the series. Files newly added
    # by the patches intentionally return 404 and are created by git am.
    base_url="https://git.kernel.org/pub/scm/linux/kernel/git/netdev/net-next.git/plain"
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        mkdir -p "$tree/$(dirname "$path")"
        wget -q -O "$tree/$path.tmp" "$base_url/$path?id=$S2500_BASE_COMMIT" 2>/dev/null || {
            rm -f "$tree/$path.tmp"
            continue
        }
        mv "$tree/$path.tmp" "$tree/$path"
    done < <(
        grep -hE '^(---|\+\+\+) [ab]/' "$mbox" |
        sed -E 's#^(---|\+\+\+) [ab]/##' |
        grep -v '^/dev/null$' |
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

    t1s_has_target "$tree" s2500 ||
        t1s_die "S2500 $S2500_SERIES_VERSION feature set missing after patching"

    printf '%s\n' "$tree"
}

t1s_prepare_source() {
    local repo_root="$1" target="$2" kver="${3:-$(uname -r)}"
    local branch tree

    t1s_require wget
    branch="$(t1s_kernel_branch "$kver")"

    if tree="$(t1s_prepare_rpi_files "$repo_root" "$target" "$branch")"; then
        t1s_note "Using only the required files from Raspberry Pi $branch." >&2
        printf '%s\n' "$tree"
        return
    fi

    t1s_warn "Raspberry Pi $branch lacks $target and/or the S2500-generation OA-TC6 feature set."
    t1s_warn "Fetching only the files touched by the upstream S2500 $S2500_SERIES_VERSION series."
    t1s_warn "No complete Raspberry Pi or Linux kernel tree will be cloned."

    tree="$(t1s_prepare_upstream_v8 "$repo_root")"

    # The S2500 series contains the common OA-TC6 baseline. ADIN1140 and
    # LAN865x may already be present at the selected base; if not, fetch just
    # their driver files from current upstream.
    if ! t1s_has_target "$tree" "$target"; then
        local raw="https://raw.githubusercontent.com/torvalds/linux/master" path
        while IFS= read -r path; do
            [[ -n "$path" ]] || continue
            [[ -f "$tree/$path" ]] && continue
            t1s_fetch "$raw/$path" "$tree/$path" ||
                t1s_die "Required upstream source not found: $path"
        done < <(t1s_target_files "$target")
    fi

    t1s_has_target "$tree" "$target" ||
        t1s_die "Required $target source set is incomplete"

    printf '%s\n' "$tree"
}
