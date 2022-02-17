{ config, lib, ... }:
let
  deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
  primaryInterface = config.currentCoreNode.primaryInterface or config.currentAwsAutoScalingGroup.primaryInterface;
  cfg = config.virtualisation.docker;
in {

  options = {
    virtualisation.docker = {
      insecureRegistries = lib.mkOption {
        type = with lib.types; nullOr (listOf str);
        default = null;
        description = ''
          A list of insecure docker repositories where TLS certificate checks will be skipped.
          Intended only for temporary use in a test environment where trusted certs are not
          yet available.
        '';
      };
    };
  };

  config = {
    virtualisation.docker.enable = true;
    virtualisation.docker = {
      autoPrune.enable = true;
      autoPrune.dates = "daily";

      extraOptions = lib.concatStringsSep " " ([
        "--log-driver=journald"
        # For simplicity, let the bridge network have a static ip/mask (by default it
        # would choose this one, but fall back to the next range if this one is already used)
        "--bip=172.17.0.1/16"
        # Which allows us to specify that containers should use the local host as the DNS server
        # This is written into the containers /etc/resolv.conf
        "--dns=172.17.0.1"
      ] ++ (lib.optionals (cfg.insecureRegistries != null)
        # Declares insecure registries to be used TEMPORARILY in a test environment
        (map (registry: "--insecure-registry=${registry}") cfg.insecureRegistries)));
    };

    # needed to access AWS meta-data after docker starts veth* devices.
    networking.interfaces.${primaryInterface}.ipv4.routes = lib.mkIf (deployType == "aws") [{
      address = "169.254.169.252";
      prefixLength = 30;
    }];

    # Workaround dhcpcd breaking AWS meta-data, resulting in vault-agent failure.
    # Ref: https://github.com/NixOS/nixpkgs/issues/109389
    # Rather than explicitly deny all veth* interfaces access to dhcpcd,
    # ensure the meta-data route is added upon service restart.
    networking.dhcpcd.runHook = lib.mkIf (deployType == "aws") ''
      if [ "$reason" = BOUND -o "$reason" = REBOOT ]; then
        /run/current-system/systemd/bin/systemctl try-reload-or-restart network-addresses-${primaryInterface}.service || true
      fi
    '';

    # Trust traffic originating from the Nomad bridge where nomad bridge jobs are run
    networking.firewall.trustedInterfaces = [ "docker0" ];
  };
}
