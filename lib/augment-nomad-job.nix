{ nixpkgs }: let
    pkgs = import nixpkgs { system = "x86_64-linux";};
    maybeAddPackage = nixpkgs.lib.mapAttrs (name: orig:
      orig // (
        if orig ? group
        then { group = maybeAddPackage orig.group; }
        else if orig ? task
        then { task = maybeAddPackage orig.task; }
        else if orig.driver == "nix"
        then let
            json = pkgs.writeTextDir "jobs/${name}.json" (builtins.toJSON orig);
            config = orig.config // {
              packages = (orig.config.packages or [ ]) ++ [json];
            };
            # FIXME: nspawn support for nomad group.network.dns.servers
            template = let
              resolvconf =[{
                data = ''
                  nameserver 172.16.0.10
                '';
                destination = "/etc/resolv.conf";
              }];
            in
            if orig ? template then orig.template ++ resolvconf else resolvconf;
          in
          { inherit config template; }
        else { }
      )
    );
in maybeAddPackage
