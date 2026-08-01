# Flashing a blank-slate Alpine SD card

Gets a truly blank SD card to a headless, SSH-accessible, persistently-installed Alpine system. Stops there — installing anything project-specific happens afterward, over the SSH session this leaves you with.

Primary instructions are for a Mac. Windows/Linux notes are called out briefly where the steps differ.

**Status:** confirmed working end-to-end on a Pi 3B+ (2026-08-01) — blank card through to a persistent, disk-booted, SSH-accessible system, fully CLI-automated with no interactive steps and no internet access needed at flash-time. See `lessons-learned.md` for the full story (including several real bugs found and fixed) and for what's still unconfirmed (Pi 4/5, the DHCP path, WiFi AP mode).

---

## 0. What you need

- A spare microSD card — prefer a small one (8–16GB) if you'll be iterating; formatting/erasing a large card takes noticeably longer (see `lessons-learned.md`)
- A machine with the card in a reader
- Your SSH public key (e.g. `~/.ssh/id_ed25519.pub`)
- Network access — either a LAN the Pi's eth0 will land on, or a direct Ethernet cable to the Pi (see step 4)

---

## 1. Download the Alpine image

Alpine ships Raspberry Pi images as a **tarball of boot-partition contents**, not a dd-able `.img` — you format the card yourself and extract the tarball onto it.

Get the aarch64 build from the official downloads page:

https://alpinelinux.org/downloads/ → "Raspberry Pi" row → aarch64

Or directly from the CDN mirror (adjust version as needed):

```sh
curl -LO https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/aarch64/alpine-rpi-3.21.6-aarch64.tar.gz
```

**One image covers more boards than you'd expect.** The aarch64 tarball is universal across all 64-bit-capable Raspberry Pi boards, not per-model — it ships DTBs for Pi 2 (v1.2+), Pi 3 (all variants), Zero 2 W, CM3, Pi 4/400/CM4, and Pi 5/500/CM5 in one file; the firmware auto-selects the right one at boot. It does **not** cover 32-bit-only boards — original Pi Zero (v1), Pi 1, and Pi 2 v1.1 need Alpine's separate `armhf`/`armv7` image instead. Confirm your target board is aarch64-capable before assuming this download is right.

---

## 2. Format the SD card

**Mac:**

```sh
diskutil list                    # identify the card, e.g. /dev/disk4 — double-check this!
sudo diskutil partitionDisk disk4 MBR "MS-DOS FAT32" BOOT 1G "Free Space" EMPTY R
```

This creates a 1GB FAT32 boot partition (mounted at `/Volumes/BOOT`) and leaves the rest of the card as an explicit unformatted gap — plenty of room for the ~100MB of Alpine boot files plus this repo's `apks-extra/` (see step 3). Prefer this over `diskutil eraseDisk MS-DOS BOOT MBRFormat`, which formats the *entire* card as one FAT32 partition: FAT32 format time scales with the size of the partition being formatted, so on a large card (100GB+) that can take several minutes versus seconds for a 1GB partition. `setup-disk` (step 6) safely repartitions the *whole physical disk* later anyway while the OS is running entirely in memory, so the leftover free space isn't wasted or orphaned — this is fine for a real deployment, not just faster iteration while debugging.

**Windows:** format the whole card FAT32/MBR via Disk Management or `diskpart`, then extract the tarball with 7-Zip.

**Linux:** partition with `fdisk` (single partition, type `c` W95 FAT32 LBA), then `mkfs.vfat -F32 /dev/sdX1`.

Same end state on all three: one FAT32 boot partition, MBR scheme.

---

## 3. Extract the Alpine tarball onto the card

```sh
tar xzf alpine-rpi-3.21.6-aarch64.tar.gz -C /Volumes/BOOT
```

