{ deploy, lib }:

{ self, ssh-key }:

  assert lib.assertMsg (builtins.typeOf ssh-key == "string") ''
    'ssh-key' arg to 'bitte.lib.mkDeploy' must be a string
    relative to the flake root where the ssh key can be found.
  '';

let

  deploy' = {
    sshUser = "root";
    sshOpts = [ "-i" "\${FLAKE_ROOT}/${ssh-key}" ];
    nodes = builtins.mapAttrs (k: _: {
      profiles.system.user = "root";
      profiles.system.path =
        deploy.lib.activate.nixos
        self.nixosConfigurations.${k};
    }) self.nixosConfigurations;
  };

in {
  deploy = deploy';

  checks =
    builtins.mapAttrs (system: deployLib: deployLib.deployChecks deploy')
    deploy.lib;

}
