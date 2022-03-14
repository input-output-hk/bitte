{ nixpkgs }: let
    pkgs = import nixpkgs { system = "x86_64-linux";};
    addPackage = nixpkgs.lib.mapAttrs (name: orig:
      orig
      // (if orig ? group
      then { group = addPackage orig.group; }
      else if orig ? task
      then { task = addPackage orig.task; }
      else
        let
          json = pkgs.writeTextDir "jobs/${name}.json" (builtins.toJSON orig);
          closure = pkgs.buildPackages.closureInfo { rootPaths = json; };
          closureStorePaths = nixpkgs.lib.splitString "\n" (nixpkgs.lib.fileContents "${closure}/store-paths");
          join = pkgs.symlinkJoin {
            name = "closure";
            paths = closureStorePaths;
          };
          config = orig.config // { packages = (orig.config.packages or [ ]) ++ [ join ]; };
        in
        { inherit config; }));
in addPackage
