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

**Not yet confirmed end-to-end.** The Alpine flow here is carried over from a real flash session on `mobile_aprs_gateway` that ended without a confirmed successful headless boot on a fresh card — see `alpine/lessons-learned.md` for exactly where that session left off. Treat this as "best current understanding, actively being hardened," not a proven recipe, until a session closes that loop.

---

## Using this in another project

```sh
git submodule add <this-repo-url> vendor/minimal_pi
```

(Path convention: sits under a project's own `vendor/` alongside any other pinned external dependency, same as e.g. `w7gvr_hf_skimmer`'s `vendor/wsjtx`.)
