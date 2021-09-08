{ config, lib, pkgs, ... }:

# TODO whitelist build-time dependencies?

{
  services.vulnix.whitelists = lib.mkOptionDefault [
    # fix about to be deployed
    {
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
    }

    # general false positives
    ({
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
      "network-3.1.1.1" = {
        cve = [ "2021-35048" ];
        comment = [
          "drv is a haskell library, CVE is about SQLi in some web UI"
          "build-time dependency of shellcheck through pandoc"
        ];
      };
      "zip-3.0" = { # FIXME is it 3 or 3.0?
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
      "plexus-utils" = {
        cve = [ "2017-1000487" ];
        comment = "build-time dependency of mvn2nix";
      };
      maven = {
        cve = [ "2021-26291" ];
        comment = "build-time dependency of mvn2nix";
      };
      commons-collections = {
        cve = [ "2017-15708" ];
        comment = [
          "only affects Apache Synapse"
          "build-time dependency of mvn2nix"
        ];
      };
      "gradle-4.10.3" = {
        cve = [ "2019-15052" ];
        comment = "build-time dependency";
      };
    } // lib.genAttrs [ "shellcheck" "ShellCheck" ] (pname: {
      cve = [ "2021-28794" ];
      comment = "CVE is about a Visual Studio Code extension";
    }) // lib.optionalAttrs (!config.services.xserver.enable) {
      "libX11-1.7.0" = {
        cve = [ "2021-31535" ];
        # XXX nomad jobs might, though very unlikely
        comment = "we don't run a graphical session";
      };
    } // lib.optionalAttrs (
      with pkgs.lib.systems;
      !inspect.predicates.isWindows (parse.mkSystemFromString pkgs.system)
    ) {
      "ripgrep" = {
        cve = [ "2021-3013" ];
        comment = "we're not on windows";
      };
    } // lib.optionalAttrs (!config.services.httpd.enable) {
      "openssl-1.1.1k" = {
        cve = [ "CVE-2019-0190" ];
        comment = "we don't use Apache";
        issue_url = "https://github.com/NixOS/nixpkgs/issues/88371";
      };
    })
  ];
}
