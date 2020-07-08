{ self, pkgs, config, ... }: {
  imports = [
    ./common.nix
    ./docker.nix
    ./consul/client.nix
    ./vault/client.nix
    ./nomad/client.nix
  ];

  security.pki.certificateFiles =
    [ "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt" ];

  boot.cleanTmpDir = true;

  # TODO: put our CA cert here.
  security.pki.certificates = [ ];
  time.timeZone = "UTC";
  networking.firewall.enable = false;
  systemd.services.amazon-init.enable = false;
  services.amazon-ssm-agent.enable = true;
  services.vault-agent-client.enable = true;

  systemd.services.client-secrets = {
    wantedBy = [ "multi-user.target" ];
    before = [ "consul.service" "vault.service" "nomad.serivce" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "30s";
    };

    path = with pkgs; [ sops cfssl coreutils curl cacert ];

    script = ''
      set -exuo pipefail

      pushd /run/keys

      fetch () {
        src="$1"
        dst="$2"
        if [ ! -s "$dst" ]; then
          curl -f -s -o "$dst" "http://ipxe.${config.cluster.domain}/$src"
        fi
      }

      fetch ca.pem /etc/ssl/certs/ca.pem
      fetch all.pem /etc/ssl/certs/all.pem
      fetch client.enc.json client.enc.json
      fetch vault.enc.json vault.enc.json

      sops -d vault.enc.json > /etc/vault.d/consul-tokens.json
      sops -d client.enc.json | cfssljson -bare

      mkdir -p /var/lib/consul/certs
      [ -s /var/lib/consul/certs/cert-key.pem ] || cp cert-key.pem /var/lib/consul/certs
      [ -s /var/lib/consul/certs/cert.pem     ] || cp     cert.pem /var/lib/consul/certs

      mkdir -p /var/lib/vault/certs
      [ -s /var/lib/vault/certs/cert-key.pem ] || cp cert-key.pem /var/lib/vault/certs
      [ -s /var/lib/vault/certs/cert.pem     ] || cp     cert.pem /var/lib/vault/certs
      fetch core-1.pem /var/lib/vault/certs/core-1.pem
      fetch core-2.pem /var/lib/vault/certs/core-2.pem
      fetch core-3.pem /var/lib/vault/certs/core-3.pem

      mkdir -p /var/lib/nomad/certs
      [ -s /var/lib/nomad/certs/cert-key.pem ] || cp cert-key.pem /var/lib/nomad/certs
      [ -s /var/lib/nomad/certs/cert.pem     ] || cp     cert.pem /var/lib/nomad/certs
    '';
  };
}
