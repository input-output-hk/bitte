{ config, lib, ... }:

let
  cfg = config.services.vulnix.defaultWhitelists;

  resultOption = with lib; mkOption {
    readOnly = true;
    type = types.attrs;
    description = "The computed whitelist.";
  };
in {
  options.services.vulnix.defaultWhitelists = {
    # fix about to be deployed
    ephemeral.whitelist = resultOption // {
      default = {
        "openssl-1.1.1k" = {
          until = "2021-09-15";
          cve = [
            "CVE-2021-3711"
            "CVE-2021-3712"
          ];
          issue_url = "https://github.com/NixOS/nixpkgs/pull/135611";
        };
        "libsndfile-1.0.30" = {
          until = "2021-09-15";
          cve = [ "2021-3246" ];
          issue_url = [
            "https://github.com/NixOS/nixpkgs/issues/132138"
            "https://github.com/NixOS/nixpkgs/pull/132689"
            "https://github.com/NixOS/nixpkgs/pull/134004"
          ];
        };
      };
    };

    # general false positives (nixpkgs-wide)
    nixpkgs.whitelist = resultOption // {
      default = {
        "openssl" = {
          cve = [
            "CVE-2018-16395"
            "CVE-2016-7798"
          ];
          comment = "CVEs are about a Ruby library";
          issue_url = [
            "https://github.com/flyingcircusio/vulnix/issues/62"
            "https://github.com/NixOS/nixpkgs/issues/116905"
            "https://github.com/NixOS/nixpkgs/issues/109204"
          ];
        };
        "zip-3.0" = { # comes up as version "3" in Grafana, not sure why
          cve = [ "2018-13410" ];
          comment = "disputed";
          issue_url = [
            "https://github.com/NixOS/nixpkgs/issues/88417"
            "https://github.com/NixOS/nixpkgs/issues/70134"
            "https://github.com/NixOS/nixpkgs/issues/57192"
          ];
        };
        "gnulib" = {
          cve = [ "2018-17942" ];
          comment = "fixed long ago";
          issue_url = [
            "https://github.com/NixOS/nixpkgs/issues/34787"
            "https://github.com/NixOS/nixpkgs/issues/88310"
          ];
        };
      } // lib.genAttrs [ "shellcheck" "ShellCheck" ] (pname: {
        cve = [ "2021-28794" ];
        comment = "CVE is about a Visual Studio Code extension";
      });
    };

    systemDependent = {
      nixosConfig = with lib; mkOption {
        type = types.attrs;
        default = config;
        description = "NixOS configuration to consider.";
      };

      whitelist = resultOption // {
        default = let
          inherit (cfg.systemDependent) nixosConfig;
        in (
          lib.optionalAttrs (!nixosConfig.services.xserver.enable) {
            "libX11-1.7.0" = {
              cve = [ "2021-31535" ];
              # XXX nomad jobs might, though very unlikely
              comment = "we don't run a graphical session";
            };
          } // lib.optionalAttrs (
            !lib.systems.inspect.predicates.isWindows (
              # we cannot use `nixosConfig.nixpkgs.pkgs` here
              # due to evaluation order as that is in _module.args
              with nixosConfig.nixpkgs;
              if crossSystem != null
              then crossSystem
              else localSystem
            )
          ) {
            "ripgrep" = {
              cve = [ "2021-3013" ];
              comment = "we're not on windows";
            };
          } // lib.optionalAttrs (!nixosConfig.services.httpd.enable) {
            "openssl-1.1.1k" = {
              cve = [ "CVE-2019-0190" ];
              comment = "we don't use Apache";
              issue_url = "https://github.com/NixOS/nixpkgs/issues/88371";
            };
          }
        );
      };
    };
  };

  config.services.vulnix = {
    whitelists = lib.mkOptionDefault (map
      (x: x.whitelist)
      (builtins.attrValues cfg)
    );

    scanNomadJobs.whitelists = lib.mkOptionDefault (map
      (x: x.whitelist)
      (lib.attrVals [ "ephemeral" "nixpkgs" ] cfg)
    );
  };
}
