#!/bin/sh
# build-apkovl.sh — build a minimal Alpine first-boot overlay (apkovl) for
# headless setup of a fresh Raspberry Pi SD card.
#
# Run this on your dev machine, against the boot (FAT) partition of a
# freshly-flashed Alpine aarch64 RPi SD card, BEFORE the card's first boot.
#
# What it does: enables eth0 (DHCP by default, or a static address if given)
# + sshd, and authorizes your SSH pubkey for root. That's the minimum needed
# to get a shell with no monitor/keyboard. Also always bakes in a static WiFi
# AP on wlan0 (hostapd + dnsmasq, config from wifi-ap/) as an additional,
# always-on interface — not an alternative to eth0, just a second way in when
# no Ethernet is available (see STATUS.md, milestone 2). Everything else
# (hostname, users, packages, whatever application the device will run) is
# deliberately out of scope here — do it afterward over that first SSH
# session, via your own project's provisioning script. Kept out of the
# overlay on purpose, since a bad overlay can't be debugged without pulling
# the card and re-mounting it.
#
# Hostname is intentionally NOT set here: Alpine's boot process looks for
# "<resolved-hostname>.apkovl.tar.gz", and on a fresh boot with plain DHCP
# and no reverse-DNS entry it resolves to "localhost" — so this script always
# writes localhost.apkovl.tar.gz and leaves /etc/hostname as "localhost" for
# the transient first-boot session. Set the real hostname later, over that
# SSH session, once the disk is actually installed (setup-alpine's disk step
# wipes the SD card contents, including whatever hostname you'd have baked
# into the overlay — no point setting it twice).
#
# Usage:
#   sh build-apkovl.sh <pubkey-file> [output-dir] [static-ip] [netmask] [secondary-pubkey-file]
#
# secondary-pubkey-file is optional: a second key to also authorize for root,
# appended as an extra line in authorized_keys. Useful when the user running
# this script (e.g. a sudoer account needed for disk/network setup elsewhere
# in the flow) isn't the same person who wants to SSH into the Pi afterward —
# authorize both up front instead of hand-appending the second key later.
#
# If static-ip is omitted, eth0 uses DHCP — fine when the Pi and your
# machine share a LAN with a router/switch in between (check the router's
# client list or `arp -a` afterward to find the address).
#
# If static-ip IS given, use it for a direct machine<->Pi cable with no DHCP
# server on the link (there's nothing to hand out an address otherwise), e.g.:
#
#   sh build-apkovl.sh ~/.ssh/id_ed25519.pub /Volumes/BOOT 169.254.100.1 255.255.0.0
#
# You'll also need to give your machine's own Ethernet adapter a compatible
# address on the same link (e.g. 169.254.100.2/16) — see
# flashing-base-alpine.md for the how-to.
#
# NOTE: mirrors Alpine's standard apkovl/lbu mechanism as inferred from a
# real, already-provisioned Alpine Pi and Alpine's documented behavior.
# See lessons-learned.md for what has and hasn't been confirmed working
# end-to-end on a truly blank card.

set -e

SCRIPTDIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

PUBKEY="$1"
OUTDIR="${2:-.}"
STATIC_IP="$3"
STATIC_NETMASK="${4:-255.255.0.0}"
SECONDARY_PUBKEY="$5"

if [ -z "$PUBKEY" ]; then
    echo "Usage: sh build-apkovl.sh <pubkey-file> [output-dir] [static-ip] [netmask] [secondary-pubkey-file]" >&2
    exit 1
fi
if [ ! -f "$PUBKEY" ]; then
    echo "Pubkey file not found: $PUBKEY" >&2
    exit 1
fi
if [ -n "$SECONDARY_PUBKEY" ] && [ ! -f "$SECONDARY_PUBKEY" ]; then
    echo "Secondary pubkey file not found: $SECONDARY_PUBKEY" >&2
    exit 1
fi
if [ ! -f "$SCRIPTDIR/wifi-ap/hostapd.conf" ]; then
    echo "Missing $SCRIPTDIR/wifi-ap/hostapd.conf" >&2
    exit 1
fi
if [ ! -f "$SCRIPTDIR/wifi-ap/dnsmasq.conf" ]; then
    echo "Missing $SCRIPTDIR/wifi-ap/dnsmasq.conf" >&2
    exit 1
fi
if [ ! -d "$OUTDIR" ]; then
    echo "Output dir not found: $OUTDIR" >&2
    exit 1
