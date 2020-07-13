{ lib, pkgs, config, ... }:
let
  inherit (config.cluster) domain kms s3-bucket region instances;
  s3dir = "s3://${s3-bucket}/infra/certs/${region}/${domain}";
in {
  security.acme = {
    # server = "https://acme-staging-v02.api.letsencrypt.org/directory";
    acceptTerms = true;
    email = lib.mkForce "michael.fellinger@iohk.io";

    certs."${domain}" = {
      dnsProvider = "route53";
      user = "nginx";
      group = "nginx";
      postRun = "/run/current-system/systemd/bin/systemctl reload nginx";
      # We use IAM, so this is all automatic, but the module insists on a file.
      credentialsFile = pkgs.writeText "${domain}-credentials" "";
      extraDomains = {
        "consul.${domain}" = null;
        "vault.${domain}" = null;
        "nomad.${domain}" = null;
      };
    };
  };
}
