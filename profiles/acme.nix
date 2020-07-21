{ lib, pkgs, config, ... }:
let
  inherit (config.cluster) domain kms s3-bucket region instances;
  inherit (lib) forEach listToAttrs nameValuePair;
  s3dir = "s3://${s3-bucket}/infra/secrets/${config.cluster.name}/${kms}";

  postRun = pkgs.writeShellScriptBin "acme-post-run" ''
    export PATH="${lib.makeBinPath (with pkgs; [ coreutils systemd awscli ])}"
    export AWS_DEFAULT_REGION="${region}"

    aws s3 sync "/var/lib/acme/${domain}" "${s3dir}/acme/${domain}/server"

    systemctl reload haproxy
  '';
in {
  security.acme = {
    # server = "https://acme-staging-v02.api.letsencrypt.org/directory";
    acceptTerms = true;
    email = lib.mkForce "michael.fellinger@iohk.io";

    certs."${domain}" = {
      dnsProvider = "route53";
      postRun = "${postRun}/bin/acme-post-run";
      # We use IAM, so this is all automatic, but the module insists on a file.
      credentialsFile = pkgs.writeText "${domain}-credentials" "";
      extraDomains = { "*.${domain}" = { }; };
    };
  };
}