fi

# Resolve to absolute before the tar step below cd's into WORKDIR — a
# relative OUTDIR would otherwise resolve against WORKDIR post-cd and get
# silently deleted by the EXIT trap, discarding the output with no error.
OUTDIR=$(cd "$OUTDIR" && pwd)

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

mkdir -p "$WORKDIR/etc/apk/keys"
mkdir -p "$WORKDIR/etc/network"
mkdir -p "$WORKDIR/etc/runlevels/default"
mkdir -p "$WORKDIR/etc/hostapd"
mkdir -p "$WORKDIR/root/.ssh"

echo "localhost" > "$WORKDIR/etc/hostname"

# Marker (existence-only, content ignored) telling mkinitfs's diskless-boot
# init to add its own standard baseline services — devfs/dmesg/mdev/hwdrivers
# /modloop (sysinit), modules/sysctl/hostname/bootmisc/syslog (boot), clean
# shutdown handling — that a from-scratch minimal apkovl like this one
# otherwise skips entirely. Without it, modloop (the kernel-modules squashfs)
# never gets mounted, and setup-alpine's disk-install step fails outright
# with "mountpoint: /.modloop: No such file or directory". Self-cleaning:
# mkinitfs removes this file from the running system once it's acted on it,
# so nothing lingers on the persistent install.
touch "$WORKDIR/etc/.default_boot_services"

# Enabling the sshd runlevel symlink alone isn't enough — the diskless-boot
# init (mkinitfs's initramfs-init) only installs packages listed in
# etc/apk/world from the apkovl. Without this, /etc/init.d/sshd never gets
# installed in the first place, the runlevel symlink dangles, and sshd never
# starts (network comes up fine, but the port is never listening). Confirmed
# by reading initramfs-init.in directly: pkgs accumulate from
# "$sysroot"/etc/apk/world, then `apk add --root $sysroot ... $pkgs` runs
# against the local apks/ repo already on the boot partition (has a full
# APKINDEX, so apk's install_if resolution — which is what actually pulls in
# openssh-server-common-openrc, the package owning /etc/init.d/sshd — works
# offline). openssh-server alone is enough; sshd doesn't need the ssh client.
# hostapd/dnsmasq work the same way: install_if metadata on hostapd-openrc
# (openrc hostapd=<ver>) and dnsmasq-openrc (openrc dnsmasq-common=<ver>)
# means listing just the two parent packages is enough — apk's solver pulls
# in dnsmasq-common (a hard dependency of dnsmasq) and both -openrc packages
# automatically, same mechanism as openssh-server above.
printf '%s\n' openssh-server hostapd dnsmasq > "$WORKDIR/etc/apk/world"

# Trust key for this repo's own supplemental local package repo
# (apks-extra/ — packages setup-disk needs that Alpine's own RPi tarball
# doesn't ship locally: dosfstools, linux-rpi, raspberrypi-bootloader, etc.
# See lessons-learned.md). Safe to always include: mkinitfs's diskless-boot
# init only auto-generates etc/apk/repositories when the apkovl doesn't
# already ship one (it never touches etc/apk/keys/ either way), so baking
# the key in here has no ordering hazard. The matching private key is NOT
# in this repo — see apks-extra/README.md.
if [ -f "$SCRIPTDIR/apks-extra/minimal_pi-install.rsa.pub" ]; then
    cp "$SCRIPTDIR/apks-extra/minimal_pi-install.rsa.pub" "$WORKDIR/etc/apk/keys/"
fi

# offline-install-prep.sh: run this over the first-boot SSH session, before
# setup-alpine, to copy the local apk repos into tmpfs (they'd otherwise
# vanish when setup-disk unmounts the boot media to repartition it). Baked
# in here so it's present automatically, no separate copy step.
if [ -f "$SCRIPTDIR/offline-install-prep.sh" ]; then
    cp "$SCRIPTDIR/offline-install-prep.sh" "$WORKDIR/root/offline-install-prep.sh"
    chmod 755 "$WORKDIR/root/offline-install-prep.sh"
fi

# WiFi AP (milestone 2): always baked in as an additional interface, not an
# alternative to eth0. hostapd.conf/dnsmasq.conf are static, repo-resident
# config (placeholder SSID/passphrase — edit wifi-ap/ before flashing for
# real use), copied by reference same as the trust key and
# offline-install-prep.sh above. Presence already required near the top of
# this script (unlike the trust key, wifi-ap/ is a permanent part of the
# repo, not an optional artifact).
cp "$SCRIPTDIR/wifi-ap/hostapd.conf" "$WORKDIR/etc/hostapd/hostapd.conf"
cp "$SCRIPTDIR/wifi-ap/dnsmasq.conf" "$WORKDIR/etc/dnsmasq.conf"

