inputs: let
  inherit (inputs) nixpkgs nixpkgs-docker nix nixpkgs-unstable ops-lib self;
  inherit (nixpkgs) lib;

  deprecated = k:
    lib.warn ''
      ${k} is deprecated from the bitte overlay.
            See bitte/overlay.nix
    '';

  pkgsUnstable = nixpkgs-unstable.legacyPackages;
in
  final: prev: rec {
    # Packages specifically needing an unstable nixpkgs pinned latest available version
    inherit
      (pkgsUnstable.${prev.system})
      grafana # 9.1.5
      grafana-loki # 2.6.1
      nushell # 0.68.1
      podman # 4.2.1
      vector
      ; # 0.24.1

    # Alphabetically sorted packages
    agenix = inputs.agenix.packages.${final.system}.agenix;
    agenix-cli = inputs.agenix-cli.packages.${final.system}.agenix-cli;
    bitte-ruby = prev.bundlerEnv {
      name = "bitte-gems";
      gemdir = ./.;
    };

    # TODO: this should be fixed upstream?
    bundler = prev.bundler.overrideAttrs (o: {
      postInstall = ''
        find $out -name bundler.rb | xargs sed -i -e '/if sudo_needed/I,+2 d'
      '';
    });

    caddy = pkgsUnstable.${prev.system}.callPackage ./pkgs/caddy.nix {buildGoModule = pkgsUnstable.${prev.system}.buildGo118Module;};
    consul = pkgsUnstable.${prev.system}.callPackage ./pkgs/consul {buildGoModule = pkgsUnstable.${prev.system}.buildGo118Module;};
    consulRegister = prev.callPackage ./pkgs/consul-register.nix {};
    cue = prev.callPackage ./pkgs/cue.nix {};
    devShell = final.callPackage ./pkgs/dev-shell.nix {};
    docker-distribution = prev.callPackage ./pkgs/docker-distribution.nix {};
    docker-registry-repair = prev.callPackage ./pkgs/docker-registry/default.nix {name = "docker-registry-repair";};
    docker-registry-tail = prev.callPackage ./pkgs/docker-registry/default.nix {name = "docker-registry-tail";};

    # Pin docker and containerd to avoid unexpected cluster wide docker daemon restarts
    # during metal deploy resulting in OCI jobs being killed or behaving unexpectedly
    inherit (nixpkgs-docker.legacyPackages.${prev.system}) docker containerd; # v20.10.15

    mill = prev.callPackage ./pkgs/mill.nix {};
    nix = inputs.nix.packages.${prev.system}.nix;
    nomad = nixpkgs-unstable.legacyPackages.${prev.system}.callPackage ./pkgs/nomad.nix {};
    nomad-autoscaler = prev.callPackage ./pkgs/nomad-autoscaler.nix {};
    nomad-follower = inputs.nomad-follower.defaultPackage.${prev.system};
    oauth2-proxy = final.callPackage ./pkgs/oauth2_proxy.nix {};
    ragenix = inputs.ragenix.defaultPackage.${final.system};
    spiffe-helper = prev.callPackage ./pkgs/spiffe-helper.nix {};
    spire-agent = spire.agent;
    spire = prev.callPackage ./pkgs/spire.nix {};
    spire-server = spire.server;
    spire-systemd-attestor = prev.callPackage ./pkgs/spire-systemd-attestor.nix {};
    traefik = pkgsUnstable.${prev.system}.callPackage ./pkgs/traefik.nix {buildGoModule = pkgsUnstable.${prev.system}.buildGo118Module;};
    vault-backend = final.callPackage ./pkgs/vault-backend.nix {};
    vault-bin = prev.callPackage ./pkgs/vault-bin.nix {};
    victoriametrics = pkgsUnstable.${prev.system}.callPackage ./pkgs/victoriametrics.nix {buildGoModule = pkgsUnstable.${prev.system}.buildGo119Module;};

    scaler-guard = let
      deps = with final; [awscli2 bash curl jq nomad];
    in
      prev.runCommandLocal "scaler-guard" {
        script = ./scripts/scaler-guard.sh;
        nativeBuildInputs = [prev.makeWrapper];
      } ''
        makeWrapper $script $out/bin/scaler-guard \
          --prefix PATH : ${prev.lib.makeBinPath deps}
      '';

    ssh-keys = let
      keys = import (ops-lib + "/overlays/ssh-keys.nix") lib;
      inherit (keys) allKeysFrom devOps csl-developers plutus-developers remoteBuilderKeys;
    in {
      devOps = allKeysFrom devOps;
      ciInfra = allKeysFrom devOps ++ allKeysFrom {inherit (csl-developers) angerman;};
      buildSlaveKeys = {
        macos = allKeysFrom devOps ++ allKeysFrom remoteBuilderKeys;
        linux = remoteBuilderKeys.hydraBuildFarm;
      };
      plutus-developers = allKeysFrom plutus-developers;
    };

    toPrettyJSON = final.callPackage ./pkgs/to-pretty-json.nix {};

    uploadBaseAMIs =
      final.writeBashBinChecked
      "upload-base-amis-to-development-profile-iohk-amis-bucket" ''
        export AWS_PROFILE="development"

        export home_region=eu-central-1
        export bucket=bitte-amis
        export regions="eu-west-1 eu-central-1 us-east-1 us-east-2 us-west-1 us-west-2"

        echo Cores ...
        bash -x ${nixpkgs + /nixos/maintainers/scripts/ec2/create-amis.sh} \
          ${
          (self.lib.mkSystem {
            pkgs = final;
          })
          .bitteAmazonSystemBaseAMI
          .config
          .system
          .build
          .amazonImage
        }
        echo Cores done.

        echo Clients ...
        bash -x ${nixpkgs + /nixos/maintainers/scripts/ec2/create-amis.sh} \
          ${
          (self.lib.mkSystem {
            pkgs = final;
          })
          .bitteAmazonZfsSystemBaseAMI
          .config
          .system
          .build
          .amazonImage
        }
        echo Clients done.
      '';

    writeBashBinChecked = name: final.writeBashChecked "/bin/${name}";
    writeBashChecked = final.writers.makeScriptWriter {
      interpreter = "${final.bash}/bin/bash";
      check = final.writers.writeBash "shellcheck-check" ''
        ${final.shellcheck}/bin/shellcheck "$1"
      '';
    };
  }
