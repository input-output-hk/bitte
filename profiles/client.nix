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

  systemd.services.client-certs = {
    wantedBy = ["multi-user.target"];
    before = [ "consul.service" "vault.service" "nomad.serivce"];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    path = with pkgs; [ sops cfssl coreutils curl cacert ];

    script = ''
      set -exuo pipefail

      pushd /run/keys

      if [ ! -s /etc/ssl/certs/ca.pem ]; then
        curl -o /etc/ssl/certs/ca.pem http://ipxe.${config.cluster.domain}/ca.pem
      fi

      if [ ! -s /etc/ssl/certs/all.pem ]; then
        curl -o /etc/ssl/certs/all.pem http://ipxe.${config.cluster.domain}/all.pem
      fi

      if [ ! -s client.enc.json ]; then
        curl -o client.enc.json http://ipxe.${config.cluster.domain}/client.enc.json
      fi

      sops -d client.enc.json | cfssljson -bare

      mkdir -p /var/lib/consul/certs
      [ -s /var/lib/consul/certs/cert-key.pem ] || cp cert-key.pem /var/lib/consul/certs
      [ -s /var/lib/consul/certs/cert.pem ] || cp cert.pem /var/lib/consul/certs

      mkdir -p /var/lib/vault/certs
      [ -s /var/lib/vault/certs/cert-key.pem ] || cp cert-key.pem /var/lib/vault/certs
      [ -s /var/lib/vault/certs/cert.pem ] || cp cert.pem /var/lib/vault/certs

      mkdir -p /var/lib/nomad/certs
      [ -s /var/lib/nomad/certs/cert-key.pem ] || cp cert-key.pem /var/lib/nomad/certs
      [ -s /var/lib/nomad/certs/cert.pem ] || cp cert.pem /var/lib/nomad/certs
    '';
  };
}
