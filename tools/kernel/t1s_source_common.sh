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

# Keep a small, per-driver provenance record next to the downloaded sources.
# The unified build report must say exactly which baseline was selected; a
# successful compilation alone does not make a backport's origin obvious.
t1s_source_record() {
    local repo_root="$1" target="$2" baseline="$3" detail="$4"
    local record="$repo_root/build/t1s-source/source-${target}.env"
    mkdir -p "$(dirname "$record")"
    {
        printf 'TARGET=%q\n' "$target"
        printf 'BASELINE=%q\n' "$baseline"
        printf 'DETAIL=%q\n' "$detail"
    } > "$record"
}

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
    wget -q --timeout=15 --tries=2 -O "$dst.tmp" "$url" || {
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

# Prefer the complete Linux 7.2 driver API for older Raspberry Pi kernels.
# Download only the files required by the requested MAC-PHY/PHY.
t1s_prepare_upstream_72() {
    local repo_root="$1" target="$2"
    local tree="$repo_root/build/t1s-source/linux-v7.2-$target"
    local base="https://raw.githubusercontent.com/torvalds/linux/v7.2"
    local path
    if t1s_has_target "$tree" "$target"; then
        printf '%s\n' "$tree"
        return 0
    fi
    rm -rf "$tree"
    mkdir -p "$tree"
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        if ! t1s_fetch "$base/$path" "$tree/$path"; then
            t1s_warn "Linux 7.2 does not provide $path for $target"
            rm -rf "$tree"
            return 1
        fi
    done < <({ t1s_common_files; t1s_target_files "$target"; } | awk '!seen[$0]++')
    t1s_has_target "$tree" "$target" || return 1
    printf '%s\n' "$tree"
}

t1s_prepare_upstream_v8() {
    local repo_root="$1" target="${2:-s2500}"
    local tree="$repo_root/build/t1s-source/net-next-s2500-v8-$target"
    local work="$repo_root/build/t1s-source/.s2500-v8-$target"
    local mbox path base_url

    t1s_require git
    t1s_require b4
    t1s_require wget

    if [[ -f "$tree/.beiis-s2500-v8-ready" ]] && t1s_has_target "$tree" s2500; then
        t1s_note "Reusing prepared S2500 v8 source tree: $tree" >&2
        printf '%s\n' "$tree"
        return 0
    fi
    # Recreate the patch checkout; keep the separate download cache in $work.
    rm -rf "$tree"
    mkdir -p "$tree" "$work"

    t1s_note "Downloading S2500 $S2500_SERIES_VERSION patch series (no kernel clone)." >&2
    # Independent b4 caches prevent concurrent product builds from modifying
    # the same message cache entries. Keep them in the product-specific workdir.
    mkdir -p "$work/cache"
    if ! find "$work" -maxdepth 1 -type f \( -name '*.mbx' -o -name '*.mbox' \) | grep -q .; then
        (cd "$work" && XDG_CACHE_HOME="$work/cache" b4 am -o . "$S2500_SERIES_MSGID" >/dev/null) || { t1s_warn "Could not download S2500 patch series"; return 1; }
    else
        t1s_note "Reusing downloaded S2500 patch series" >&2
    fi
    mbox="$(find "$work" -maxdepth 1 -type f \( -name '*.mbx' -o -name '*.mbox' \) | head -n1)"
    [[ -n "$mbox" ]] || t1s_die "b4 did not produce an S2500 patch mbox"

    # Apply the series on its declared net-next base, not an unrelated
    # moving kernel branch. Include both sides of renames (diff --git), not
    # only ---/+++ markers. Missing OLD files are fatal: silently skipping
    # them makes git am fail with misleading "does not exist in index".
    local old_paths all_paths
    old_paths="$work/old-paths.txt"
    all_paths="$work/all-paths.txt"
    # Parse each diff in order. A path added by an earlier patch is NOT a
    # file from the base commit (e.g. oa_tc6/Kconfig in patch 3).
    # Pure renames must still fetch their original path (oa_tc6.c).
    python3 - "$mbox" "$old_paths" "$all_paths" <<'PY'
import re
import sys
from pathlib import Path

mbox, old_out, all_out = map(Path, sys.argv[1:])
lines = mbox.read_text(errors="replace").splitlines()
created = set()
needed = set()
touched = set()
for idx, line in enumerate(lines):
    match = re.match(r"diff --git a/(.+) b/(.+)$", line)
    if not match:
        continue
    old, new = match.groups()
    j = idx + 1
    metadata = []
    while j < len(lines) and not lines[j].startswith("diff --git ") and not lines[j].startswith("From "):
        metadata.append(lines[j])
        j += 1
    new_file = any(x.startswith("new file mode ") or x == "--- /dev/null" for x in metadata)
    rename_from = next((x[len("rename from "):] for x in metadata if x.startswith("rename from ")), None)
    source = rename_from or old
    if not new_file and source not in created:
        needed.add(source)
    if new_file or rename_from:
        created.add(new)
    touched.add(source)
    touched.add(new)
old_out.write_text("\n".join(sorted(needed)) + "\n")
# Fetch only known-to-exist base paths, never paths newly created by patches.
all_out.write_text("\n".join(sorted(needed)) + "\n")
PY

    base_url="https://kernel.googlesource.com/pub/scm/linux/kernel/git/netdev/net-next/+/$S2500_BASE_COMMIT"
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        mkdir -p "$tree/$(dirname "$path")"
        if [[ -s "$work/base-files/$path" ]]; then
            cp "$work/base-files/$path" "$tree/$path"
            continue
        fi
        if ! wget -q --timeout=15 --tries=4 --waitretry=2 -O "$tree/$path.tmp" "$base_url/$path?format=TEXT"; then
            rm -f "$tree/$path.tmp"
            # New paths need not exist on the base; old paths MUST exist
            # unless created earlier in the same patch series.
            if grep -Fxq "$path" "$old_paths"; then
                t1s_warn "Cannot fetch pinned net-next base file: $path ($S2500_BASE_COMMIT)"
                t1s_warn "Cannot safely apply the patch series to an incomplete base."
                return 1
            fi
            continue
        fi
        if ! base64 -d "$tree/$path.tmp" > "$tree/$path"; then
            t1s_warn "Invalid base64 response for $path"; return 1
        fi
        rm -f "$tree/$path.tmp"
        mkdir -p "$work/base-files/$(dirname "$path")"
        cp "$tree/$path" "$work/base-files/$path"
    done < "$all_paths"

    rm -rf "$tree/.git"
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
    touch "$tree/.beiis-s2500-v8-ready"

    printf '%s\n' "$tree"
}

t1s_prepare_source() {
    local repo_root="$1" target="$2" kver="${3:-$(uname -r)}"
    local branch tree

    t1s_require wget
    # Prefer sources from the *running kernel* rather than an independently
    # moving Raspberry Pi branch. /source may be a symlink to a full tree.
    local local_src
    for local_src in "/lib/modules/$kver/source" "/lib/modules/$kver/build"; do
        if [[ -d "$local_src" ]] && t1s_has_target "$local_src" "$target"; then
            t1s_note "Using local sources for running kernel $kver: $local_src" >&2
            t1s_source_record "$repo_root" "$target" "running-kernel" "$kver ($local_src)"
            printf '%s\n' "$local_src"
            return 0
        fi
    done
    branch="$(t1s_kernel_branch "$kver")"

    # Use Linux 7.2 when the running kernel does not have this T1S stack.
    # S2500 arrived later: its validated v8 series remains the fallback.
    if tree="$(t1s_prepare_upstream_72 "$repo_root" "$target")"; then
        t1s_note "Using upstream Linux v7.2 $target sources." >&2
        t1s_source_record "$repo_root" "$target" "Linux v7.2" "complete $target source set"
        printf '%s\n' "$tree"
        return 0
    fi

    t1s_warn "Linux v7.2 lacks the complete $target source set."
    t1s_warn "Falling back to the later upstream S2500 $S2500_SERIES_VERSION patch series."
    t1s_warn "No complete Raspberry Pi or Linux kernel tree will be cloned."

    tree="$(t1s_prepare_upstream_v8 "$repo_root" "$target")" || {
        t1s_warn "S2500 upstream backport source preparation failed; no source tree available."
        return 1
    }

    # The S2500 series contains the common OA-TC6 baseline. ADIN1140 and
    # LAN865x may already be present at the selected base; if not, fetch just
    # their driver files from current upstream.
    [[ -n "$tree" && -d "$tree" ]] || { t1s_warn "No valid source directory for $target"; return 1; }
    local supplement=""
    if ! t1s_has_target "$tree" "$target"; then
        # Missing MAC-PHY drivers are sourced from the requested Linux 7.2
        # baseline. Never fetch moving 'master' into a pinned OA-TC6 stack.
        local raw="https://raw.githubusercontent.com/torvalds/linux/v7.2" path
        while IFS= read -r path; do
            [[ -n "$path" ]] || continue
            [[ -f "$tree/$path" ]] && continue
            t1s_fetch "$raw/$path" "$tree/$path" ||
                t1s_die "Required upstream source not found: $path"
        done < <(t1s_target_files "$target")
        supplement=" + Linux v7.2 driver files"
    fi

    t1s_has_target "$tree" "$target" || { t1s_warn "Required $target source set is incomplete"; return 1; }

    t1s_source_record "$repo_root" "$target" \
        "onsemi S2500 v8 series" \
        "net-next base $S2500_BASE_COMMIT; series $S2500_SERIES_MSGID$supplement"
    printf '%s\n' "$tree"
}
