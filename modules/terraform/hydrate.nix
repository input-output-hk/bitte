# Rationale:
#
# - Hydrate the cluster with backends, roles & policies
# - Hydrate vault with application secrets
# - Hydrate applications with initial state
# - NB: some things (still) auto-hydrate through systemd one-shot jobs
#       these could eventually be moved here.
{ self, lib, pkgs, config, terralib, ... }:
let
  inherit (terralib)
    var id pp regions awsProviderNameFor awsProviderFor mkSecurityGroupRule
    nullRoute;

  c = "create";
  r = "read";
  u = "update";
  d = "delete";
  l = "list";
  s = "sudo";

  vbkStub = "https://vbk.infra.aws.iohkdev.io/state/${config.cluster.name}";

in
{
  tf.secrets-hydrate.configuration = {
    # preconfigured
    terraform.backend.http = {
      address = "${vbkStub}/secrets-hydrate";
      lock_address = "${vbkStub}/secrets-hydrate";
      unlock_address = "${vbkStub}/secrets-hydrate";
    };
    terraform.required_providers = pkgs.terraform-provider-versions;
    provider.vault = { };
  };

  tf.app-hydrate.configuration = {
    # preconfigured
    terraform.backend.http = {
      address = "${vbkStub}/app-hydrate";
      lock_address = "${vbkStub}/app-hydrate";
      unlock_address = "${vbkStub}/app-hydrate";
    };
    terraform.required_providers = pkgs.terraform-provider-versions;
    provider.vault = { };
  };

  tf.hydrate.configuration = {
    terraform.backend.http = {
      address = "${vbkStub}/hydrate";
      lock_address = "${vbkStub}/hydrate";
      unlock_address = "${vbkStub}/hydrate";
    };
    terraform.required_providers = pkgs.terraform-provider-versions;
    provider.vault = { };
    provider.aws = [{ region = config.cluster.region; }] ++ (lib.forEach regions
      (region: {
        inherit region;
        alias = awsProviderNameFor region;
      }));

    # TODO: migrate stuff from nixos modules here (auth backends)

    /*
      Load docker developer password into vault
    */

    data.sops_file.docker-developer-password.source_file =
      "./encrypted/docker-passwords.json";
    resource.vault_generic_secret.docker-developer-password = {
      path = "kv/nomad-cluster/docker-developer-password";
      data_json = var ''data.sops_file.docker-developer-password.raw'';
    };

    /*
      Polices. (vault, todo: nomad & consul)
      Related to roles that are impersonated by humans.
      -> Machine roles best remain within systemd one-shots.
    */
    # this policy document is (at least) overridable
    data.vault_policy_document.admin.rule =
      let
        rules = [
          { path = "approle/*"; capabilities = [ c r u d l ]; description = ""; }
          { path = "aws/*"; capabilities = [ c r u d l ]; description = ""; }
          { path = "consul/*"; capabilities = [ c r u d l ]; description = ""; }
          { path = "kv/*"; capabilities = [ c r u d l ]; description = ""; }
          { path = "nomad/*"; capabilities = [ c r u d l ]; description = ""; }
          { path = "pki/*"; capabilities = [ c r u d l ]; description = ""; }
          { path = "sops/*"; capabilities = [ c r u d l ]; description = ""; }
          { path = "auth/aws/config/client"; capabilities = [ c r u d l ]; description = ""; }
          { path = "auth/aws/role/*"; capabilities = [ c r u d l ]; description = ""; }
          { path = "auth/github-employees/config"; capabilities = [ c r u d l s ]; description = ""; }
          { path = "auth/github-employees/map/teams/*"; capabilities = [ c r u d l s ]; description = ""; }
          { path = "auth/github-terraform/config"; capabilities = [ c r u d l s ]; description = ""; }
          { path = "auth/github-terraform/map/teams/*"; capabilities = [ c r u d l s ]; description = ""; }
          { path = "auth/token/create/*"; capabilities = [ c r u d l ]; description = ""; }
          { path = "auth/token/create"; capabilities = [ c r u d l s ]; description = ""; }
          { path = "auth/token/create/nomad-cluster"; capabilities = [ c r u d l s ]; description = ""; }
          { path = "auth/token/create/nomad-server"; capabilities = [ c r u d l s ]; description = ""; }
          { path = "auth/token/create-orphan"; capabilities = [ c r u d l ]; description = ""; }
          { path = "auth/token/lookup"; capabilities = [ c r u d l ]; description = ""; }
          { path = "auth/token/lookup-self"; capabilities = [ r ]; description = ""; }
          { path = "auth/token/renew-self"; capabilities = [ u ]; description = ""; }
          { path = "auth/token/revoke-accessor"; capabilities = [ u ]; description = ""; }
          { path = "auth/token/revoke"; capabilities = [ u ]; description = ""; }
          { path = "auth/token/roles/*"; capabilities = [ c r u d l ]; description = ""; }
          { path = "auth/token/roles/nomad-cluster"; capabilities = [ c r u d l ]; description = ""; }
          { path = "auth/token/roles/nomad-server"; capabilities = [ r ]; description = ""; }
          { path = "identity/*"; capabilities = [ c r u d l ]; description = ""; }
          { path = "sys/auth/aws"; capabilities = [ c r u d l s ]; description = ""; }
          { path = "sys/auth"; capabilities = [ r l ]; description = ""; }
          { path = "sys/auth/github-employees"; capabilities = [ c r u d l s ]; description = ""; }
          { path = "sys/auth/github-employees/config"; capabilities = [ c r ]; description = ""; }
          { path = "sys/auth/github-terraform"; capabilities = [ c r u d l s ]; description = ""; }
          { path = "sys/auth/github-terraform/config"; capabilities = [ c r ]; description = ""; }
          { path = "sys/capabilities-self"; capabilities = [ s ]; description = ""; }
          { path = "sys/mounts/auth/*"; capabilities = [ c r u d l s ]; description = ""; }
          { path = "sys/mounts/sops"; capabilities = [ c r u d l s ]; description = ""; }
          { path = "sys/policies/*"; capabilities = [ c r u d l ]; description = ""; }
          { path = "sys/policy"; capabilities = [ c r u d l ]; description = ""; }
          { path = "sys/policy/*"; capabilities = [ c r u d l ]; description = ""; }
        ];
      in
      rules;

    resource.vault_policy.admin = {
      name = "admin";
      policy = var "data.vault_policy_document.admin.hcl";
    };
    resource.vault_policy.developer = {
      name = "developer";
      policy = builtins.toJSON {
        path = {
          # Allow to decrypt dev sops secrets
          "sops/dev".capabilities = [ r l ];
          # Allow all KV access
          "kv/*".capabilities = [ c r u d l ];
          # Allow creating AWS tokens
          "aws/creds/developer".capabilities = [ r u ];
          # Allow creating Nomad tokens
          "nomad/creds/developer".capabilities = [ r u ];
          # Allow creating Consul tokens
          "consul/creds/developer".capabilities = [ r u ];
          # Allow lookup of own capabilities
          "sys/capabilities-self".capabilities = [ u ];
          # Allow lookup of own tokens
          "auth/token/lookup-self".capabilities = [ r ];
          # Allow self renewing tokens
          "auth/token/renew-self".capabilities = [ u ];
        };
      };
    };

    /*
      Transit backend for sops encryption / decryption
      ATTENTION!
      Export the private keys and store them in vaultwarden
      Otherwise, secrets are lost if the cluster goes down.
    */
    resource.vault_mount.sops = {
      path = "sops";
      type = "transit";
      description = "Sops encryption / decryption transit backend";
      default_lease_ttl_seconds = 3600;
      max_lease_ttl_seconds = 86400;
    };
    resource.vault_transit_secret_backend_key.ops = {
      backend = var "vault_mount.sops.path";
      name = "ops"; # devops
      allow_plaintext_backup = true; # enables key backup into vaultwarden
    };
    resource.vault_transit_secret_backend_key.dev = {
      backend = var "vault_mount.sops.path";
      name = "dev"; # developers
      allow_plaintext_backup = true; # enables key backup into vaultwarden
    };

    /*
      Bootstrap vault intermediate pki endpoint
      with local root CA from well-known encrypted
      locations.
    */
    data.sops_file.ca = {
      source_file = "./encrypted/ca.json";
    };
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
      common_name = "vault.${config.cluster.domain}";
    };
    resource.tls_locally_signed_cert.issuing_ca = {
      cert_request_pem = var "vault_pki_secret_backend_intermediate_cert_request.issuing_ca.csr";
      ca_key_algorithm = "ECDSA";
      ca_private_key_pem = var "data.sops_file.ca.data[\"key\"]";
      ca_cert_pem = var "data.sops_file.ca.data[\"cert\"]";

      validity_period_hours = 43800;
      is_ca_certificate = true;
      allowed_uses = [
        "signing"
        "key encipherment"
        "cert sign"
        "crl sign"
      ];
    };
    resource.vault_pki_secret_backend_intermediate_set_signed.issuing_ca = {
      # backend = var "vault_pki_secret_backend.pki.path";
      backend = "pki";
      certificate =
        (var "tls_locally_signed_cert.issuing_ca.cert_pem") +
        (var "data.sops_file.ca.data[\"cert\"]")
      ;
    };


    /*
      Bootstrap vault github employee & aws backend.
    */
    resource.vault_github_auth_backend.employee = {
      organization = "input-output-hk";
      path = "github-employees";
    };

    resource.vault_github_team =
      let
        admins = lib.listToAttrs (lib.forEach config.cluster.adminGithubTeamNames
          (name:
            lib.nameValuePair name {
              backend = var "vault_github_auth_backend.employee.path";
              team = name;
              policies = [ "admin" "default" ];
            }));

        developers = lib.listToAttrs
          (lib.forEach config.cluster.developerGithubTeamNames (name:
            lib.nameValuePair name {
              backend = var "vault_github_auth_backend.employee.path";
              team = name;
              policies = [ "developer" "default" ];
            }));
      in
      admins // developers;

    resource.vault_github_user =
      lib.mkIf (builtins.length config.cluster.developerGithubNames > 0)
        (lib.listToAttrs (lib.forEach config.cluster.developerGithubNames (name:
          lib.nameValuePair name {
            backend = var "vault_github_auth_backend.employee.path";
            user = name;
            policies = [ "developer" "default" ];
          })));

    resource.vault_aws_secret_backend_role = {
      developers = {
        backend = "aws";
        name = "developer";
        credential_type = "iam_user";
        iam_groups = [ "developers" ];
      };
      admin = {
        backend = "aws";
        name = "admin";
        credential_type = "iam_user";
        iam_groups = [ "admins" ];
      };
    };

    # hydrate aws groups & policies

    resource.aws_iam_group = {
      developers = {
        name = "developers";
        path = "/developers/";
      };
      admins = {
        name = "admins";
        path = "/admins/";
      };
    };

    resource.aws_iam_group_policy = {
      developers = {
        name = "Developers";
        group = var "aws_iam_group.developers.name";
        policy = ''
          {
            "Version": "2012-10-17",
            "Statement": [
              {
                "Effect": "Allow",
                "Action": [
                  "iam:ChangePassword"
                ],
                "Resource": [
                  "arn:aws:iam::*:user/$${aws:username}"
                ]
              },
              {
                "Effect": "Allow",
                "Action": [
                  "iam:GetAccountPasswordPolicy",
                  "autoscaling:DescribeAutoScalingGroups"
                ],
                "Resource": "*"
              },
              {
                "Effect": "Allow",
                "Action": [
                  "s3:*"
                ],
                "Resource": "arn:aws:s3:::*"
              }
            ]
          }
        '';
      };
      admins = {
        name = "Administrators";
        group = var "aws_iam_group.admins.name";
        policy = ''
          {
            "Version": "2012-10-17",
            "Statement": [
              {
                "Effect": "Allow",
                "Action": "*",
                "Resource": "*"
              }
            ]
          }
        '';
      };
    };
  };
}
