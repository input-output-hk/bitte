inputs:
let
  inherit (inputs) nixpkgs ops-lib self;
  inherit (nixpkgs) lib;
  deprecated = k:
    lib.warn ''
      ${k} is deprecated from the bitte overlay.
            See bitte/overlay.nix
    '';
in final: prev:
rec {
  inherit (inputs.nix.packages.x86_64-linux) nix;
  nixFlakes = final.nix;
  nixUnstable = final.nix;

  nomad = inputs.nomad.defaultPackage."${final.system}";
  ragenix = inputs.ragenix.defaultPackage."${final.system}";

  ssh-keys = let
    keys = import (ops-lib + "/overlays/ssh-keys.nix") lib;
    inherit (keys) allKeysFrom devOps;
  in { devOps = allKeysFrom devOps; };

  consul = prev.callPackage ./pkgs/consul { };
  cue = prev.callPackage ./pkgs/cue.nix { };
  vault-bin = prev.callPackage ./pkgs/vault-bin.nix { };
  mill = prev.callPackage ./pkgs/mill.nix { };
  haproxy-auth-request = prev.callPackage ./pkgs/haproxy-auth-request.nix { };
  haproxy-cors = prev.callPackage ./pkgs/haproxy-cors.nix { };
  devShell = final.callPackage ./pkgs/dev-shell.nix { };
  consulRegister = prev.callPackage ./pkgs/consul-register.nix { };
  boundary = prev.callPackage ./pkgs/boundary.nix { };
  grpcdump = prev.callPackage ./pkgs/grpcdump.nix { };
  glusterfs = final.callPackage ./pkgs/glusterfs.nix { };
  victoriametrics = prev.callPackage ./pkgs/victoriametrics.nix { };
  nomad-autoscaler = prev.callPackage ./pkgs/nomad-autoscaler.nix { };
  vault-backend = final.callPackage ./pkgs/vault-backend.nix { };
  oauth2-proxy = final.callPackage ./pkgs/oauth2_proxy.nix { };
  filebeat = final.callPackage ./pkgs/filebeat.nix { };
  spire = prev.callPackage ./pkgs/spire.nix { };
  spire-agent = spire.agent;
  spire-server = spire.server;
  spiffe-helper = prev.callPackage ./pkgs/spiffe-helper.nix { };

  # XXX remove (also flake input) after nixpkgs bump that has vulnix 1.10.1
  vulnix = import inputs.vulnix {
    inherit nixpkgs;
    pkgs = import nixpkgs { inherit (final) system; };
  };

  # Remove once nixpkgs is using openssh 8.7p1+ by default to avoid coredumps
  # Ref: https://bbs.archlinux.org/viewtopic.php?id=265221
  opensshNoCoredump = let version = "8.7p1";
  in prev.opensshPackages.openssh.overrideAttrs (oldAttrs: {
    inherit version;
    src = prev.fetchurl {
      url = "mirror://openbsd/OpenSSH/portable/openssh-${version}.tar.gz";
      sha256 = "sha256-fKNLi7JK6eUPM3krcJGzhB1+G0QP9XvJ+r3fAeLtHiQ=";
    };
  });

  # Little convenience function helping us to containing the bash
  # madness: forcing our bash scripts to be shellChecked.
  writeBashChecked = final.writers.makeScriptWriter {
    interpreter = "${final.bash}/bin/bash";
    check = final.writers.writeBash "shellcheck-check" ''
      ${final.shellcheck}/bin/shellcheck "$1"
    '';
  };
  writeBashBinChecked = name: final.writeBashChecked "/bin/${name}";
  toPrettyJSON = final.callPackage ./pkgs/to-pretty-json.nix { };

  scaler-guard = let deps = with final; [ awscli bash curl jq nomad ];
  in prev.runCommandLocal "scaler-guard" {
    script = ./scripts/scaler-guard.sh;
    nativeBuildInputs = [ prev.makeWrapper ];
  } ''
    makeWrapper $script $out/bin/scaler-guard \
      --prefix PATH : ${prev.lib.makeBinPath deps}
  '';

  uploadBaseAMIs = final.writeBashBinChecked
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
          }).bitteAmazonSystemBaseAMI.config.system.build.amazonImage
        }
      echo Cores done.

      echo Clients ...
      bash -x ${nixpkgs + /nixos/maintainers/scripts/ec2/create-amis.sh} \
        ${
          (self.lib.mkSystem {
            pkgs = final;
          }).bitteAmazonZfsSystemBaseAMI.config.system.build.amazonImage
        }
      echo Clients done.
    '';

} //
# DEPRECATED
(lib.mapAttrs deprecated {

  # Do use bitte.lib directly, instead
  inherit (self.lib) recImport sanitize snakeCase terralib;

  # Do use bitteShell, instead
  bitteShellCompat = lib.warn ''
    'bitteShellCompat' is deprecated.
    Use the unified 'bitteShell' instead.
  '' final.bitteShell;

  # Clutter: organize better or remove
  mkShellNoCC = prev.mkShell.override { stdenv = prev.stdenvNoCC; };
  pp = v: builtins.trace (builtins.toJSON v) v;
  ci-env = prev.symlinkJoin {
    name = "ci-env";
    paths = with prev; [ coreutils bashInteractive git cacert hello nixfmt ];
  };
  ensureDependencies = services:
    let
      checks = lib.concatStringsSep "\n" (lib.forEach services (service:
        "${prev.systemd}/bin/systemctl is-active '${service}.service'"));
    in prev.writeShellScript "check" ''
      set -exuo pipefail
      ${checks}
    '';

  # We will start using input-output-hk/cicero, soon
  mkRequired = constituents:
    let
      build-version = final.writeText "version.json" (builtins.toJSON {
        inherit (inputs.self)
          lastModified lastModifiedDate narHash outPath shortRev rev;
      });
    in final.releaseTools.aggregate {
      name = "required";
      constituents = (lib.attrValues constituents) ++ [ build-version ];
      meta.description = "All required derivations";
    };

  # We will start using input-output-hk/cicero, soon
  hydra-unstable = prev.hydra-unstable.overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or [ ]) ++ [
      # allow evaluator_restrict_eval to be configured
      (prev.fetchpatch {
        url =
          "https://github.com/NixOS/hydra/pull/888/commits/de203436cdbfa521ac3a231fafbcc7490c10766e.patch";
        sha256 = "sha256-TCJEmTkycUWTx7U433jaGzKwpbCyNdXqiv9UfhsHnfs=";
      })
      # allow evaluator_pure_eval to be configured
      (prev.fetchpatch {
        url =
          "https://github.com/NixOS/hydra/pull/981/commits/24959a3ca6608cb1a1b11c2bf8436c800e5811f8.patch";
        sha256 = "sha256-JXhmtI8IDjv6VAXwLwDoGnWywBbIbZYh4uFWlP5UdSU=";
      })
    ];
  });

})

