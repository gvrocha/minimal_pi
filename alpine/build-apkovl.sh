#!/bin/sh
# build-apkovl.sh — build a minimal Alpine first-boot overlay (apkovl) for
# headless setup of a fresh Raspberry Pi SD card.
#
# Run this on your dev machine, against the boot (FAT) partition of a
# freshly-flashed Alpine aarch64 RPi SD card, BEFORE the card's first boot.
#
# What it does: enables eth0 (DHCP by default, or a static address if given)
# + sshd, and authorizes your SSH pubkey for root. That's the minimum needed
# to get a shell with no monitor/keyboard. Everything else (hostname, users,
# wifi, packages, whatever application the device will run) is deliberately
# out of scope here — do it afterward over that first SSH session, via your
# own project's provisioning script. Kept out of the overlay on purpose,
# since a bad overlay can't be debugged without pulling the card and
# re-mounting it.
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
#   sh build-apkovl.sh <pubkey-file> [output-dir] [static-ip] [netmask]
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

PUBKEY="$1"
OUTDIR="${2:-.}"
STATIC_IP="$3"
STATIC_NETMASK="${4:-255.255.0.0}"

if [ -z "$PUBKEY" ]; then
    echo "Usage: sh build-apkovl.sh <pubkey-file> [output-dir] [static-ip] [netmask]" >&2
    exit 1
fi
if [ ! -f "$PUBKEY" ]; then
    echo "Pubkey file not found: $PUBKEY" >&2
    exit 1
fi

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

mkdir -p "$WORKDIR/etc/network"
mkdir -p "$WORKDIR/etc/runlevels/default"
mkdir -p "$WORKDIR/root/.ssh"

echo "localhost" > "$WORKDIR/etc/hostname"

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

cp "$PUBKEY" "$WORKDIR/root/.ssh/authorized_keys"
chmod 700 "$WORKDIR/root/.ssh"
chmod 600 "$WORKDIR/root/.ssh/authorized_keys"

ln -sf /etc/init.d/sshd "$WORKDIR/etc/runlevels/default/sshd"
ln -sf /etc/init.d/networking "$WORKDIR/etc/runlevels/default/networking"

OUTFILE="$OUTDIR/localhost.apkovl.tar.gz"
( cd "$WORKDIR" && tar czf "$OUTFILE" etc root )

echo "==> Wrote $OUTFILE"
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
