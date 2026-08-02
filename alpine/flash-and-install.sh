#!/bin/bash
# flash-and-install.sh — milestone-1 driver: blank SD card to a headless,
# SSH-accessible, persistently-installed Alpine system on a Pi 3B+, over a
# direct Ethernet cable, in one script call.
#
# This is the automation described in flashing-base-alpine.md, collapsed into
# one script per the milestone-1 scope decision (STATUS.md, 2026-08-01): the
# individual steps were already proven on real hardware, but doing them by
# hand each time isn't "done." This script is Mac-side only (uses diskutil /
# networksetup, both macOS-specific) — it drives the Pi remotely over
# ssh/scp, same as you'd do by hand. Nothing new runs ON the Pi: it still
# just uses offline-install-prep.sh (baked into the apkovl already) and
# Alpine's own setup-alpine.
#
# Static-IP direct-cable is the only mode wired up here — it's the only path
# actually confirmed end-to-end (STATUS.md). DHCP/same-LAN is intentionally
# NOT branched-in speculatively; add it once that path itself is confirmed.
#
# Usage (run with bash specifically, NOT sh — this script uses bash arrays
# and process substitution for the network-service-reorder logic below;
# macOS's /bin/sh is bash in restricted POSIX-compatibility mode and rejects
# both with a syntax error):
#   bash flash-and-install.sh <hostname> <pubkey-file> <disk> <alpine-tarball> [pi-ip] [netmask] [mac-service] [secondary-pubkey-file]
#
#   hostname        real hostname for the installed system
#   pubkey-file     SSH public key to authorize for root (e.g. ~/.ssh/id_ed25519.pub)
#   disk            the SD card's diskutil identifier (e.g. disk4) — run
#                    `diskutil list` yourself first and double check. THIS
#                    DISK GETS ERASED. Accepts "disk4" or "/dev/disk4".
#   alpine-tarball   path to an already-downloaded alpine-rpi-*-aarch64.tar.gz
#                    (see flashing-base-alpine.md step 1 for where to get it —
#                    this script doesn't fetch it, so the offline/no-internet
#                    boundary stays exactly where flashing-base-alpine.md puts it)
#   pi-ip           default 169.254.100.1
#   netmask         default 255.255.0.0
#   mac-service     networksetup hardware-port name for YOUR Mac's Ethernet
#                    adapter on this link (e.g. "USB 10/100/1000 LAN") — find
#                    it via `networksetup -listallhardwareports`. If omitted,
#                    this script lists candidates and stops rather than
#                    guessing: a real session found multiple simultaneous
#                    Ethernet-labeled ports on one Mac, and picking the wrong
#                    one silently breaks the link instead of failing loudly.
#   secondary-pubkey-file
#                   optional: also authorize a second key for root. Needed
#                   whenever the sudoer running this script (for diskutil /
#                   networksetup) isn't the person who actually wants to SSH
#                   into the Pi afterward — this script's own ssh/scp calls
#                   authenticate using whichever identity belongs to the user
#                   actually running it, so <pubkey-file> above should be
#                   THAT user's key; pass the other person's key here instead
#                   of hand-appending it to authorized_keys after the fact.
#
# Needs sudo for two steps (partitioning the disk, setting the Mac's own
# static IP) — run this yourself in a real terminal, not through anything
# that can't prompt for a password interactively.

set -e

SCRIPTDIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

