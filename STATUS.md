# STATUS

Current-state tracker. See `alpine/lessons-learned.md` for the full narrative behind each item.

## Milestone 1 — Pi 3B+ headless SSH via Ethernet, single script

**Re-scoped 2026-08-01** (was "Ethernet OR AP" — split into two milestones so Ethernet can be called done on its own merits, with WiFi AP as a separate follow-on milestone rather than blocking this one).

Done when a single script (or, if needed, a matched pair — one run on the laptop to build the SD card, one run on the Pi) takes a blank SD card to a headless, SSH-accessible, persistent Alpine install over Ethernet, with no other manual steps.

- [x] **Steps individually proven — done as of 2026-08-01.** Blank SD card → headless first-boot SSH (apkovl) → fully CLI-automated `setup-alpine` disk install → persistent, disk-booted, SSH-accessible Alpine 3.21.6 system. Zero interactive steps, zero internet access needed at flash-time on either machine. Confirmed on real Pi 3B+ hardware, direct-cable static-IP topology.
- [x] **Single script — confirmed working end-to-end as of 2026-08-01.** `alpine/flash-and-install.sh` collapses all of `flashing-base-alpine.md`'s steps into one Mac-side call (must be run with `bash`, not `sh` — see script header): partitions the card, extracts the tarball, flattens `boot/`, copies `apks-extra/`, builds the apkovl, ejects, configures the Mac's own interface (with an automatic fix for the documented default-route-hijack gotcha), waits for the Pi over SSH, and drives `offline-install-prep.sh` → `build-answerfile.sh` → detached `setup-alpine` → reboot, retrying through the documented Ethernet-link-flapping issue at every remote step. Run end-to-end against real Pi 3B+ hardware (hostname `minpi`, 125GB card) — three real bugs found and fixed along the way across that run and a follow-up (adding an optional secondary-pubkey argument), including a host-key-pinning issue that would have hit every subsequent re-flash to the same static IP (see `lessons-learned.md`). **Milestone 1 is done.**

## Milestone 2 — Add WiFi AP option, single script

Same bar as milestone 1 (one script, or laptop+Pi pair), extended so the Pi can host its own WiFi access point for headless SSH access when no Ethernet is available — no separate router/switch needed.

- [ ] **AP config — in progress.** `hostapd`, `dnsmasq`, `dnsmasq-common` resolved, vendored into `apks-extra/`, and installed successfully on the live test Pi (2026-08-01) — a real signing-process bug was found and fixed along the way (see `lessons-learned.md`). hostapd.conf/dnsmasq.conf design, apkovl wiring, and a live end-to-end AP test are still outstanding — paused mid-session on a recurring Ethernet-link-flapping hardware issue (see "Known gaps" below), not yet resumed. See sibling `mobile_aprs_gateway` project for a Pi 5 precedent (never fully debugged) and a real Alpine nftables gotcha to carry over.
- [ ] **Wire into milestone 1's script(s) as a second network-mode option** — depends on milestone 1's script existing first.

## Confirmed working

- Alpine headless flashing procedure (`alpine/flashing-base-alpine.md`), Pi 3B+, aarch64 tarball, direct-cable static IP.
- `build-apkovl.sh` — first-boot SSH overlay, 4 real bugs found and fixed.
- `build-answerfile.sh` + `offline-install-prep.sh` — full CLI automation of `setup-alpine`'s disk install, no internet needed (backed by vendored `apks-extra/` local repo, self-signed).

## Known gaps

- **`/etc/apk/repositories` ships with both lines commented out on the resulting installed system, but — correction, 2026-08-01 — the paths they point at (`/root/apks-cache`, `/root/apks-extra`) do survive post-reboot.** Earlier text here claimed these were transient tmpfs paths that vanish after reboot; that was wrong. Confirmed directly on a real persistent installed device: `setup-disk` carries `/root` (including these two directories) onto the real ext4 root, and simply uncommenting the two lines makes `apk update`/`apk add` work immediately against the local repos, no internet needed. The real remaining gap is just that they ship commented-out by default and never point at a real internet mirror — a downstream provisioning step (or the milestone-1/2 driver script itself) should either uncomment these local paths, or run `setup-apkrepos -1` / hand-write a `dl-cdn.alpinelinux.org` line, before assuming `apk add` works for anything beyond what's already vendored.

## Open / not yet exercised

- DHCP/same-LAN path (only direct-cable static IP tested so far).
- Pi 4 / Pi 5 — the flat-boot-layout fix is confirmed for Pi 3B+ only. A Pi 4 is available for testing next.
- Root cause of Ethernet link flapping under I/O load during `setup-disk` — power-supply undervoltage is the leading hypothesis, not confirmed with an actual voltage measurement. Didn't end up blocking anything once long installs run detached (`nohup`) from the live SSH session, but worth resolving before calling the hardware side fully solid.
- Full bootstrap → provisioning handoff to a downstream project (out of scope for `minimal_pi` itself, but worth a sanity-check end-to-end run from some consuming project).

## Next up

**Milestone 1 is done (2026-08-01).** Milestone 2: finish the WiFi AP path — hostapd.conf/dnsmasq.conf design, apkovl wiring, and a live end-to-end AP test are still outstanding (packages already vendored and installed on the test device). See `alpine/lessons-learned.md`'s "Not yet exercised" section for starting context.
