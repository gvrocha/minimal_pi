# apks-extra — supplemental local apk repo

Packages `setup-disk -m sys` needs that Alpine's own `alpine-rpi-*-aarch64.tar.gz`
doesn't ship in its local `apks/` cache at all: `dosfstools`, `linux-rpi` (the
kernel package for the *persistent* install — distinct from the raw
`vmlinuz-rpi` file the diskless boot uses directly), `raspberrypi-bootloader`
+ `raspberrypi-bootloader-common`, and their full transitive dependency
closure (`mkinitfs`, `abuild` + its own build-time deps, firmware packages,
etc. — 26 packages total).

Without this, a fully offline (no internet, on either machine) SD-card
deployment is not possible with the stock image — see `lessons-learned.md`
("Fixed bugs" / offline package-vendoring section) for exactly how each of
these was identified and why.

## Signing

apk requires a signed index to trust a repository by default (`setup-disk`'s
own internal `apk add` calls don't pass `--allow-untrusted`, so that flag
alone doesn't solve this for the actual disk-install step — only proper
signing does). `APKINDEX.tar.gz` here is signed with a repo-specific RSA
keypair generated for this purpose; `minimal_pi-install.rsa.pub` (committed)
is the public half, baked into every apkovl by `build-apkovl.sh` so it's
trusted from first boot.

**The private half (`minimal_pi-install.rsa`) is deliberately NOT in this
repo** — a private signing key has no business in version control, even for
a low-stakes local repo like this one. It lives at `~/.ssh/minimal_pi-install.rsa`
on Guilherme's machine; check there first if you need to re-sign this index
(e.g. adding a package, or bumping versions for a new Alpine release). If
it's ever lost, regenerating is harmless: generate a new keypair, re-sign,
replace the `.pub` file here, and existing already-deployed devices are
unaffected (this key is only ever used during provisioning, never at
runtime).

## Regenerating (e.g. for a new Alpine release)

Rough process — see `lessons-learned.md` for the full narrative and why each
step is what it is:

1. Diff the target release's `main` APKINDEX against what's already in the
   stock `alpine/apks/aarch64/` (from the official tarball) to find what's
   still missing for `dosfstools` + `linux-rpi` + `raspberrypi-bootloader`'s
   full dependency closure.
2. Download the missing `.apk` files from `dl-cdn.alpinelinux.org`.
3. `apk index -o APKINDEX.tar.gz --rewrite-arch aarch64 *.apk` (run on an
   aarch64 Alpine system — e.g. the Pi itself, over its first-boot SSH
   session; apk-tools ships there already).
4. Sign it with `abuild-sign` (or replicate its `do_sign()` steps manually —
   see `lessons-learned.md`; note macOS's `tar` and the Pi's busybox `tar`
   both need different flags than `abuild-sign`'s own GNU-tar-flavored
   invocation expects).
5. Copy the new `APKINDEX.tar.gz` back into `aarch64/` here.
