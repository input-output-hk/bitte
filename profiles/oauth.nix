{ config, ... }: {
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
    keyFile = "/run/keys/oauth-secrets";

    email.domains = [ "iohk.io" ];
    cookie.domain = ".${config.cluster.domain}";
  };

  users.extraGroups.keys.members = [ "oauth2_proxy" ];

  secrets.install.oauth.script = ''
    export PATH="${lib.makeBinPath (with pkgs; [ sops coreutils ])}"

    cat ${config.secrets.encryptedRoot + "/oauth-secrets"} \
      | sops -d /dev/stdin \
      > /run/keys/oauth-secrets

    chown root:keys /run/keys/oauth-secrets
    chmod g+r /run/keys/oauth-secrets
  '';

  systemd.services.oauth2_proxy.after = [ "secret-oauth.service" ];
}