info()  { printf '==> %s\n' "$*"; }
warn()  { printf 'WARNING: %s\n' "$*" >&2; }
err()   { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

HOSTNAME_ARG="$1"
PUBKEY="$2"
DISK="$3"
TARBALL="$4"
PI_IP="${5:-169.254.100.1}"
NETMASK="${6:-255.255.0.0}"
MAC_SERVICE="$7"
SECONDARY_PUBKEY="$8"

if [ -z "$HOSTNAME_ARG" ] || [ -z "$PUBKEY" ] || [ -z "$DISK" ] || [ -z "$TARBALL" ]; then
    cat >&2 <<USAGE
Usage: bash flash-and-install.sh <hostname> <pubkey-file> <disk> <alpine-tarball> [pi-ip] [netmask] [mac-service] [secondary-pubkey-file]

See the comment header in this script for what each argument means.
USAGE
    exit 1
fi

[ -f "$PUBKEY" ]  || err "Pubkey file not found: $PUBKEY"
[ -f "$TARBALL" ] || err "Alpine tarball not found: $TARBALL"
[ -n "$SECONDARY_PUBKEY" ] && { [ -f "$SECONDARY_PUBKEY" ] || err "Secondary pubkey file not found: $SECONDARY_PUBKEY"; }

# Accept either "disk4" or "/dev/disk4" — diskutil takes both, but normalize
# so the confirmation prompt below always shows the same form the user typed
# into `diskutil list`.
DISK="${DISK#/dev/}"

if [ -z "$MAC_SERVICE" ]; then
    warn "No mac-service given — can't safely guess which of your Mac's Ethernet"
    warn "adapters is on this link (a real session found several simultaneously-"
    warn "present ones). Candidates (filter out Wi-Fi / Thunderbolt Bridge / virtual):"
    echo ""
    networksetup -listallhardwareports
    echo ""
    err "Re-run with the exact 'Hardware Port' name as the 7th argument."
fi

# --- Phase 0: destructive-action confirmation -------------------------------
# diskutil partitionDisk below erases $DISK unconditionally. Wrong-disk here
# is catastrophic (could be the Mac's own boot volume) — worth the friction
# of a typed confirmation rather than a single -y flag.
echo ""
info "About to ERASE the following disk:"
diskutil list "$DISK" || err "diskutil doesn't recognize disk '$DISK' — check \`diskutil list\` yourself first."
echo ""
printf 'Type the disk identifier (%s) again to confirm erase: ' "$DISK"
read -r CONFIRM_DISK
[ "$CONFIRM_DISK" = "$DISK" ] || err "Confirmation didn't match — aborting, nothing touched."

# --- Phase 1: build the card -------------------------------------------------
info "Partitioning $DISK (1GB FAT32 boot partition + free space, per lessons-learned.md)..."
sudo diskutil partitionDisk "$DISK" MBR "MS-DOS FAT32" BOOT 1G "Free Space" EMPTY R

BOOTVOL=/Volumes/BOOT
[ -d "$BOOTVOL" ] || err "Expected $BOOTVOL to be mounted after partitioning — it isn't. Stopping before touching anything further."

info "Extracting $TARBALL onto $BOOTVOL..."
tar xzf "$TARBALL" -C "$BOOTVOL"

# Pi 3B+ needs the flat boot layout (see lessons-learned.md — the raw tarball
# nests kernel/initramfs under boot/, which produces a 7-flash "kernel not
# found" ACT LED code on this board). Applied unconditionally: this script is
# scoped to Pi 3B+ (milestone 1), not a multi-board dispatcher.
if [ -d "$BOOTVOL/boot" ]; then
    info "Flattening boot/ layout for Pi 3B+..."
    mv "$BOOTVOL"/boot/* "$BOOTVOL"/
    rmdir "$BOOTVOL"/boot
    sed -i '' 's#boot/vmlinuz-rpi#vmlinuz-rpi#; s#boot/initramfs-rpi#initramfs-rpi#' "$BOOTVOL"/config.txt
fi

info "Copying apks-extra/ onto $BOOTVOL (offline setup-alpine disk install)..."
cp -r "$SCRIPTDIR/apks-extra" "$BOOTVOL/"

info "Building first-boot apkovl (static IP $PI_IP/$NETMASK)..."
sh "$SCRIPTDIR/build-apkovl.sh" "$PUBKEY" "$BOOTVOL" "$PI_IP" "$NETMASK" "$SECONDARY_PUBKEY"

# Defensive check against a real historical bug (lessons-learned.md #1): a
# relative OUTDIR used to make build-apkovl.sh silently discard its own
# output. build-apkovl.sh resolves OUTDIR absolutely now, but this check
# costs nothing and catches the whole bug class if that ever regresses.
APKOVL="$BOOTVOL/localhost.apkovl.tar.gz"
[ -f "$APKOVL" ] || err "apkovl missing at $APKOVL after build-apkovl.sh — stopping before ejecting."

info "Ejecting $DISK..."
diskutil eject "$DISK"

# --- Phase 2: this Mac's own interface on the direct-cable link -------------
MAC_IP="169.254.100.2"
info "Configuring '$MAC_SERVICE' with static IP $MAC_IP/$NETMASK (self-routed, point-to-point)..."
sudo networksetup -setmanual "$MAC_SERVICE" "$MAC_IP" "$NETMASK" "$MAC_IP"

# Known gotcha (lessons-learned.md): if this point-to-point service outranks
# the Mac's normal uplink in service order, macOS may pick it for the
# *default* route the instant it's configured, silently breaking normal
# internet access on the Mac. Detect and fix automatically rather than
# leaving the user to debug "the internet stopped working" later.
MAC_DEVICE=$(networksetup -listallhardwareports | awk -v svc="$MAC_SERVICE" '
    $0 == "Hardware Port: " svc { want=1; next }
    want && /^Device:/ { print $2; exit }
')
DEFAULT_IFACE=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')

if [ -n "$MAC_DEVICE" ] && [ "$DEFAULT_IFACE" = "$MAC_DEVICE" ]; then
    warn "'$MAC_SERVICE' just took over the Mac's default route."
    # Bash array, not string-splitting — service names routinely contain
    # spaces (e.g. "USB 10/100/1000 LAN"), which a plain $(...) word-split
    # would silently mangle into multiple arguments.
    CURRENT_ORDER=()
    while IFS= read -r svc; do
        CURRENT_ORDER+=("$svc")
    done < <(networksetup -listnetworkserviceorder | sed -n 's/^([0-9]*) \(.*\)$/\1/p')

    HAS_WIFI=0
    for svc in "${CURRENT_ORDER[@]}"; do
        [ "$svc" = "Wi-Fi" ] && HAS_WIFI=1
    done

    if [ "$HAS_WIFI" -eq 1 ]; then
        NEW_ORDER=("Wi-Fi")
        for svc in "${CURRENT_ORDER[@]}"; do
            [ "$svc" = "Wi-Fi" ] && continue
            NEW_ORDER+=("$svc")
        done
        sudo networksetup -ordernetworkservices "${NEW_ORDER[@]}"
        info "Service order fixed — Wi-Fi restored as the default route."
    else
        warn "No 'Wi-Fi' service found to restore automatically — fix manually:"
        warn "  networksetup -listnetworkserviceorder"
        warn "  sudo networksetup -ordernetworkservices <your-normal-uplink> ...(rest in original order)..."
    fi
fi

# --- Phase 3: physical step, then wait for the Pi -----------------------------
# $PI_IP is a rotating identity by design: every re-flash of the same card (or
# a different card reusing this same static IP, which is the normal case for
# this repo's direct-cable setup) presents a brand-new random SSH host key.
# A real test session hit this directly: StrictHostKeyChecking=accept-new
# only auto-trusts a host with NO existing known_hosts entry — it does NOT
# override a *changed* key for a host already seen (e.g. from a previous
# flash to this same IP), so every ssh/scp call in this script would fail
# outright on any second-or-later run, with the wait loops just spinning
# until their timeout ("Never reached root@... over SSH" even though the Pi
# was actually up and answering fine). Pinning host identity for a machine
# whose identity is expected to change every run is the wrong model entirely,
# so this script's own automated calls don't persist or check it at all —
# UserKnownHostsFile=/dev/null skips writing anywhere, StrictHostKeyChecking=no
# skips verifying. This only affects this script's internal automation; your
# own manual `ssh root@<pi-ip>` afterward still uses your real known_hosts
# and behaves completely normally. Acceptable here specifically because this
# is a direct point-to-point cable, not a shared network segment where
# spoofing the IP is realistic.
SSH_OPTS=(-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR)

echo ""
info "Insert the card into the Pi, connect the direct Ethernet cable, and power it on."
printf "Press Enter once it's powered on: "
read -r _

info "Waiting for SSH on $PI_IP (first boot can take a minute or two)..."
i=0
until ssh -o BatchMode=yes -o ConnectTimeout=3 "${SSH_OPTS[@]}" \
        "root@$PI_IP" true 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -gt 60 ] && err "Never reached root@$PI_IP over SSH after 5 minutes. Try 'ssh root@$PI_IP' by hand in another terminal to see the actual error (LED flash codes / cable issue if it hangs with no response at all; a specific SSH error otherwise) — see lessons-learned.md."
    sleep 5
    printf '.'
done
echo ""
info "SSH is up."

# The Ethernet link on this hardware has a documented tendency to flap under
# I/O load (lessons-learned.md, "Hardware reliability") — root cause
# unconfirmed (leading hypothesis: power-supply undervoltage), but it's a
# known, recurring condition rather than a rare fluke. Every remote step past
# this point retries through transient drops instead of treating one failed
# ssh/scp call as fatal.
ssh_retry() {
    tries=0
    until ssh -o ConnectTimeout=5 "${SSH_OPTS[@]}" "root@$PI_IP" "$@"; do
        tries=$((tries + 1))
        [ "$tries" -ge 12 ] && err "SSH command kept failing after $tries retries: $*"
        warn "SSH call failed (attempt $tries) — link may be flapping, retrying in 5s..."
        sleep 5
    done
}

scp_retry() {
    tries=0
    until scp -o ConnectTimeout=5 "${SSH_OPTS[@]}" "$1" "root@$PI_IP:$2"; do
        tries=$((tries + 1))
        [ "$tries" -ge 12 ] && err "scp kept failing after $tries retries: $1 -> $2"
        warn "scp failed (attempt $tries) — link may be flapping, retrying in 5s..."
        sleep 5
    done
}

# --- Phase 4: remote install --------------------------------------------------
info "Prepping offline apk repos on the Pi..."
ssh_retry "sh /root/offline-install-prep.sh"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

info "Building answerfile for hostname '$HOSTNAME_ARG'..."
sh "$SCRIPTDIR/build-answerfile.sh" "$HOSTNAME_ARG" "$WORKDIR" /dev/mmcblk0
scp_retry "$WORKDIR/answerfile" "/root/answerfile"

info "Launching setup-alpine on the Pi (detached — survives a link drop mid-install)..."
ssh_retry "rm -f /root/setup-alpine.log; nohup sh -c 'yes | setup-alpine -e -f /root/answerfile' > /root/setup-alpine.log 2>&1 < /dev/null &"

info "Waiting for the disk install to finish (this can take several minutes)..."
i=0
while :; do
    i=$((i + 1))
    [ "$i" -gt 180 ] && err "setup-alpine hasn't finished after 15 minutes — check /root/setup-alpine.log on the Pi."

    STATUS=$(ssh -o ConnectTimeout=5 "${SSH_OPTS[@]}" "root@$PI_IP" \
        "grep -q 'Installation is complete' /root/setup-alpine.log 2>/dev/null && echo DONE || (pgrep -f 'setup-alpine -e -f' >/dev/null && echo RUNNING || echo UNKNOWN)" \
        2>/dev/null || echo UNREACHABLE)

    case "$STATUS" in
        DONE) break ;;
        RUNNING|UNKNOWN|UNREACHABLE) sleep 5; printf '.' ;;
    esac
done
echo ""
info "Install complete."

info "Rebooting into the persistent install..."
# Deliberately NOT ssh_retry: a reboot command is expected to drop the
# connection (possibly with a non-zero exit from ssh itself) rather than
# return cleanly. ssh_retry's retry-until-success semantics are the wrong
# tool here — they'd hard-fail the whole script if the Pi doesn't come back
# within its retry budget, even though the reboot itself worked fine. One
# best-effort shot, exit code ignored either way.
ssh -o ConnectTimeout=5 "${SSH_OPTS[@]}" "root@$PI_IP" "reboot" 2>/dev/null || true

info "Waiting for the persistent system to come back over SSH..."
i=0
until ssh -o BatchMode=yes -o ConnectTimeout=3 "${SSH_OPTS[@]}" \
        "root@$PI_IP" true 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -gt 60 ] && err "Never came back over SSH after reboot (waited 5 minutes). Try 'ssh root@$PI_IP' by hand in another terminal to see the actual error."
    sleep 5
    printf '.'
done
echo ""

# Purely informational sanity-check queries below — must never be allowed to
# kill the script this late (a real run hit exactly this: the wait loop above
# succeeded on its very first check, but sshd flickered again moments later
# while still finishing first-boot setup, and a bare $(...) assignment with
# no fallback took the whole script down via set -e one step from the finish
# line, after the actual disk install had already succeeded). Retry generously,
# fall back to a placeholder rather than exiting either way.
#
# A real run showed why 30s isn't generous enough: the wait loop above
# succeeded on its very first check (likely catching the tail end of the old
# pre-reboot session, not the new persistent one), then GOT_HOSTNAME's own
# retries all failed — but GOT_ROOT, using identical logic ~30s later, then
# succeeded fine. The persistent boot (fresh host keys, full service startup)
# was still settling; it just needed more time than one 30s budget gave it.
ssh_output_retry() {
    tries=0
    while [ "$tries" -lt 40 ]; do
        if out=$(ssh -o ConnectTimeout=5 "${SSH_OPTS[@]}" "root@$PI_IP" "$@" 2>/dev/null); then
            printf '%s' "$out"
            return 0
        fi
        tries=$((tries + 1))
        sleep 3
    done
    printf '(unavailable — check manually)'
}

GOT_HOSTNAME=$(ssh_output_retry hostname)
GOT_ROOT=$(ssh_output_retry "mount | grep ' / ' || true")

info "Done. Persistent Alpine system is up at root@$PI_IP"
info "  hostname: $GOT_HOSTNAME"
info "  root fs:  $GOT_ROOT"
[ -n "$SECONDARY_PUBKEY" ] && info "  authorized keys: $PUBKEY and $SECONDARY_PUBKEY"
[ "$GOT_HOSTNAME" = "$HOSTNAME_ARG" ] || warn "hostname doesn't match what was requested ($HOSTNAME_ARG) — check manually."
