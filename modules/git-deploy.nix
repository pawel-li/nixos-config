# Keeps this machine on the latest commit of its GitHub repo.
#
# A timer checks the branch head every few minutes with `git ls-remote` (one
# small request, not rate limited). When it differs from the commit the running
# system was built from, it runs `nixos-rebuild switch` pinned to that commit.
# A commit that fails to build is remembered and skipped until a newer one is
# pushed, so the machine stays on its last working generation.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.nixos-git-deploy;
  currentRev = toString config.system.configurationRevision;
in
{
  options.services.nixos-git-deploy = {
    enable = lib.mkEnableOption "switching to the latest commit of the config repo on GitHub";

    repo = lib.mkOption {
      type = lib.types.str;
      example = "pawel-li/nixos-config";
      description = "GitHub repository (owner/name) holding this flake.";
    };

    branch = lib.mkOption {
      type = lib.types.str;
      default = "main";
      description = "Branch to follow.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      defaultText = lib.literalExpression "config.networking.hostName";
      description = "Name under nixosConfigurations to build.";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "5min";
      description = "Time between checks, as a systemd time span.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.nixos-git-deploy = {
      description = "Switch to the latest commit of github:${cfg.repo}";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      # This unit runs `switch` itself, so switching must not stop or restart it.
      restartIfChanged = false;
      unitConfig.X-StopOnRemoval = false;

      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "nixos-git-deploy";
      };

      environment = config.nix.envVars // { HOME = "/root"; } // config.networking.proxy.envVars;
      path = with pkgs; [ coreutils gitMinimal gnutar gzip xz config.nix.package.out ];

      script = ''
        set -euo pipefail
        current=${lib.escapeShellArg currentRev}
        failed_file=/var/lib/nixos-git-deploy/failed-rev

        if ! head=$(timeout 60 git ls-remote --exit-code https://github.com/${cfg.repo} refs/heads/${cfg.branch}); then
          echo "Can't reach GitHub, will try again later."
          exit 0
        fi
        remote=''${head%%[[:space:]]*}

        if [ "$remote" = "$current" ]; then
          echo "Up to date at $current."
          exit 0
        fi
        if [ -f "$failed_file" ] && [ "$(cat "$failed_file")" = "$remote" ]; then
          echo "$remote failed to build earlier. Waiting for a newer commit."
          exit 0
        fi

        echo "Switching from ''${current:-unknown} to $remote."
        if ${config.system.build.nixos-rebuild}/bin/nixos-rebuild switch --flake "github:${cfg.repo}/$remote#${cfg.host}"; then
          rm -f "$failed_file"
        else
          echo "$remote" > "$failed_file"
          echo "Build of $remote failed. Staying on the current system."
          exit 1
        fi
      '';
    };

    systemd.timers.nixos-git-deploy = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = cfg.interval;
        RandomizedDelaySec = "30s";
      };
    };
  };
}
