# minimal_pi

Reusable base for getting a Raspberry Pi to a **minimal, headless, SSH-accessible** state — the layer every project-specific provisioning script (app packages, radio config, whatever) builds on top of, factored out so it's solved once instead of once per project.

Extracted from [`mobile_aprs_gateway`](../mobile_aprs_gateway)'s provisioning work, on the observation that "get a blank SD card to headless SSH" has nothing to do with what application eventually runs on the device.

---

## Scope — what belongs here vs. not

**Belongs here:** anything true regardless of the app that ends up running — flashing the OS image, first-boot SSH access, getting from a diskless RAM-boot to a persistent installed system.

**Does not belong here:** installing app packages, application-specific network topology (APRS's dual-radio AP+uplink, this or that daemon's config), anything that varies per project. That stays in each consuming project's own `provisioning/`.

The dividing line, concretely: this repo gets you to a `root@<pi-ip>` shell on a real installed system. What happens after that first SSH session is every project's own business.

---

## Layout

```
minimal_pi/
└── alpine/          # Alpine Linux — the only distro covered so far
    ├── build-apkovl.sh          # first-boot overlay: SSH key + eth0 dhcp/static
    ├── flashing-base-alpine.md  # flash procedure, image download through setup-alpine
    └── lessons-learned.md       # hard-won operational notes, including open/unresolved issues
```

More distro folders (e.g. `raspios/`) can be added later if a project needs one — no shared code between them is assumed or forced.

---

## Status

**Ethernet path confirmed end-to-end on Pi 3B+ (2026-08-01).** Blank SD card → headless first-boot SSH → fully CLI-automated `setup-alpine` disk install → persistent, disk-booted, SSH-accessible Alpine system, with zero interactive steps and zero internet access needed at flash-time. See `alpine/lessons-learned.md` for the full story, including four real bugs found and fixed along the way.

**Not yet done:** WiFi AP mode (the "OR AP" half of milestone 1 — Pi hosting its own access point for headless access with no Ethernet available), and validation on Pi 4/5 (the boot-layout fix so far is confirmed for Pi 3B+ specifically).

---

## Using this in another project

```sh
git submodule add <this-repo-url> vendor/minimal_pi
```

(Path convention: sits under a project's own `vendor/` alongside any other pinned external dependency, same as e.g. `w7gvr_hf_skimmer`'s `vendor/wsjtx`.)
