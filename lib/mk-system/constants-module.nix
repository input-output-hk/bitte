{ config, ... }:
let
  deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
  domain = config.${if deployType == "aws" then "cluster" else "currentCoreNode"}.domain;
in {
  _module.args = {
    etcEncrypted = "/etc/encrypted";

    pkiFiles = {
      # Common deployType cert files
      caCertFile = "/etc/ssl/certs/ca.pem";

      # "aws" deployType cert files
      certChainFile = "/etc/ssl/certs/full.pem";
      certFile = "/etc/ssl/certs/cert.pem";
      keyFile = "/etc/ssl/certs/cert-key.pem";

      # "prem" and "premSim" deployType cert files
      clientCertFile = "/etc/ssl/certs/client.pem";
      clientKeyFile = "/etc/ssl/certs/client-key.pem";
      clientCertChainFile = "/etc/ssl/certs/client-full.pem";
      serverCertFile = "/etc/ssl/certs/server.pem";
      serverKeyFile = "/etc/ssl/certs/server-key.pem";
      serverCertChainFile = "/etc/ssl/certs/server-full.pem";
    };

    letsencryptCertMaterial = {
      certFile = "/etc/ssl/certs/${domain}-cert.pem";
      certChainFile = "/etc/ssl/certs/${domain}-full.pem";
      keyFile = "/etc/ssl/certs/${domain}-key.pem";
    };

    gossipEncryptionMaterial = {
      nomad = "/etc/nomad.d/secrets.json";
      consul = "/etc/consul.d/secrets.json";
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
      traefik = "/run/keys/traefik-consul-token";
    };
  };
}
