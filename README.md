# nixos-config

NixOS configuration for my laptop (GNOME, NixOS 26.05) that also serves Glance,
Immich, Jellyfin, Navidrome, Paperless-ngx, JobOps and Coder to the home network
and sends PDFs to a reMarkable tablet. The laptop follows
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

Open them from any device on the home Wi-Fi (phone, Mac, the laptop itself).
They answer nothing else: not the internet, not a device on a network cable.
If the laptop ever joins another Wi-Fi network, they'd answer there too, so
it should stay at home.

| Service | Address | What for | First time |
| ------- | ------- | -------- | ---------- |
| Glance | <http://laptop.local> (or `:8080`) | start page: links to the others and shows if they're up | nothing to do |
| Immich | <http://laptop.local:2283> | photos and videos, backed up from the phone | the page asks you to create the admin account; then install the Immich app on the phone and sign in with server `http://laptop.local:2283` |
| Jellyfin | <http://laptop.local:8096> | films, series, music | the page walks you through creating the admin account; add `/home/pawel/Videos` and `/home/pawel/Music` as libraries |
| Navidrome | <http://laptop.local:4533> | music | the page asks you to create the admin account |
| Paperless-ngx | <http://laptop.local:28981> | scanned documents and PDFs, searchable (Polish and English text) | on the laptop run `sudo paperless-manage createsuperuser` once and pick a username and password |
| JobOps | <http://laptop.local:3001> | job search: finds offers, scores them against your CV, writes a CV for each one and tracks your applications | the page asks you to create your account, pick an AI provider and upload your CV; see [JobOps](#jobops) |
| Coder | <http://laptop.local:3000> | development machines on the laptop that you or an AI agent start on demand | the page asks you to create the admin account; see [Coder](#coder) |

Do the first-time steps right away: until Immich, Jellyfin, Navidrome, JobOps
and Coder have an admin account, anyone on the Wi-Fi who opens the page can
create it.

- **Music and videos:** copy them into `~/Music` and `~/Videos`. Navidrome and
  Jellyfin see only those two folders, read-only. Navidrome picks up new files
  within seconds; Jellyfin on its next library scan (or "Scan All Libraries"
  in its dashboard).
- **Photos:** the Immich app on the phone backs photos up to
  `/var/lib/immich`. To show the ones already in `~/Pictures` as well, add
  `/home/pawel/Pictures` in Immich under Administration → External Libraries;
  Immich sees only that folder, read-only.
- **Documents:** drag files onto the Paperless page, or use a Paperless app on
  the phone. Its files live in `/var/lib/paperless`.
- **A device can't open `laptop.local`** (some Android browsers): use the
  laptop's IP address instead, from GNOME Settings → Wi-Fi → the gear icon
  next to your network.

### JobOps

JobOps runs in Docker from the project's own image and updates itself to the
newest release every Monday. Its database and the CVs it writes live in
`/var/lib/job-ops/data`. Settings that can't be made on the page go in
`/var/lib/job-ops/env`, one `NAME=value` per line: edit it with
`sudoedit /var/lib/job-ops/env`, then run `sudo systemctl restart docker-job-ops`.

- **AI:** OpenRouter, OpenAI and Gemini take their API key right on the page.
  For Claude, add `ANTHROPIC_API_KEY=…` to the file, or use your Claude
  subscription: run `claude setup-token` wherever you have Claude Code (the
  Mac, say) and add `CLAUDE_CODE_OAUTH_TOKEN=…`. Then pick Claude CLI as the
  provider in JobOps.
- **Gmail** (JobOps then follows replies from recruiters and updates each
  application): create a Google OAuth client as the
  [Gmail guide](https://jobops.dakheera47.com/docs/getting-started/gmail-oauth-setup)
  shows, with redirect URI `http://localhost:3001/oauth/gmail/callback`. Add
  `GMAIL_OAUTH_CLIENT_ID=…` and `GMAIL_OAUTH_CLIENT_SECRET=…` to the file and
  restart. Then, on the laptop itself, open <http://localhost:3001>, go to
  Tracking Inbox and connect Gmail. Google takes a plain-http address only for
  `localhost`, so this one step has to happen on the laptop.

### Coder

Coder runs development machines ("workspaces") from templates, for you or
for an AI agent on the home Wi-Fi.

- **First workspace:** Templates → Create Template → Docker. Workspaces run in
  containers here on the laptop. The cloud templates (AWS, Google Cloud, …)
  won't work: a machine in the cloud has to reach Coder, and Coder answers
  only on the home Wi-Fi.
- **Agents:** on the Mac or the laptop, sign in once with
  `coder login http://laptop.local:3000`. Then the agent can use
  `coder create`, `coder ssh` and the rest. For Claude Code,
  `claude mcp add coder -- coder exp mcp server` gives it tools to create
  workspaces and run commands in them. Agents running in the cloud (Claude
  Code on the web, say) can't reach Coder.
- Coder downloads Terraform, which it uses to build workspaces, the first time
  it needs it.

### reMarkable

Drop a PDF or EPUB into `~/reMarkable` on the laptop and it shows up on the
tablet a moment later. Sent files move to `~/reMarkable/Sent`. It goes through
reMarkable's free cloud sync, so you don't need a Connect subscription. Without
Connect, files you haven't opened in 50 days drop out of the cloud, but they
stay on the tablet.

- **Sign in once:** in a terminal on the laptop run `rmapi`, open
  <https://my.remarkable.com/device/browser/connect>, log in and type the code
  it shows into the terminal. Then type `exit`. Files that were already waiting
  go out within the hour, or right away after
  `sudo systemctl restart remarkable-upload`.
- **A file stays in `~/reMarkable`:** `journalctl -u remarkable-upload` says
  why. A file isn't sent if the tablet already has a document with the same
  name. Rename the file and it goes out.
- **From the Mac or phone:** the free reMarkable apps
  (<https://remarkable.com/download>) take files too. With no app at all,
  connect the tablet by USB, turn on the USB web interface under Settings →
  Storage and open <http://10.11.99.1>.

### Adding a service

Every service in `hosts/laptop/configuration.nix` is meant for the home
Wi-Fi. When you add one, make it listen on every address, add its port to
`wifiTcpPorts` near the top of that file, then add it to the Glance page.
Leave its `openFirewall` off: that would open the port on every network, cable
and IPv6 included. Anything not in the list stays blocked by the firewall.
Docker containers get the same treatment only with `networks = [ "host" ]`,
as JobOps has: a port published the usual Docker way gets past the firewall.

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
`nixos-26.05` commit (and Immich to the newest in NixOS unstable) and pushes
`flake.lock`, so the laptop gets security fixes without you doing anything. Run it by hand from the Actions tab any time.

When a new NixOS release is out (26.11 in late November), change
`nixos-26.05` in `flake.nix`, push, and the laptop
upgrades. Leave `system.stateVersion` as it is. With 26.11, also delete the
`nixpkgs-unstable` input and the `services.immich.package` line in
`flake.nix`: Immich only comes from unstable because 26.05's version has known
security holes.
