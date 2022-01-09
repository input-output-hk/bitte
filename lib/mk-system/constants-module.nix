{ config, ... }: {
  _module.args = {
    pkiFiles = {
      caCertFile = "/etc/ssl/certs/ca.pem";
      certChainFile = "/etc/ssl/certs/full.pem";
      certFile = "/etc/ssl/certs/cert.pem";
      keyFile = "/etc/ssl/certs/cert-key.pem";
    };

    letsencryptCertMaterial = {
      certFile = "/etc/ssl/certs/${config.cluster.domain}-cert.pem";
      certChainFile = "/etc/ssl/certs/${config.cluster.domain}-full.pem";
      keyFile = "/etc/ssl/certs/${config.cluster.domain}-key.pem";
    };

    hashiTokens = {
      vaultd-consul-json = "/etc/vault.d/consul-token.json";
      nomadd-consul-json = "/etc/nomad.d/consul-token.json";
      consuld-json = "/etc/consul.d/tokens.json";

      vault = "/run/keys/vault-token";
      consul-default = "/run/keys/consul-default-token";
      consul-nomad = "/run/keys/consul-nomad-token";
      consul-vault-srv = "vault-consul-token";
      nomad-snapshot = "/run/keys/nomad-snapshot-token";
      nomad-autoscaler = "/run/keys/nomad-autoscaler-token";
    };
  };
}
