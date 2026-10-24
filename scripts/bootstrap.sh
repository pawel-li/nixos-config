#!/usr/bin/env bash
# One-time setup on the freshly installed laptop. Run it from the installed
# NixOS desktop (not the USB installer), connected to the internet:
#
#   nix-shell -p git gh curl --run 'bash <(curl -fsSL https://raw.githubusercontent.com/pawel-li/nixos-config/main/scripts/bootstrap.sh)'
#
# It saves this laptop's hardware config to the repo, pushes it, and switches
# the system to the flake. After that the laptop follows GitHub on its own.
set -euo pipefail

REPO=pawel-li/nixos-config
HOST=laptop
USER_NAME=pawel
DIR=$HOME/nixos-config
export NIX_CONFIG="experimental-features = nix-command flakes"

say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mError: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -un)" = "$USER_NAME" ] ||
  die "run this as '$USER_NAME', the user the config declares. You are '$(id -un)'."
[ -d /sys/firmware/efi ] ||
  die "this laptop booted in legacy BIOS mode, but the config uses systemd-boot, which needs UEFI. Reinstall with the USB booted in UEFI mode."
[ -f /etc/nixos/hardware-configuration.nix ] ||
  die "/etc/nixos/hardware-configuration.nix is missing. Run this on the installed system, not the USB."
git ls-remote "https://github.com/$REPO" HEAD >/dev/null 2>&1 ||
  die "can't reach github.com. Connect to the internet first."

say "Signing in to GitHub (needed to push this laptop's hardware config)"
gh auth status >/dev/null 2>&1 || gh auth login --hostname github.com --git-protocol https --web
gh auth setup-git

say "Getting $REPO into $DIR"
if [ -d "$DIR/.git" ]; then
  git -C "$DIR" pull --ff-only
else
  git clone "https://github.com/$REPO" "$DIR"
fi
cd "$DIR"

if ! git config user.email >/dev/null; then
  login=$(gh api user --jq .login)
  id=$(gh api user --jq .id)
  git config user.name "$login"
  git config user.email "$id+$login@users.noreply.github.com"
fi

say "Copying this laptop's hardware config"
cp /etc/nixos/hardware-configuration.nix "hosts/$HOST/hardware-configuration.nix"

# The installer writes disk-encryption (and sometimes boot partition) settings
# into its own configuration.nix instead of hardware-configuration.nix.
# Carry those over so the laptop can still unlock and boot.
extras=$(awk '
  capturing {
    print
    depth += gsub(/[{]/, "{") - gsub(/[}]/, "}")
    if (depth <= 0) capturing = 0
    next
  }
  /^[[:space:]]*boot\.(initrd\.(luks|secrets)|loader\.efi\.efiSysMountPoint)/ {
    print
    depth = gsub(/[{]/, "{") - gsub(/[}]/, "}")
    capturing = (depth > 0)
  }
' /etc/nixos/configuration.nix)
if [ -n "$extras" ]; then
  {
    echo "# Copied from the installer's /etc/nixos/configuration.nix by scripts/bootstrap.sh."
    echo "{ ... }:"
    echo
    echo "{"
    echo "$extras"
    echo "}"
  } >"hosts/$HOST/installer-extras.nix"
  echo "Also carried over from the installer:"
  echo "$extras"
fi

git add -A "hosts/$HOST"

say "Test-building the system before pushing anything"
nixos-rebuild build --flake ".#$HOST"
rm -f result

if git diff --cached --quiet; then
  echo "The repo already has this laptop's hardware config."
else
  git commit -m "laptop: add hardware configuration"
  say "Pushing to GitHub"
  git push
fi

rev=$(git rev-parse HEAD)
say "Switching the system to the flake (commit ${rev:0:7})"
sudo nixos-rebuild switch --flake "github:$REPO/$rev#$HOST"

say "Done"
cat <<EOF
This laptop now follows https://github.com/$REPO (branch main).
Push a change and it is applied here within about 5 minutes.

  Watch updates:   journalctl -fu nixos-git-deploy
  Check right now: sudo systemctl start nixos-git-deploy

Reboot once now so the new hostname and everything else start fresh.
EOF
