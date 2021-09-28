{ config, lib, pkgs, ... }: {
  services.oauth2_proxy = {
    enable = true;
    extraConfig.whitelist-domain = ".${config.cluster.domain}";
    # extraConfig.github-org = "input-output-hk";
    # extraConfig.github-repo = "input-output-hk/mantis-ops";
    # extraConfig.github-user = "manveru,johnalotoski";
    extraConfig.pass-user-headers = "true";
    extraConfig.set-xauthrequest = "true";
    extraConfig.reverse-proxy = "true";
    provider = "google";
    keyFile = config.age.secrets.oauth.path;

    email.domains = [ "iohk.io" ];
    cookie.domain = ".${config.cluster.domain}";
  };

  users.extraGroups.keys.members = [ "oauth2_proxy" ];

  age.secrets.oauth = {
    file = config.age.encryptedRoot + "/oauth/secrets.age";
    mode = "0440";
    group = "keys";
  };

  systemd.services.oauth2_proxy.after = [ "secret-oauth.service" ];
}
