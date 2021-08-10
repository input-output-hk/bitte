{ deploy, lib }:

{ self, cluster ? builtins.head (builtins.attrNames self.clusters) }: {
  deploy = {
    sshUser = "root";
    sshOpts = [ "-i" "\${FLAKE_ROOT}/secrets/ssh-${cluster}" ];
    nodes = let
      inherit (builtins.fromJSON (builtins.readFile "${self}/.cache.json"))
        nodes;

      isUnique = pred: list: lib.count (x: x == pred) list == 1;

      names = map (x: x.name) nodes;
    in builtins.foldl' (x: y:
      let name = if y.name != "" && isUnique y.name names then y.name else y.id;
      in {
        ${name} = {
          hostname = y.pub_ip;
          profiles.system = {
            user = "root";
            path = deploy.lib.x86_64-linux.activate.nixos
              self.nixosConfigurations.${y.nixos};
          };
        };
      } // x) { } nodes;
  };

  checks =
    builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy)
    deploy.lib;

}
