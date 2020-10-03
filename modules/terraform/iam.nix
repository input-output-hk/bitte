{ self, lib, pkgs, config, ... }:
let
  inherit (pkgs.terralib)
    var id pp regions awsProviderNameFor awsProviderFor mkSecurityGroupRule
    nullRoute;

  mapVpcs = pkgs.terralib.mapVpcs config.cluster;
  mapVpcsToList = pkgs.terralib.mapVpcsToList config.cluster;

  merge = lib.foldl' lib.recursiveUpdate { };

in {
  tf.iam.configuration = {
    terraform.backend.remote = {
      organization = config.cluster.terraformOrganization;
      workspaces = [{ prefix = "${config.cluster.name}_"; }];
    };

    provider = {
      aws = [{ region = config.cluster.region; }] ++ (lib.forEach regions
        (region: {
          inherit region;
          alias = awsProviderNameFor region;
        }));

      vault = { };
    };

    data.vault_policy_document.developer = {
      rule = [{
        # TODO: Create new rules to be able to create a nomad token
        #       Need a token which comes from the nomad policy developer
        #       Create new rules to be able to create a consul token
        #       Need a token which comes from the nomad policy developer
        path = "kv/*";
        capabilities = [ "create" "read" "update" "delete" "list" ];
        description = "Allow all KV access";
      }];
    };

    resource.vault_github_auth_backend.employee = {
      organization = "input-output-hk";
      path = "github-employees";
    };

    resource.vault_github_team.devops = {
      backend = var "vault_github_auth_backend.employee.path";
      team = "devops";
      policies = [ "admin" "default" ];
    };

    resource.vault_policy.developer = {
      name = "developer";
      policy = var "data.vault_policy_document.developer.hcl";
    };

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
                  "iam:GetAccountPasswordPolicy"
                ],
                "Resource": "*"
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
