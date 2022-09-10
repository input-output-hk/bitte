inputs: let
  inherit (inputs) nixpkgs nixpkgs-docker nixpkgs-unstable ops-lib self;
  inherit (nixpkgs) lib;

  deprecated = k:
    lib.warn ''
      ${k} is deprecated from the bitte overlay.
            See bitte/overlay.nix
    '';

  pkgsUnstable = nixpkgs-unstable.legacyPackages;
in
  final: prev:
    rec {
      nixFlakes = nixUnstable;
      nixUnstable = builtins.throw "use pkgs.nix directly";

      # Packages specifically needing an unstable nixpkgs pinned latest available version
      inherit
        (pkgsUnstable.${prev.system})
        grafana # 9.1.1
        grafana-loki # 2.6.1
        nushell # 0.65.0
        podman # 4.2.0
        vector
        ; # 0.22.3

      # Alphabetically sorted packages
      agenix = inputs.agenix.packages.${final.system}.agenix;
      agenix-cli = inputs.agenix-cli.packages.${final.system}.agenix-cli;
      bitte-ruby = prev.bundlerEnv {
        name = "bitte-gems";
        gemdir = ./.;
      };

      bundler = prev.bundler.overrideAttrs (o: {
        postInstall = ''
          sed -i -e '/if sudo_needed/I,+2 d' $out/${prev.ruby.gemPath}/gems/${o.gemName}-${o.version}/lib/bundler.rb
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

      glusterfs = final.callPackage ./pkgs/glusterfs.nix {};
      grpcdump = prev.callPackage ./pkgs/grpcdump.nix {};
      mill = prev.callPackage ./pkgs/mill.nix {};
      nomad = prev.callPackage ./pkgs/nomad.nix {buildGoModule = prev.buildGo117Module;};
      nomad-autoscaler = prev.callPackage ./pkgs/nomad-autoscaler.nix {};
      nomad-follower = inputs.nomad-follower.defaultPackage.${prev.system};
      oauth2-proxy = final.callPackage ./pkgs/oauth2_proxy.nix {};
      otel-cli = final.callPackage ./pkgs/otel.nix {};
      ragenix = inputs.ragenix.defaultPackage.${final.system};
      spiffe-helper = prev.callPackage ./pkgs/spiffe-helper.nix {};
      spire-agent = spire.agent;
      spire = prev.callPackage ./pkgs/spire.nix {};
      spire-server = spire.server;
      spire-systemd-attestor = prev.callPackage ./pkgs/spire-systemd-attestor.nix {};
      tempo = pkgsUnstable.${prev.system}.callPackage ./pkgs/tempo.nix {buildGoModule = pkgsUnstable.${prev.system}.buildGo118Module;};
      traefik = pkgsUnstable.${prev.system}.callPackage ./pkgs/traefik.nix {buildGoModule = pkgsUnstable.${prev.system}.buildGo118Module;};
      vault-backend = final.callPackage ./pkgs/vault-backend.nix {};
      vault-bin = prev.callPackage ./pkgs/vault-bin.nix {};
      victoriametrics = prev.callPackage ./pkgs/victoriametrics.nix {buildGoModule = prev.buildGo117Module;};

      scaler-guard = let
        deps = with final; [awscli bash curl jq nomad];
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
        inherit (keys) allKeysFrom devOps;
      in {devOps = allKeysFrom devOps;};

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
    //
    # DEPRECATED
    (lib.mapAttrs deprecated {
      # Do use bitte.lib directly, instead
      inherit (self.lib) recImport sanitize snakeCase terralib;

      # Do use bitteShell, instead
      bitteShellCompat =
        lib.warn ''
          'bitteShellCompat' is deprecated.
          Use the unified 'bitteShell' instead.
        ''
        final.bitteShell;

      # Clutter: organize better or remove
      mkShellNoCC = prev.mkShell.override {stdenv = prev.stdenvNoCC;};
      pp = v: builtins.trace (builtins.toJSON v) v;
      ci-env = prev.symlinkJoin {
        name = "ci-env";
        paths = with prev; [coreutils bashInteractive git cacert hello nixfmt];
      };
      ensureDependencies = services: let
        checks = lib.concatStringsSep "\n" (lib.forEach services (service: "${prev.systemd}/bin/systemctl is-active '${service}.service'"));
      in
        prev.writeShellScript "check" ''
          set -exuo pipefail
          ${checks}
        '';

      # We will start using input-output-hk/cicero, soon
      mkRequired = constituents: let
        build-version = final.writeText "version.json" (builtins.toJSON {
          inherit
            (self)
            lastModified
            lastModifiedDate
            narHash
            outPath
            shortRev
            rev
            ;
        });
      in
        final.releaseTools.aggregate {
          name = "required";
          constituents = (lib.attrValues constituents) ++ [build-version];
          meta.description = "All required derivations";
        };

      # We will start using input-output-hk/cicero, soon
      hydra-unstable = prev.hydra-unstable.overrideAttrs (oldAttrs: {
        patches =
          (oldAttrs.patches or [])
          ++ [
            # allow evaluator_restrict_eval to be configured
            (prev.fetchpatch {
              url = "https://github.com/NixOS/hydra/pull/888/commits/de203436cdbfa521ac3a231fafbcc7490c10766e.patch";
              sha256 = "sha256-TCJEmTkycUWTx7U433jaGzKwpbCyNdXqiv9UfhsHnfs=";
            })
            # allow evaluator_pure_eval to be configured
            (prev.fetchpatch {
              url = "https://github.com/NixOS/hydra/pull/981/commits/24959a3ca6608cb1a1b11c2bf8436c800e5811f8.patch";
              sha256 = "sha256-JXhmtI8IDjv6VAXwLwDoGnWywBbIbZYh4uFWlP5UdSU=";
            })
          ];
      });
    })
