{
  pkgs,
  lib,
  nomad-follower,
  ...
}: {
  imports = ["${nomad-follower}/module.nix"];

  services.nomad-follower.enable = lib.mkDefault true;

  services.vault-agent.templates."/run/keys/nomad-follower-token" = lib.mkDefault {
    # Vault has deprecated use of `command` in the template stanza, but a bug
    # prevents us from moving to the `exec` statement until resolved:
    # Ref: https://github.com/hashicorp/vault/issues/16230
    command = "${pkgs.systemd}/bin/systemctl --no-block reload nomad-follower.service || true";
    contents = ''
      {{- with secret "nomad/creds/nomad-follower" }}{{ .Data.secret_id }}{{ end -}}'';
  };
}
