# Rationale:
#
# - Hydrate the cluster with backends, roles & policies
# - NB: some things (still) auto-hydrate through systemd one-shot jobs
#       these could eventually be moved here.
{ self, lib, pkgs, config, ... }:
let
  inherit (pkgs.terralib)
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