if [ -n "$STATIC_IP" ]; then
    cat > "$WORKDIR/etc/network/interfaces" <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address $STATIC_IP
    netmask $STATIC_NETMASK
EOF
else
    cat > "$WORKDIR/etc/network/interfaces" <<'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF
fi

# wlan0 AP: unconditional, regardless of how eth0 above is configured.
# 192.168.4.1/24 matches wifi-ap/dnsmasq.conf's dhcp-range (.10-.100) — this
# address sits outside that pool, same /24.
cat >> "$WORKDIR/etc/network/interfaces" <<'EOF'

auto wlan0
iface wlan0 inet static
    address 192.168.4.1
    netmask 255.255.255.0
EOF

cp "$PUBKEY" "$WORKDIR/root/.ssh/authorized_keys"
if [ -n "$SECONDARY_PUBKEY" ]; then
    # Blank line first regardless of whether $PUBKEY's file already ends in
    # one — sshd ignores blank lines in authorized_keys, but a missing
    # newline between the two would otherwise concatenate them onto one
    # line and silently invalidate both.
    echo "" >> "$WORKDIR/root/.ssh/authorized_keys"
    cat "$SECONDARY_PUBKEY" >> "$WORKDIR/root/.ssh/authorized_keys"
fi
chmod 700 "$WORKDIR/root/.ssh"
chmod 600 "$WORKDIR/root/.ssh/authorized_keys"

ln -sf /etc/init.d/sshd "$WORKDIR/etc/runlevels/default/sshd"
ln -sf /etc/init.d/networking "$WORKDIR/etc/runlevels/default/networking"
# hostapd's depend() has "need net", dnsmasq's has "need localmount net" —
# OpenRC's own resolver already orders interface-up before hostapd before
# dnsmasq correctly with all four enabled in the same runlevel, no custom
# depend() override needed (confirmed by reading both init scripts directly
# out of the vendored -openrc packages).
ln -sf /etc/init.d/hostapd "$WORKDIR/etc/runlevels/default/hostapd"
ln -sf /etc/init.d/dnsmasq "$WORKDIR/etc/runlevels/default/dnsmasq"

OUTFILE="$OUTDIR/localhost.apkovl.tar.gz"
# --uid/--gid/--uname/--gname force root:root ownership in the archive.
# Without this, tar stores whatever local user built the apkovl (this script
# never runs as root on the Mac), and unpacking that as root on the Pi during
# boot preserves those non-root numeric IDs verbatim — so /root/.ssh ends up
# NOT owned by root. sshd's StrictModes (on by default) then silently
# rejects the key: no error, just "Permission denied (publickey)" with a
# perfectly correct-looking key and file permission bits.
( cd "$WORKDIR" && tar czf "$OUTFILE" --uid 0 --gid 0 --uname root --gname root etc root )

echo "==> Wrote $OUTFILE"
if [ -n "$SECONDARY_PUBKEY" ]; then
    echo "    Authorized 2 keys for root: $PUBKEY and $SECONDARY_PUBKEY"
fi
echo "    Copy/verify it sits at the ROOT of the boot (FAT) partition,"
echo "    eject the card, boot the Pi, then:"
if [ -n "$STATIC_IP" ]; then
    echo "      ssh root@$STATIC_IP"
    echo "    (make sure your machine's own Ethernet adapter has a compatible"
    echo "    address on the same link, e.g. 169.254.100.2 netmask $STATIC_NETMASK)"
else
    echo "      ssh root@<dhcp-address-of-pi>"
    echo "    (check your router/DHCP leases for the address — first boot has"
    echo "    no static IP yet)."
fi
echo ""
echo "    Hostname isn't set yet — set it over this SSH session, after"
echo "    setup-alpine has installed to disk (see flashing-base-alpine.md)."
echo ""
AP_SSID=$(sed -n 's/^ssid=//p' "$SCRIPTDIR/wifi-ap/hostapd.conf" | head -1)
echo "    Also broadcasting WiFi AP '$AP_SSID' (see wifi-ap/hostapd.conf for"
echo "    the passphrase) — ssh root@192.168.4.1 once connected to it."