(No `sudo` needed — FAT32 doesn't preserve Unix ownership/permission bits, and extracting as a regular user works fine.)

**Pi 3B+ (and possibly other models — see `lessons-learned.md`): flatten the boot file layout.** The raw tarball nests the kernel/initramfs under a `boot/` subdirectory, matching `config.txt`'s `kernel=boot/vmlinuz-rpi`. On a Pi 3B+ this doesn't boot at all — confirmed via the ACT LED's 7-flash "kernel not found" error code. Fix, before ever booting the card:

```sh
mv /Volumes/BOOT/boot/* /Volumes/BOOT/
rmdir /Volumes/BOOT/boot
sed -i '' 's#boot/vmlinuz-rpi#vmlinuz-rpi#; s#boot/initramfs-rpi#initramfs-rpi#' /Volumes/BOOT/config.txt
```

**Copy this repo's `apks-extra/` onto the card too**, for a fully offline `setup-alpine` disk install in step 6 (Alpine's own tarball doesn't ship everything `setup-disk` needs — see `lessons-learned.md`, "Offline package vendoring"):

```sh
cp -r apks-extra /Volumes/BOOT/
```

---

## 4. Build and drop the apkovl onto the same card

Same-LAN (router/switch in between), DHCP:

```sh
sh build-apkovl.sh ~/.ssh/id_ed25519.pub /Volumes/BOOT
```

Direct cable, no DHCP server on the link — bake in a static IP instead:

```sh
sh build-apkovl.sh ~/.ssh/id_ed25519.pub /Volumes/BOOT 169.254.100.1 255.255.0.0
```

For the direct-cable case, also give your machine's own Ethernet adapter a compatible address on the same link, e.g.:

```sh
sudo networksetup -setmanual "<your Ethernet adapter name>" 169.254.100.2 255.255.0.0 169.254.100.2
```

(Find the adapter name via `networksetup -listallhardwareports`, filtering out Wi-Fi/Thunderbolt-Bridge/virtual entries.)

---

## 5. Eject, boot, SSH in

```sh
diskutil eject /dev/disk4
```

Insert into the Pi, power it on. Give it a minute or two, then:

- DHCP case: find its lease (router admin page, or `arp -a`), then `ssh root@<dhcp-ip>`
- Static-IP case: `ssh root@169.254.100.1` (or whatever you chose)

Should work with no password — the apkovl already authorized your key.

---

## 6. Run setup-alpine (fully CLI-automated, no interactive session needed)

`setup-alpine` supports a non-interactive answerfile mode that covers every step, including the disk install — no monitor/keyboard, no interactive SSH session required. This is where the real hostname gets set (`build-apkovl.sh` deliberately leaves it as `localhost` for the transient first-boot session — see step 4).

All of this runs over the SSH session from step 5. First, make the local package repos survive `setup-disk` unmounting the boot media to repartition it (they otherwise vanish mid-install — see `lessons-learned.md`):

```sh
ssh root@<pi-ip> "sh /root/offline-install-prep.sh"
```

(`offline-install-prep.sh` is baked into the apkovl automatically by `build-apkovl.sh` — no separate copy needed.)

Then build and copy an answerfile (from your dev machine):

```sh
sh build-answerfile.sh <hostname> . /dev/mmcblk0
scp answerfile root@<pi-ip>:/root/answerfile
```

Then run the install itself, **detached** (`nohup` + background) rather than as a plain foreground SSH command — a long-running install tied directly to the SSH session is fragile against any transient link drop (see `lessons-learned.md`, "Hardware reliability"):

```sh
ssh root@<pi-ip> "nohup sh -c 'yes | setup-alpine -e -f /root/answerfile' > /root/setup-alpine.log 2>&1 < /dev/null &"
```

`-e` empties the root password (the one prompt the answerfile itself can't cover — this repo is key-only login by design). `yes` answers `setup-disk`'s unavoidable erase-confirmation prompt(s).

Poll for completion (reconnecting is fine even if the link drops mid-install — the process survives independently once detached):

```sh
ssh root@<pi-ip> "pgrep -f 'setup-alpine -e -f' || tail -20 /root/setup-alpine.log"
```

Look for `Installation is complete. Please reboot.` at the end of the log, then:

```sh
ssh root@<pi-ip> "reboot"
```

You now have a persistent, headless, SSH-accessible Alpine install — hand off to your project's own provisioning script from here. (Prefer to do this by hand, interactively? Plain `setup-alpine` with no flags still works exactly as before — the automated path above is an addition, not a replacement.)

---

## Caveats

- Confirmed end-to-end on a Pi 3B+ via the direct-cable static-IP path (2026-08-01). The DHCP/same-LAN path and Pi 4/5 are believed to work the same way but not yet directly tested — see `lessons-learned.md`.
- **Internet access is needed exactly once, on the machine flashing the card — never on the Pi itself, and never after step 3.** `apks-extra/` (step 3) exists specifically so step 6's disk install works with zero internet access on either machine. The resulting installed system doesn't need internet for headless SSH access at all, over Ethernet or AP.
- Initial headless access (steps 5–6) depends on eth0 for DHCP or a direct static link. Boards with no built-in ethernet (e.g. Pi Zero W) need a different apkovl with WiFi client credentials pre-baked in — not covered here yet. WiFi AP mode (the Pi hosting its own access point) is also not yet covered — see `lessons-learned.md`.
