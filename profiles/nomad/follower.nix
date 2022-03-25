{ pkgs, lib, nomad-follower, ... }: {
  imports = [ "${nomad-follower}/module.nix" ];

  services.nomad-follower.enable = lib.mkDefault true;

  services.vault-agent.templates."/run/keys/nomad-follower-token" = lib.mkDefault {
    command =
      "${pkgs.systemd}/bin/systemctl --no-block reload nomad-follower.service || true";
    contents = ''
      {{- with secret "nomad/creds/nomad-follower" }}{{ .Data.secret_id }}{{ end -}}'';
  };
}
