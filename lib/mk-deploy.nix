{ deploy, lib }:

{ self, deploySshKey }:

assert lib.assertMsg (builtins.typeOf deploySshKey == "string") ''
  'deploySshKey' arg to 'bitte.lib.mkDeploy' must be a string
  relative to the flake root where the ssh key can be found.
'';

let

  deploy' = {
    nodes = builtins.mapAttrs (k: _: let
      cfg = self.nixosConfigurations.${k};
    in {
      sshUser = "root";
      sshOpts = [ "-C" "-o" "StrictHostKeyChecking=no" "-i" "${deploySshKey}"];
      profiles.system.user = "root";
      profiles.system.path =
        let inherit (cfg.pkgs) system;
        in deploy.lib.${system}.activate.nixos cfg;
    } // (lib.optionalAttrs ((cfg.config.currentCoreNode.deployType or cfg.config.currentAwsAutoScalingGroup.deployType) == "prem") {
      hostname = cfg.config.cluster.name + "-" + cfg.config.networking.hostName;
      sshOpts = [ "-C" "-o" "StrictHostKeyChecking=no" ];
    })) self.nixosConfigurations;
  };

in {
  deploy = deploy';

  checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks deploy')
    deploy.lib;

}
