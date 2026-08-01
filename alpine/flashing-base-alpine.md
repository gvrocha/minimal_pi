# Flashing a blank-slate Alpine SD card

Gets a truly blank SD card to a headless, SSH-accessible, persistently-installed Alpine system. Stops there — installing anything project-specific happens afterward, over the SSH session this leaves you with.

Primary instructions are for a Mac. Windows/Linux notes are called out briefly where the steps differ.

**Status:** not yet confirmed working end-to-end on a truly fresh card — see `lessons-learned.md` before relying on this for a real deployment.

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
diskutil unmountDisk /dev/disk4
sudo diskutil eraseDisk MS-DOS BOOT MBRFormat /dev/disk4
```

This gives a single FAT32 partition, MBR scheme, mounted at `/Volumes/BOOT`. That's the whole layout needed up front — the Pi boots this diskless (running from RAM) at first, so there's no need to pre-reserve space for a root partition. `setup-disk` (step 6) repartitions the card safely later while the OS is running entirely in memory.

**Windows:** format the whole card FAT32/MBR via Disk Management or `diskpart`, then extract the tarball with 7-Zip.

**Linux:** partition with `fdisk` (single partition, type `c` W95 FAT32 LBA), then `mkfs.vfat -F32 /dev/sdX1`.

Same end state on all three: one FAT32 partition spanning the card.

---

## 3. Extract the Alpine tarball onto the card

```sh
tar xzf alpine-rpi-3.21.6-aarch64.tar.gz -C /Volumes/BOOT
```

(No `sudo` needed — FAT32 doesn't preserve Unix ownership/permission bits, and extracting as a regular user works fine.)

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

## 6. Run setup-alpine (interactive — not scriptable)

```sh
setup-alpine
```

Answer the prompts: keyboard layout, hostname (pick the real one now — this is where it should actually be set, not baked into the apkovl), network interface (already up — accept), root password (set one, or leave blank for key-only login), timezone/NTP (choose "none" if this device will discipline its clock some other way, e.g. GPS), mirror (pick any), and finally:

- **Which disk(s) would you like to use?** → `mmcblk0`
- **How would you like to use it?** → `sys`

It'll confirm it's about to erase the disk — say yes. This is safe: you're running from a RAM-resident diskless boot, so wiping the SD card underneath it doesn't touch the running system. It repartitions into boot (FAT32) + root (ext4), and carries forward the hostname/sshd/authorized_keys config from step 4.

Reboot when it finishes. You now have a persistent, headless, SSH-accessible Alpine install — hand off to your project's own provisioning script from here.

---

## Caveats

- This whole procedure is based on documented Alpine RPi install flow and one real (inconclusive) flash session — not yet verified end-to-end on a truly blank card. See `lessons-learned.md` for exactly where that stands.
- Initial headless access (steps 5–6) depends on eth0 for DHCP or a direct static link. Boards with no built-in ethernet (e.g. Pi Zero W) need a different apkovl with WiFi client credentials pre-baked in — not covered here yet.
