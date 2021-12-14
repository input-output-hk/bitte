{ config, lib, ... }:

let
  cfg = config.services.vulnix.defaultWhitelists;

  resultOption = with lib;
    mkOption {
      readOnly = true;
      type = types.attrs;
      description = "The computed whitelist.";
    };
in {
  options.services.vulnix.defaultWhitelists = {
    ephemeral.whitelist = resultOption // {
      default = {
        "binutils-2.35.1" = {
          until = "2021-10-10";
          comment = "has active PR to upgrade binutils";
          cve = [ "CVE-2021-20294" "CVE-2021-3487" "CVE-2021-20284" ];
          issue_url = "https://github.com/NixOS/nixpkgs/pull/134917";
        };
        "libgcrypt-1.9.3" = {
          until = "2021-10-10";
          comment = "in staging-21.05";
          cve = [ "CVE-2021-40528" ];
          issue_url =
            "https://github.com/NixOS/nixpkgs/pull/137025#issuecomment-914725087";
        };
      };
    };

    # general false positives (nixpkgs-wide)
    nixpkgs.whitelist = resultOption // {
      default = {
        "openssl" = {
          cve = [ "CVE-2018-16395" "CVE-2016-7798" ];
          comment = "CVEs are about a Ruby library";
          issue_url = [
            "https://github.com/flyingcircusio/vulnix/issues/62"
            "https://github.com/NixOS/nixpkgs/issues/116905"
            "https://github.com/NixOS/nixpkgs/issues/109204"
          ];
        };
        "zip-3.0" = {
          # comes up as version "3" in Grafana, not sure why
          cve = [ "CVE-2018-13410" ];
          comment = "disputed";
          issue_url = [
            "https://github.com/NixOS/nixpkgs/issues/88417"
            "https://github.com/NixOS/nixpkgs/issues/70134"
            "https://github.com/NixOS/nixpkgs/issues/57192"
          ];
        };
        "gnulib" = {
          cve = [ "CVE-2018-17942" ];
          comment = "fixed long ago"; # TODO really? check again
          issue_url = [
            "https://github.com/NixOS/nixpkgs/issues/34787"
            "https://github.com/NixOS/nixpkgs/issues/88310"
          ];
        };
        "bash-4.4-p23" = {
          cve = [ "CVE-2019-18276" ];
          comment = "version not affected";
          issue_url =
            "https://github.com/NixOS/nixpkgs/issues/88269#issuecomment-722169817";
        };
        "python" = {
          cve = [ "CVE-2017-17522" ];
          comment = [
            "disputed"
            "not considered a (security) bug by upstream and various downstreams"
          ];
          issue_url = [
            "https://github.com/NixOS/nixpkgs/issues/88385"
            "https://github.com/NixOS/nixpkgs/issues/88384"
            "https://github.com/NixOS/nixpkgs/issues/73675#issuecomment-555525714"
          ];
        };
      } // lib.genAttrs [ "glibc-2.33-49" "glibc-2.33-50" ] (name: {
        cve = [ "CVE-2021-38604" ];
        comment = "version not affected";
        issue_url = [
          "https://github.com/NixOS/nixpkgs/issues/138667#issuecomment-923991137"
          "https://github.com/NixOS/nixpkgs/pull/134765"
        ];
      }) // lib.genAttrs [ "shellcheck" "ShellCheck" ] (pname: {
        cve = [ "CVE-2021-28794" ];
        comment = "CVE is about a Visual Studio Code extension";
      });
    };

    systemDependent = {
      nixosConfig = with lib;
        mkOption {
          type = types.attrs;
          default = config;
          description = "NixOS configuration to consider.";
        };

      whitelist = resultOption // {
        default = let inherit (cfg.systemDependent) nixosConfig;
        in lib.optionalAttrs (!nixosConfig.services.xserver.enable) {
          "libX11-1.7.0" = {
            cve = [ "CVE-2021-31535" ];
            # XXX nomad jobs might, though very unlikely
            comment = "we don't run a graphical session";
          };
        } // lib.optionalAttrs (!lib.systems.inspect.predicates.isWindows (
          # we cannot use `nixosConfig.nixpkgs.pkgs` here
          # due to evaluation order as that is in _module.args
          with nixosConfig.nixpkgs;
          if crossSystem != null then crossSystem else localSystem)) {
            "ripgrep" = {
              cve = [ "CVE-2021-3013" ];
              comment = "we're not on windows";
            };
            "bat" = {
              cve = [ "CVE-2021-36753" ];
              comment = "we're not on windows";
            };
          } // (let
            disabled = !nixosConfig.services.httpd.enable;
            fixed =
              lib.versionAtLeast nixosConfig.services.httpd.package.version
              "2.4.49";
          in lib.optionalAttrs (disabled || fixed) {
            "openssl-1.1.1k" = {
              cve = [ "CVE-2019-0190" ];
              comment = lib.optional disabled "we don't use Apache"
                ++ lib.optional fixed "version not affected";
              issue_url = [
                "https://github.com/NixOS/nixpkgs/issues/88371"
                "https://httpd.apache.org/security/vulnerabilities_24.html"
              ];
            };
          });
      };
    };
  };

  config.services.vulnix = {
    whitelists =
      lib.mkOptionDefault (map (x: x.whitelist) (builtins.attrValues cfg));

    scanNomadJobs.whitelists = lib.mkOptionDefault
      (map (x: x.whitelist) (lib.attrVals [ "ephemeral" "nixpkgs" ] cfg));
  };
}
