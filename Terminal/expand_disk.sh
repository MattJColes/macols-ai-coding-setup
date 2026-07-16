#!/bin/bash

# Re-exec under bash if invoked with sh/dash (bashisms ahead)
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

# expand_disk.sh — grow the root filesystem to use the WHOLE disk.
#
# Why you need this: the Ubuntu Server installer's default LVM layout only
# assigns part of the disk to the root logical volume (people often see it
# "stuck" at ~100/128 GB) and leaves the rest as free space in the volume
# group. On VMs whose virtual disk was later enlarged, the partition itself
# also doesn't fill the disk. This script fixes both, end to end:
#
#   1. growpart  -> expand the partition to fill the disk
#   2. pvresize  -> let LVM see the bigger partition (LVM only)
#   3. lvextend  -> grow the logical volume into all free VG space (LVM only)
#   4. resize2fs / xfs_growfs / btrfs resize -> grow the filesystem online
#
# It auto-detects LVM vs. a plain partition and ext4/xfs/btrfs, is idempotent
# (safe to re-run), and grows the live root filesystem with no unmount/reboot.
#
# Usage:
#   sudo ./expand_disk.sh           # show plan, ask for confirmation
#   sudo ./expand_disk.sh --yes     # non-interactive (for automation)
#   sudo ./expand_disk.sh --dry-run # show what would happen, change nothing

set -euo pipefail

ASSUME_YES=0
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes)     ASSUME_YES=1 ;;
        -n|--dry-run) DRY_RUN=1 ;;
        -h|--help)
            sed -n '8,27p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

# --- Must run as root ---
if [ "$(id -u)" -ne 0 ]; then
    echo "Re-running with sudo..."
    exec sudo -E bash "$0" "$@"
fi

run() {
    echo "  + $*"
    if [ "$DRY_RUN" -eq 0 ]; then
        "$@"
    fi
}

# --- Ensure growpart (cloud-guest-utils) is available ---
if ! command -v growpart >/dev/null 2>&1; then
    echo "Installing cloud-guest-utils (provides growpart)..."
    export DEBIAN_FRONTEND=noninteractive
    run apt-get update -y
    run apt-get install -y cloud-guest-utils
fi

# --- Discover the root filesystem ---
ROOT_SRC=$(findmnt -no SOURCE /)
ROOT_SRC=${ROOT_SRC%%[*}              # strip btrfs "[subvol]" suffix if present
ROOT_FSTYPE=$(findmnt -no FSTYPE /)
ROOT_TYPE=$(lsblk -dno TYPE "$ROOT_SRC" 2>/dev/null | head -n1)

echo "=== Expand root filesystem to use the full disk ==="
echo "Root device : $ROOT_SRC"
echo "Filesystem  : $ROOT_FSTYPE"
echo "Device type : ${ROOT_TYPE:-unknown}"
echo ""
echo "Before:"
df -h / | sed 's/^/  /'
echo ""

if [ "$ASSUME_YES" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    read -rp "Proceed with expanding the disk? [y/N]: " reply
    case "$reply" in
        [Yy]*) ;;
        *) echo "Aborted."; exit 0 ;;
    esac
fi

# Grow the partition that backs $1 (e.g. /dev/sda2, /dev/nvme0n1p2) to fill
# its disk. Tolerates growpart's "NOCHANGE" (nothing left to grow) exit code.
# A genuine failure here is a non-fatal warning: the LVM lvextend step below
# can still reclaim free space already present in the volume group.
grow_partition() {
    local part="$1" name disk partnum out rc
    name=$(basename "$part")
    if [ ! -e "/sys/class/block/$name/partition" ]; then
        echo "  ! $part is not a partition (no sysfs entry); skipping growpart" >&2
        return 0
    fi
    partnum=$(cat "/sys/class/block/$name/partition")
    # Derive the parent disk from sysfs — unambiguous for both sdX and nvme
    # naming (e.g. /sys/class/block/nvme0n1p3 -> .../nvme0n1/nvme0n1p3).
    disk="/dev/$(basename "$(dirname "$(readlink -f "/sys/class/block/$name")")")"
    echo "  + growpart $disk $partnum"
    if [ "$DRY_RUN" -eq 1 ]; then
        return 0
    fi
    out=$(growpart "$disk" "$partnum" 2>&1) && rc=0 || rc=$?
    echo "$out" | sed 's/^/    /'
    if [ "$rc" -ne 0 ] && ! grep -qi 'NOCHANGE' <<<"$out"; then
        echo "  ! growpart could not grow $part (rc=$rc); continuing — lvextend" \
             "may still reclaim free space already in the volume group." >&2
    fi
}

# Grow the filesystem mounted at / (online, no unmount needed).
grow_fs() {
    case "$ROOT_FSTYPE" in
        ext2|ext3|ext4) run resize2fs "$ROOT_SRC" ;;
        xfs)            run xfs_growfs / ;;
        btrfs)          run btrfs filesystem resize max / ;;
        *)
            echo "Unsupported filesystem '$ROOT_FSTYPE'; grow it manually." >&2
            exit 1 ;;
    esac
}

if [ "$ROOT_TYPE" = "lvm" ]; then
    # ---- LVM path: grow partition(s) -> pvresize -> lvextend -> grow fs ----
    VG=$(lvs --noheadings -o vg_name "$ROOT_SRC" | tr -d '[:space:]')
    echo "LVM detected. Volume group: $VG"

    # Each physical volume in the VG sits on a partition that may not fill its
    # disk yet — grow the partition, then let LVM pick up the extra space.
    while read -r pv; do
        [ -n "$pv" ] || continue
        grow_partition "$pv"
        run pvresize "$pv"
    done < <(pvs --noheadings -o pv_name -S "vg_name=$VG" | tr -d ' ')

    # Hand all free extents in the VG to the root logical volume.
    run lvextend -l +100%FREE "$ROOT_SRC"
    grow_fs
else
    # ---- Plain partition path: grow partition -> grow fs ----
    echo "No LVM; treating $ROOT_SRC as a plain partition."
    grow_partition "$ROOT_SRC"
    grow_fs
fi

echo ""
echo "After:"
df -h / | sed 's/^/  /'
echo ""
if [ "$DRY_RUN" -eq 1 ]; then
    echo "(dry run — no changes were made)"
else
    echo "=== Done. Root filesystem now uses the available disk space. ==="
fi
