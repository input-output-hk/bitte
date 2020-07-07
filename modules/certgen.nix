{ pkgs, lib, config, nodeName, ... }:
let
  inherit (builtins) toJSON;
  inherit (lib) mapAttrs mkIf mkEnableOption;
in {
  # FIXME: this leaves the root certificate on each core machine for signing
  #        themselves...
  #        Add service that does the cleanup by setting the CA in Vault and
  #        re-issuing the certificates from there.
  options = {
    services.certgen.enable = mkEnableOption "Enable certificate distributor";
  };

  config = {
    systemd.services.certgen = mkIf config.services.certgen.enable {
      wantedBy = [ "multi-user.target" ];
      before = [ "consul.service" "vault.service" ];
      requiredBy = [ "consul.service" "vault.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      path = with pkgs; [ consul jq sops cfssl ];

      script = ''
        set -exuo pipefail
        pushd /run/keys

        enc="certs.enc.json"

        echo "Waiting for $PWD/$enc from deployer..."

        set +x
        until [ -s "$enc" ]; do
          sleep 1
        done
        set -x

        sops -d certs.enc.json | cfssljson -bare

        cat ca.pem core-*.pem > all.pem
        cp ca.pem /etc/ssl/certs/ca.pem
        cp all.pem /etc/ssl/certs/all.pem

        # Consul
        mkdir -p /var/lib/consul/certs
        cp cert-key.pem /var/lib/consul/certs
        cp cert.pem /var/lib/consul/certs

        # Vault
        mkdir -p /var/lib/vault/certs
        cp cert-key.pem /var/lib/vault/certs
        cp cert.pem /var/lib/vault/certs
        cp core-*.pem /var/lib/vault/certs

        # Nomad
        mkdir -p /var/lib/nomad/certs
        cp cert-key.pem /var/lib/nomad/certs
        cp cert.pem /var/lib/nomad/certs

        enc="client.enc.json"
        echo "Waiting for $PWD/$enc from deployer..."

        # Clients
        set +x
        until [ -s "$enc" ]; do
          sleep 1
        done
        set -x

        cp "$enc" "/var/lib/nginx"
        if [ -d /var/lib/nginx ]; then
          cp core-*.pem /var/lib/nginx/nixos-images
        fi
      '';
    };
  };
}
