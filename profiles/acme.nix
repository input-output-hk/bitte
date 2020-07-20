{ lib, pkgs, config, ... }:
let
  inherit (config.cluster) domain kms s3-bucket region instances;
  inherit (lib) forEach listToAttrs nameValuePair;
  s3dir = "s3://${s3-bucket}/infra/certs/${region}/${domain}";
in {
  security.acme = {
    # server = "https://acme-staging-v02.api.letsencrypt.org/directory";
    acceptTerms = true;
    email = lib.mkForce "michael.fellinger@iohk.io";

    certs."${domain}" = {
      dnsProvider = "route53";
      postRun = "/run/current-system/systemd/bin/systemctl reload haproxy";
      # We use IAM, so this is all automatic, but the module insists on a file.
      credentialsFile = pkgs.writeText "${domain}-credentials" "";
      extraDomains = listToAttrs
        (forEach config.cluster.instances.core-1.route53.domains
          (subDomain: nameValuePair "${subDomain}.${domain}" null));
    };
  };
}
