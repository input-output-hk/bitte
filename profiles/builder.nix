{ lib, pkgs, config, nodeName, ... }:
let
  isInstance = config.instance != null;
  isAsg = config.instance == null;
  isMonitoring = nodeName == "monitoring";
in {
  age.secrets = {
    builder = {
      file = config.age.encryptedRoot + "/ssh/builder.age";
      path = "/etc/nix/builder-key";
    };
  };

  systemd.services.ssh-post-start = {
    after = [ "sshd.service"];
    wantedBy = lib.optional config.services.nomad.enable "nomad.service";
    requiredBy = lib.optional config.services.nomad.enable "nomad.service";

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "20s";
    };

    path = with pkgs; [ coreutils openssh ];

    script = ''
      set -exuo pipefail

      ssh \
        -o NumberOfPasswordPrompts=0 \
        -o StrictHostKeyChecking=accept-new \
        -i /etc/nix/builder-key \
        builder@monitoring echo 'trust established'
    '';
  };

  nix = {
    distributedBuilds = isAsg;
    daemonNiceLevel = 10;
    maxJobs = lib.mkIf isAsg 0;
    extraOptions = ''
      builders-use-substitutes = true
    '';
    trustedUsers = lib.mkIf isMonitoring [ "root" "builder" ];
    buildMachines = lib.optionals isAsg [{
      maxJobs = 5;
      hostName = "monitoring";
      speedFactor = 1;
      sshKey = "/etc/nix/builder-key";
      sshUser = "builder";
      system = "x86_64-linux";
    }];
  };

  users.extraUsers = lib.mkIf isMonitoring {
    builder = {
      isSystemUser = true;
      openssh.authorizedKeys.keyFiles =
        [ (config.age.encryptedRoot + "/nix-builder-key.pub") ];
      shell = pkgs.bashInteractive;
    };
  };
}
