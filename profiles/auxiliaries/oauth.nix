{ config, lib, pkgs, ... }:
let
  deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
  domain = config.${if deployType == "aws" then "cluster" else "currentCoreNode"}.domain;
  isSops = deployType == "aws";
in {

  services.oauth2_proxy.enable = true;

  services.oauth2_proxy = {
    extraConfig.whitelist-domain = ".${domain}";
    # extraConfig.github-org = "input-output-hk";
    # extraConfig.github-repo = "input-output-hk/mantis-ops";
    # extraConfig.github-user = "manveru,johnalotoski";
    extraConfig.pass-user-headers = "true";
    extraConfig.set-xauthrequest = "true";
    extraConfig.reverse-proxy = "true";
    extraConfig.skip-provider-button = lib.mkDefault "true";
    extraConfig.upstream = lib.mkDefault "static://202";

    provider = "google";
    keyFile = "/run/keys/oauth-secrets";

    email.domains = [ "iohk.io" ];
    cookie.domain = ".${domain}";
  };

  users.extraGroups.keys.members = [ "oauth2_proxy" ];

  secrets.install.oauth.script = lib.mkIf isSops ''
    export PATH="${lib.makeBinPath (with pkgs; [ sops coreutils ])}"

    cat ${(toString config.secrets.encryptedRoot) + "/oauth-secrets"} \
      | sops -d /dev/stdin \
      > /run/keys/oauth-secrets

    chown root:keys /run/keys/oauth-secrets
    chmod g+r /run/keys/oauth-secrets
  '';

  systemd.services.oauth2_proxy = lib.mkIf isSops {
    after = [ "secret-oauth.service" ];
    wants = [ "secret-oauth.service" ];
  };

  age.secrets = lib.mkIf (!isSops) {
    oauth-password = {
      file = config.age.encryptedRoot + "/oauth/password.age";
      path = "/run/keys/oauth-secrets";
      owner = "root";
      group = "keys";
      mode = "0644";
    };
  };
}
