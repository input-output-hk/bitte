let
  domain = "bitte.domain.com";
  region = "eu-central-1"; # consul region
in {
  entries = [
    {
      spiffe_id = "spiffe://io.iog/clusters/bitte/${cluster}/vault/server";
      parent_id = "spiffe://io.iog/clusters/bitte/${cluster}/core/jointoken";
      dns_names = [
        "vault.service.consul"
        "vault.${domain}"
        "127.0.0.1"
        # idenitifies this certificate holder as a (potential) vault leader role (AuthZ)
        # TODO: set leader_tls_server_name = leader.raft.vault
        "leader.raft.vault"
      ];
      selectors = [
        { type = "unix"; value = "name:vault"; }
        { type = "unix"; value = "path:${pkgs.vault}/bin/vault"; }
      ];
    }
    {
      spiffe_id = "spiffe://io.iog/clusters/bitte/${cluster}/vault/agent";
      parent_id = "spiffe://io.iog/clusters/bitte/${cluster}/client/jointoken";
      dns_names = [ "127.0.0.1" ]; # only ever serves locally
      selectors = [
        { type = "unix"; value = "name:vault"; }
        { type = "unix"; value = "path:${pkgs.vault}/bin/vault"; }
      ];
    }

    {
      spiffe_id = "spiffe://io.iog/clusters/bitte/${cluster}/consul/server";
      parent_id = "spiffe://io.iog/clusters/bitte/${cluster}/core/jointoken";
      dns_names = [
        "consul.service.consul"
        "consul.${domain}"
        "127.0.0.1"
        # idenitifies this certificate holder as a consul server role (AuthZ)
        "server.${region}.consul"
      ];
      selectors = [
        { type = "unix"; value = "name:consul"; }
        { type = "unix"; value = "path:${pkgs.consul}/bin/consul"; }
      ];
    }
    {
      spiffe_id = "spiffe://io.iog/clusters/bitte/${cluster}/consul/client";
      parent_id = "spiffe://io.iog/clusters/bitte/${cluster}/client/jointoken";
      dns_names = [ "127.0.0.1" ]; # only ever serves locally
      selectors = [
        { type = "unix"; value = "name:consul"; }
        { type = "unix"; value = "path:${pkgs.consul}/bin/consul"; }
      ];
    }

    {
      spiffe_id = "spiffe://io.iog/clusters/bitte/${cluster}/nomad/server";
      parent_id = "spiffe://io.iog/clusters/bitte/${cluster}/core/jointoken";
      dns_names = [
        "nomad.service.consul"
        "nomad.${domain}"
        "127.0.0.1"
        # idenitifies this certificate holder as a nomad server role (AuthZ)
        # TODO: set `verify_server_hostname = true` in the nomad config
        "server.${region}.nomad"
      ];
      selectors = [
        { type = "unix"; value = "name:nomad"; }
        { type = "unix"; value = "path:${pkgs.nomad}/bin/nomad"; }
      ];
    }
    {
      spiffe_id = "spiffe://io.iog/clusters/bitte/${cluster}/nomad/client";
      parent_id = "spiffe://io.iog/clusters/bitte/${cluster}/client/jointoken";
      dns_names = [
        "127.0.0.1" # only ever serves locally
        # idenitifies this certificate holder as a nomad client role (AuthZ)
        # TODO: set `verify_server_hostname = true` in the nomad config
        "client.${region}.nomad"
      ];
      selectors = [
        { type = "unix"; value = "name:nomad"; }
        { type = "unix"; value = "path:${pkgs.nomad}/bin/nomad"; }
      ];
    }
  ];
}
