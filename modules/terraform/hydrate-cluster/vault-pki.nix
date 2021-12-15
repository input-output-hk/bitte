/* Bootstrap vault intermediate pki endpoint
   with local root CA from well-known encrypted
   locations.
*/
{ terralib, lib, config, ... }:
let

  inherit (terralib) var;
  inherit (config.cluster) domain;

in {
  tf.hydrate-cluster.configuration = {

    data.sops_file.ca = { source_file = "./encrypted/ca.json"; };
    # TODO: commented parts are currently accomplished by a systemd one-shot
    # resource.vault_pki_secret_backend.pki = {
    #   description = "Cluster wide TLS/SSL PKI backend";
    #   path = "pki";
    # };
    # resource.vault_pki_secret_backend_config_urls.config_urls = {
    #   backend = var "vault_pki_secret_backend.pki.path";
    #   issuing_certificates = [
    #     "https://vault.${domain}:8200/v1/pki/ca"
    #   ];
    #   crl_distribution_points = [
    #     "https://vault.${domain}:8200/v1/pki/crl"
    #   ];
    # };
    # resource.vault_pki_secret_backend_role.server = {
    #   backend = var "vault_pki_secret_backend.pki.path";
    #   name = "server";
    #       key_type = "ec";
    #       key_bits = 256;
    #       allow_any_name = true;
    #       enforce_hostnames = false;
    #       generate_lease = true;
    #       max_ttl = "72h";
    # };
    # resource.vault_pki_secret_backend_role.client = {
    #   backend = var "vault_pki_secret_backend.pki.path";
    #   name = "client";
    #       key_type = "ec";
    #       key_bits = 256;
    #       allowed_domains = service.consul,${region}.consul;
    #       allow_subdomains = true;
    #       generate_lease = true;
    #       max_ttl = "223h";
    # };
    # resource.vault_pki_secret_backend_role.admin = {
    #   backend = var "vault_pki_secret_backend.pki.path";
    #   name = "admin";
    #       key_type = "ec";
    #       key_bits = 256;
    #       allow_any_name = true;
    #       enforce_hostnames = false;
    #       generate_lease = true;
    #       max_ttl = "12h";
    # };
    resource.vault_pki_secret_backend_intermediate_cert_request.issuing_ca = {
      # depends_on = [ (id "vault_pki_secret_backend.pki") ];
      # backend = var "vault_pki_secret_backend.pki.path";
      backend = "pki";
      type = "internal";
      common_name = "vault.${domain}";
    };
    resource.tls_locally_signed_cert.issuing_ca = {
      cert_request_pem =
        var "vault_pki_secret_backend_intermediate_cert_request.issuing_ca.csr";
      ca_key_algorithm = "ECDSA";
      ca_private_key_pem = var ''data.sops_file.ca.data["key"]'';
      ca_cert_pem = var ''data.sops_file.ca.data["cert"]'';

      validity_period_hours = 43800;
      is_ca_certificate = true;
      allowed_uses = [ "signing" "key encipherment" "cert sign" "crl sign" ];
    };
    resource.vault_pki_secret_backend_intermediate_set_signed.issuing_ca = {
      # backend = var "vault_pki_secret_backend.pki.path";
      backend = "pki";
      certificate = (var "tls_locally_signed_cert.issuing_ca.cert_pem")
        + (var ''data.sops_file.ca.data["cert"]'');
    };

  };
}
