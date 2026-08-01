#!/bin/sh
# offline-install-prep.sh — copy local apk repos into tmpfs and configure
# them, before running setup-alpine. Run this on the Pi, over the first-boot
# SSH session build-apkovl.sh gets you, BEFORE `setup-alpine -e -f answerfile`.
#
# Why this exists: setup-disk (invoked by setup-alpine's disk-install step)
# has to unmount the boot media to repartition it -- but Alpine's own local
# package cache (apks/) lives ON that same media, so its repo disappears out
# from under the install unless copied into RAM first. The same applies to
# apks-extra/, this repo's own supplemental local repo for packages Alpine's
# RPi tarball doesn't ship locally at all (dosfstools, linux-rpi,
# raspberrypi-bootloader, etc.) -- see lessons-learned.md ("setup-alpine
# (step 6) full CLI automation" and the offline package-vendoring section)
# for exactly why each of these is needed and how apks-extra was built.
#
# Usage:
#   sh offline-install-prep.sh [boot-device] [mountpoint]
#
# Defaults match a standard single-SD-card Pi (mmcblk0p1, the boot/FAT
# partition apks/ and apks-extra/ were copied onto during flashing --
# see flashing-base-alpine.md step 3).

set -e

BOOTDEV="${1:-/dev/mmcblk0p1}"
MNT="${2:-/media/mmcblk0p1}"

mkdir -p "$MNT"
mountpoint -q "$MNT" || mount -t vfat -o ro "$BOOTDEV" "$MNT"

mkdir -p /root/apks-cache
cp -r "$MNT"/apks/. /root/apks-cache/

if [ -d "$MNT"/apks-extra ]; then
    mkdir -p /root/apks-extra
    cp -r "$MNT"/apks-extra/. /root/apks-extra/
    mkdir -p /etc/apk/keys
    cp /root/apks-extra/*.pub /etc/apk/keys/ 2>/dev/null || true
    printf '%s\n%s\n' /root/apks-cache /root/apks-extra > /etc/apk/repositories
else
    echo "==> No apks-extra/ found on boot media; using stock repo only." >&2
    printf '%s\n' /root/apks-cache > /etc/apk/repositories
fi

# Deliberately not unmounting $MNT here: /.modloop is loop-mounted from a
# file on this same partition (see lessons-learned.md), so it's normal for
# this to report busy. setup-disk has its own correct handling for this via
# copy-modloop (copies kernel modules out, stops modloop, then unmounts) --
# it runs at the right point in its own flow, no need to preempt it here.

apk update
echo "==> Offline repos ready in /etc/apk/repositories:"
cat /etc/apk/repositories
