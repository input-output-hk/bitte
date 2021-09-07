{ lib, ... }: {
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
    }

    # general false positives
    {
      "openssl-1.1.1k" = {
        cve = [
          "CVE-2018-16395"
          "CVE-2016-7798"
        ];
        issue_url = [
          "https://github.com/flyingcircusio/vulnix/issues/62"
          "https://github.com/NixOS/nixpkgs/issues/116905"
          "https://github.com/NixOS/nixpkgs/issues/109204"
        ];
      };
    }

    # do not usually apply to bitte clusters
    {
      "openssl-1.1.1k" = {
        cve = [ "CVE-2019-0190" ];
        issue_url = "https://github.com/NixOS/nixpkgs/issues/88371";
        comment = "we don't use Apache";
      };
    }
  ];
}
