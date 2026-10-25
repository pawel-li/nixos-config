# nixos-config

NixOS configuration for my laptop (GNOME, Navidrome, NixOS 26.05). The laptop
follows the `main` branch: push a change here and the laptop applies it on its
own within about 5 minutes.

```
flake.nix                      entry point: nixosConfigurations.laptop
hosts/laptop/configuration.nix everything about the laptop: desktop, user, packages, Navidrome
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

## Music (Navidrome)

Copy music into `~/Music` and open <http://localhost:4533>. The first visit
asks you to create the admin account. New files show up on their own, usually
within seconds; no rescan needed.

It listens only on the laptop itself. To reach it from a phone on your home
Wi-Fi, add `settings.Address = "0.0.0.0";` and `openFirewall = true;` to
`services.navidrome` in `hosts/laptop/configuration.nix`. Do that only after
creating the admin account, because until then anyone who opens the page can
create it. It also makes the login page reachable on every network the laptop
joins, cafés included.

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
