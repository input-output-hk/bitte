{ lib, pkgs, config, nodeName, ... }:
let
  isInstance = config.instance != null;
  isAsg = !isInstance;
  isMonitoring = nodeName == "monitoring";
in {
  secrets.generate.nix-key-file = ''
    export PATH="${lib.makeBinPath (with pkgs; [ nixFlakes sops coreutils ])}"
    esk=encrypted/nix-secret-key-file
    ssk=secrets/nix-secret-key-file
    if [ ! -s "$esk" ]; then
      if [ -s "$ssk" ]; then
        sops --encrypt --input-type binary --kms '${config.cluster.kms}' "$ssk" \
          > "$esk.new"
      else
        nix key generate-secret ${config.cluster.name}-0 \
          | sops --encrypt --input-type binary --kms '${config.cluster.kms}' /dev/stdin \
          > "$esk.new"
      fi
      mv "$esk.new" "$esk"
    fi
    if [ ! -s "$ssk" ]; then
      sops --decrypt --input-type binary "$ssk" > "$ssk.new"
      mv "$ssk.new" "$ssk"
    fi
    epk=encrypted/nix-public-key-file
    spk=secrets/nix-public-key-file
    for pub in "$epk" "$spk"; do
      if [ ! -s "$pub" ]; then
        nix key convert-secret-to-public < "$ssk" > "$pub.new"
        mv "$pub.new" "$pub"
      fi
    done
  '';

  secrets.generate.builder-ssh-key = ''
    export PATH="${lib.makeBinPath (with pkgs; [ openssh sops coreutils ])}"
    epk=encrypted/nix-builder-key.pub
    spk=secrets/nix-builder-key.pub
    esk=encrypted/nix-builder-key
    ssk=secrets/nix-builder-key
    if [ ! -s "$esk" ]; then
      ssh-keygen -t ed25519 -f "$ssk" -P "" -C "builder@monitoring"
      sops --encrypt --input-type binary --kms '${config.cluster.kms}' "$ssk" \
        > "$esk.new"
      mv "$esk.new" "$esk"
    fi
    if [ ! -s "$epk" ]; then
      cp "$spk" "$epk"
    fi
  '';

  secrets.install.builder-private-ssh-key = lib.mkIf isAsg {
    source = config.secrets.encryptedRoot + "/nix-builder-key";
    target = /etc/nix/builder-key;
    inputType = "binary";
    outputType = "binary";
    script = ''
      export PATH="${lib.makeBinPath (with pkgs; [ coreutils openssh ])}"
      chmod 0600 /etc/nix/builder-key
      ssh \
        -o NumberOfPasswordPrompts=0 \
        -o StrictHostKeyChecking=accept-new \
        -i /etc/nix/builder-key \
        builder@${config.cluster.instances.monitoring.privateIP} echo 'trust established'
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
      hostName = config.cluster.instances.monitoring.privateIP;
      maxJobs = 5;
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
        [ (config.secrets.encryptedRoot + "/nix-builder-key.pub") ];
      shell = pkgs.bashInteractive;
      isSystemUser = true;
    };
  };
}
