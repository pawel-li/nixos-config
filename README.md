# nixos-config

NixOS configuration for my laptop (GNOME, NixOS 26.05) that also serves Glance,
Jellyfin, Navidrome and Paperless-ngx to the home network. The laptop follows
the `main` branch: push a change here and the laptop applies it on its own
within about 5 minutes.

```
flake.nix                      entry point: nixosConfigurations.laptop
hosts/laptop/configuration.nix everything about the laptop: desktop, user, packages, services
hosts/laptop/hardware-configuration.nix   disks and drivers, generated on the laptop
modules/git-deploy.nix         the timer that pulls new commits and switches to them
scripts/bootstrap.sh           moves an installed laptop onto this repo (safe to re-run)
.github/workflows/             checks every push; bumps nixpkgs weekly
```

## Laptop already has NixOS? Move it to the latest version

Whether it has a fresh install from the USB or an earlier try of this setup,
log in as `pawel`, connect to the internet, open a terminal and run:

```bash
nix-shell -p git gh curl --run 'bash <(curl -fsSL https://raw.githubusercontent.com/pawel-li/nixos-config/main/scripts/bootstrap.sh)'
```

It asks you to sign in to GitHub in the browser (use the account that owns
this repo), saves the laptop's hardware config here and switches the laptop to
the latest `main`. Reboot when it says Done. From then on the laptop updates
itself from GitHub and you don't need this command again. If an earlier run
stopped halfway, just run it again: it picks up where it stopped.

## Installing on the laptop

1. **Boot the USB.** In the laptop's BIOS/UEFI settings, turn off Secure Boot
   and make sure it boots in UEFI mode (not "Legacy" or "CSM"). Then power on
   and press the boot-menu key (usually F12, F2, F10 or Esc) and pick the USB.
2. **Run the installer** that opens on the desktop:
   - Location: Europe/Warsaw. Keyboard: Polish.
   - User: username **`pawel`** (the config declares this exact user).
   - Desktop: GNOME. Tick "Allow unfree software".
   - Partitions: "Erase disk". Encryption is optional and supported.
   - Install, then reboot and remove the USB.
3. **Hand the laptop over to this repo.** Log in, connect to Wi-Fi, open a
   terminal and run:

   ```bash
   nix-shell -p git gh curl --run 'bash <(curl -fsSL https://raw.githubusercontent.com/pawel-li/nixos-config/main/scripts/bootstrap.sh)'
   ```

   It asks you to sign in to GitHub in the browser, saves the laptop's
   hardware config to this repo, and switches the system to the flake.
   Reboot when it says Done.

## Services

Open them from any device on the home network (phone, Mac, the laptop itself):

| Service | Address | What for | First time |
| ------- | ------- | -------- | ---------- |
| Glance | <http://laptop.local:8080> | start page: links to the others and shows if they're up | nothing to do |
| Jellyfin | <http://laptop.local:8096> | films, series, music | the page walks you through creating the admin account; add `/home/pawel/Videos` and `/home/pawel/Music` as libraries |
| Navidrome | <http://laptop.local:4533> | music | the page asks you to create the admin account |
| Paperless-ngx | <http://laptop.local:28981> | scanned documents and PDFs, searchable (Polish and English text) | on the laptop run `sudo paperless-manage createsuperuser` once and pick a username and password |

Do the first-time steps right away: until Jellyfin and Navidrome have an admin
account, anyone on the network who opens the page can create it.

- **Music and videos:** copy them into `~/Music` and `~/Videos`. Navidrome and
  Jellyfin see only those two folders, read-only. Navidrome picks up new files
  within seconds; Jellyfin on its next library scan (or "Scan All Libraries"
  in its dashboard).
- **Documents:** drag files onto the Paperless page, or use a Paperless app on
  the phone. Its files live in `/var/lib/paperless`.
- **A device can't open `laptop.local`** (some Android browsers): use the
  laptop's IP address instead, from GNOME Settings → Wi-Fi → the gear icon
  next to your network.

### Adding a service

Every service in `hosts/laptop/configuration.nix` is meant for the whole home
network. When you add one, make it listen on every address and open its port
(most NixOS services have `openFirewall = true;` for that), then add it to the
Glance page. Anything not opened that way stays blocked by the firewall. The
ports are open on every network the laptop joins, so log-ins matter.

## Always on

The laptop never goes to sleep, so the services are reachable around the
clock: closing the lid does nothing, GNOME's automatic suspend is off (at the
login screen too), and suspend and hibernate are switched off altogether. No
one needs to be logged in. The screen still turns off when idle, and the power
button asks what to do. In a power cut it keeps running on battery and shuts
down cleanly when the battery is nearly empty; press the power button to start
it again.

Plugged in all the time, the battery sits at 100%, which wears it out faster.
If GNOME Settings → Power offers a charge limit ("Preserve Battery Health"),
turn it on.

## Day-to-day

- **Change something:** edit `hosts/laptop/configuration.nix` (from the Mac or
  from `~/nixos-config` on the laptop), commit, push. The laptop switches to it
  within about 5 minutes.
- **Apply right away:** `sudo systemctl start nixos-git-deploy`
- **See what happened:** `journalctl -u nixos-git-deploy`
- **Pause updates:** `sudo systemctl stop nixos-git-deploy.timer`
  (it comes back on the next reboot)

GitHub is the source of truth. A local `nixos-rebuild switch` of changes that
are not pushed gets replaced by `main` at the next check.

**If a push breaks the build,** the laptop keeps running its current system
and skips that commit. Push a fix and it moves on.

**If a push builds but the result is bad,** pick an older generation from the
boot menu to get going, then `git revert` the commit and push. Otherwise the
laptop switches back to the bad commit at the next check.

Kernel and driver updates take effect after a reboot. The laptop never reboots
on its own.

## Updates

`update-lock.yml` runs every Monday, moves nixpkgs to the newest
`nixos-26.05` commit and pushes `flake.lock`, so the laptop gets security fixes
without you doing anything. Run it by hand from the Actions tab any time.

When a new NixOS release is out (26.11 in late November), change
`nixos-26.05` in `flake.nix`, push, and the laptop
upgrades. Leave `system.stateVersion` as it is.
