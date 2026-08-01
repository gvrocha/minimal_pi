# STATUS

Current-state tracker. See `alpine/lessons-learned.md` for the full narrative behind each item.

## Milestone 1 — Pi 3B+ headless SSH via Ethernet OR AP

- [x] **Ethernet path — done as of 2026-08-01.** Blank SD card → headless first-boot SSH (apkovl) → fully CLI-automated `setup-alpine` disk install → persistent, disk-booted, SSH-accessible Alpine 3.21.6 system. Zero interactive steps, zero internet access needed at flash-time on either machine. Confirmed on real Pi 3B+ hardware, direct-cable static-IP topology.
- [ ] **AP path — not started.** Pi hosting its own WiFi access point for headless access with no Ethernet available. No hostapd/dnsmasq config exists yet. See sibling `mobile_aprs_gateway` project for a Pi 5 precedent (never fully debugged) and a real Alpine nftables gotcha to carry over.

## Confirmed working

- Alpine headless flashing procedure (`alpine/flashing-base-alpine.md`), Pi 3B+, aarch64 tarball, direct-cable static IP.
- `build-apkovl.sh` — first-boot SSH overlay, 4 real bugs found and fixed.
- `build-answerfile.sh` + `offline-install-prep.sh` — full CLI automation of `setup-alpine`'s disk install, no internet needed (backed by vendored `apks-extra/` local repo, self-signed).

## Open / not yet exercised

- DHCP/same-LAN path (only direct-cable static IP tested so far).
- Pi 4 / Pi 5 — the flat-boot-layout fix is confirmed for Pi 3B+ only. A Pi 4 is available for testing next.
- Root cause of Ethernet link flapping under I/O load during `setup-disk` — power-supply undervoltage is the leading hypothesis, not confirmed with an actual voltage measurement. Didn't end up blocking anything once long installs run detached (`nohup`) from the live SSH session, but worth resolving before calling the hardware side fully solid.
- Full bootstrap → provisioning handoff to a downstream project (out of scope for `minimal_pi` itself, but worth a sanity-check end-to-end run from some consuming project).

## Next up

AP-mode design (hostapd + dnsmasq on the Pi 3B+'s built-in WiFi) — see `alpine/lessons-learned.md`'s "Not yet exercised" section for starting context.
