{
  config,
  lib,
  pkgs,
  etcEncrypted,
  runKeyMaterial,
  ...
}: let
  deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
  domain =
    config
    .${
      if builtins.elem deployType ["aws" "awsExt"]
      then "cluster"
      else "currentCoreNode"
    }
    .domain;
  isSops = builtins.elem deployType ["aws" "awsExt"];
in {
  services.oauth2_proxy.enable = lib.mkDefault true;

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
    keyFile = runKeyMaterial.oauth;

    email.domains = ["iohk.io"];
    cookie.domain = ".${domain}";
  };

  users.extraUsers.oauth2_proxy.group = "oauth2_proxy";
  users.extraGroups.keys.members = ["oauth2_proxy"];
  users.groups.oauth2_proxy = {};

  secrets.install.oauth.script = lib.mkIf isSops ''
    export PATH="${lib.makeBinPath (with pkgs; [sops coreutils])}"

    cat ${etcEncrypted}/oauth-secrets \
      | sops -d /dev/stdin \
      > ${runKeyMaterial.oauth}

    chown root:keys ${runKeyMaterial.oauth}
    chmod g+r ${runKeyMaterial.oauth}
  '';

  systemd.services.oauth2_proxy =
    {
      serviceConfig.RestartSec = "5s";
    }
    // lib.optionalAttrs isSops {
      after = ["secret-oauth.service"];
      wants = ["secret-oauth.service"];
    };

  age.secrets = lib.mkIf (!isSops) {
    oauth-password = {
      file = config.age.encryptedRoot + "/oauth/password.age";
      path = runKeyMaterial.oauth;
      owner = "root";
      group = "keys";
      mode = "0644";
    };
  };
}
