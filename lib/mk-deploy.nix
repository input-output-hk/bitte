{ deploy, lib }:

{ self, deploySshKey }:

assert lib.assertMsg (builtins.typeOf deploySshKey == "string") ''
  'deploySshKey' arg to 'bitte.lib.mkDeploy' must be a string
  relative to the flake root where the ssh key can be found.
'';

let

  deploy' = {
    sshUser = "root";
    sshOpts = [ "-C" "-i" "${deploySshKey}" "-o" "StrictHostKeyChecking=no" ];
    nodes = builtins.mapAttrs
      (k: _: {
        profiles.system.user = "root";
        profiles.system.path =
          let system = self.nixosConfigurations.${k}.pkgs.system;
          in deploy.lib.${system}.activate.nixos self.nixosConfigurations.${k};
      })
      self.nixosConfigurations;
  };

in
{
  deploy = deploy';

  checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks deploy')
    deploy.lib;

}
