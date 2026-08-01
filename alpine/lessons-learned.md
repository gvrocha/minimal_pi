# Lessons learned — Alpine headless flashing

Distilled from a real flash session on `mobile_aprs_gateway` (2026-07-04), attempting exactly the procedure in `flashing-base-alpine.md`. Keeping the operational lessons here even though **that session ended without a confirmed successful headless boot on a fresh card** — the open question at the end is exactly the next thing to resolve, not a solved problem being written up after the fact.

---

## Confirmed / solid

- **One aarch64 tarball covers Pi 2 (v1.2+), 3, Zero 2 W, CM3, 4/400/CM4, and 5/500/CM5.** Verified by listing the DTBs actually shipped inside `alpine-rpi-3.21.6-aarch64.tar.gz` — no per-model download needed within that family.
- **Card size matters a lot for iteration speed.** Erasing/formatting a 128GB card took **7m43s** for the `eraseDisk` step alone (FAT32 format time scales with capacity — more clusters/FAT entries to initialize). Actual usage is ~100MB of Alpine boot files + a <1KB apkovl, so an 8–16GB card is plenty and cuts iteration time dramatically if you're re-flashing repeatedly while debugging.
- **A direct machine↔Pi Ethernet link has no DHCP server** — plain DHCP in the apkovl won't get an address at all on that topology. Bake in a static IP on both ends instead (see `flashing-base-alpine.md` step 4). The `169.254.0.0/16` link-local range is a reasonable default since it needs no coordination with any other network.
- **macOS auto-recreates `.fseventsd`/`.Spotlight-V100`** on every mount of the FAT32 boot partition. Harmless in practice, but if you want a truly vanilla card for isolation testing, `.fseventsd` deletes with a plain `rm -rf`; `.Spotlight-V100` resists even `mdutil -i off` / `mdutil -X` and needs `sudo rm -rf`.
- **Always eject properly (`diskutil eject`) before pulling the card.** An improper pull was one of several hypotheses chased down during debugging (ruled out via `fsck_msdos` clean check, but not worth risking again).

---

## Suspected but NOT confirmed — the actual open problem

The session hit a fresh card that showed no sign of life (no Ethernet lights, flat ~2W power draw suggesting it wasn't even actively decompressing/booting) after following steps 1–5. Two things were found and changed, **neither confirmed to have fixed it**:

1. **Boot partition file layout.** The raw Alpine tarball extracts with the kernel/initramfs nested under a `boot/` subdirectory, and `config.txt` correctly points at `kernel=boot/vmlinuz-rpi` to match. A separately-provisioned, already-working Alpine Pi's boot partition instead has these files flat at the FAT32 root (`kernel=vmlinuz-rpi`, no `boot/` nesting) — presumably a result of `setup-alpine`/`setup-disk` reorganizing things, or of package install hooks syncing files post-install, not a property of the raw first-boot tarball itself. Flattened the fresh card to match (`mv /Volumes/BOOT/boot/* /Volumes/BOOT/`, edit `config.txt` accordingly) as a **plausible but unconfirmed** fix — Pi firmware is generally documented to support subdirectory kernel paths, so this wasn't a guaranteed smoking gun, just the one clear structural difference found between a working and non-working card.
2. **Whether Alpine's first-boot process even does a DHCP round-trip before resolving the apkovl-search hostname**, or just reads the shipped default `/etc/hostname` ("localhost") with no network step — not established either way. Doesn't change anything for the static-IP case (no DHCP delay regardless), but matters for reasoning about DHCP-case timing.

The session's own next-step plan, for whoever picks this up: reduce to the simplest possible test first (raw vanilla tarball, zero customization — not even the apkovl) and confirm *something* boots and shows an Ethernet link light at all, before reintroducing the apkovl and the layout fix as separate, isolated variables. Real console access (monitor/keyboard, or a serial console) was flagged as the highest-value unblock if available — most of the remaining hypotheses are hard to distinguish without seeing actual boot output.

---

## Not yet exercised

- `setup-alpine` / `setup-disk -m sys` itself — the session never got far enough to reach this step on the fresh card.
- The full bootstrap → rsync → configure handoff to a project-specific provisioning script.
