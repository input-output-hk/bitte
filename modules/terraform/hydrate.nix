# Rationale:
#
# - Hydrate the cluster with backends, roles & policies
# - NB: some things (still) auto-hydrate through systemd one-shot jobs
#       these could eventually be moved here.
{ self, lib, pkgs, config, terralib, ... }:
let
  inherit (terralib)
    var id pp regions awsProviderNameFor awsProviderFor mkSecurityGroupRule
    nullRoute;
in {
  tf.hydrate.configuration = {
    terraform.backend.http = let
      vbk = "https://vbk.infra.aws.iohkdev.io/state/${config.cluster.name}/hydrate";
    in {
      address = vbk;
      lock_address = vbk;
      unlock_address = vbk;
    };

    terraform.required_providers = pkgs.terraform-provider-versions;

    provider = {
      aws = [{ region = config.cluster.region; }] ++ (lib.forEach regions
        (region: {
          inherit region;
          alias = awsProviderNameFor region;
        }));

      vault = { };
    };

    # hydrate vault backends

    /*
    Bootstrap vault intermediate pki endpoint
    with local root CA from well-known encrypted
    locations.
    */
    data.sops_file.ca = {
      source_file = "./encrypted/ca.json";
    };
    resource = {
      # TODO: commented parts are currently accomplished by a systemd one-shot
      # vault_pki_secret_backend.pki = {
      #   description = "Cluster wide TLS/SSL PKI backend";
      #   path = "pki";
      # };
      # vault_pki_secret_backend_config_urls.config_urls = {
      #   backend = var "vault_pki_secret_backend.pki.path";
      #   issuing_certificates = [
      #     "https://vault.${domain}:8200/v1/pki/ca"
      #   ];
      #   crl_distribution_points = [
      #     "https://vault.${domain}:8200/v1/pki/crl"
      #   ];
      # };
      # vault_pki_secret_backend_role.server = {
      #   backend = var "vault_pki_secret_backend.pki.path";
      #   name = "server";
      #       key_type = "ec";
      #       key_bits = 256;
      #       allow_any_name = true;
      #       enforce_hostnames = false;
      #       generate_lease = true;
      #       max_ttl = "72h";
      # };
      # vault_pki_secret_backend_role.client = {
      #   backend = var "vault_pki_secret_backend.pki.path";
      #   name = "client";
      #       key_type = "ec";
      #       key_bits = 256;
      #       allowed_domains = service.consul,${region}.consul;
      #       allow_subdomains = true;
      #       generate_lease = true;
      #       max_ttl = "223h";
      # };
      # vault_pki_secret_backend_role.admin = {
      #   backend = var "vault_pki_secret_backend.pki.path";
      #   name = "admin";
      #       key_type = "ec";
      #       key_bits = 256;
      #       allow_any_name = true;
      #       enforce_hostnames = false;
      #       generate_lease = true;
      #       max_ttl = "12h";
      # };
      vault_pki_secret_backend_intermediate_cert_request.issuing_ca = {
        # depends_on = [ (id "vault_pki_secret_backend.pki") ];
        # backend = var "vault_pki_secret_backend.pki.path";
        backend = "pki";
        type = "internal";
        common_name = "vault.${config.cluster.domain}";
      };
      tls_locally_signed_cert.issuing_ca = {
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
      vault_pki_secret_backend_intermediate_set_signed.issuing_ca = {
        # backend = var "vault_pki_secret_backend.pki.path";
        backend = "pki";
        certificate =
          (var "tls_locally_signed_cert.issuing_ca.cert_pem") +
          (var "data.sops_file.ca.data[\"cert\"]")
        ;
      };
    };

    resource.vault_github_auth_backend.employee = {
      organization = "input-output-hk";
      path = "github-employees";
    };

    resource.vault_github_team = let
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
    in admins // developers;

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
