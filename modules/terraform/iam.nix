{ self, lib, pkgs, config, ... }:
let
  inherit (pkgs.terralib)
    var id pp regions awsProviderNameFor awsProviderFor mkSecurityGroupRule
    nullRoute;

  mapVpcs = pkgs.terralib.mapVpcs config.cluster;
  mapVpcsToList = pkgs.terralib.mapVpcsToList config.cluster;

  merge = lib.foldl' lib.recursiveUpdate { };

  users = [ "tester1" "tester2" ];
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
        path = "kv/*";
        capabilities = [ "create" "read" "update" "delete" "list" ];
        description = "Allow all KV access";
      }];
    };

    resource.vault_policy.developer = {
      name = "developer";
      policy = var "data.vault_policy_document.developer.hcl";
    };

    resource.vault_aws_auth_backend_role = lib.listToAttrs (lib.forEach users (user:
      lib.nameValuePair user {
        backend = "aws";
        role = user;
        auth_type = "iam";
        bound_iam_principal_arns = [ (var "aws_iam_user.${user}.arn") ];
        token_policies = [ "default" "developer" ];
      }));

    resource.vault_aws_secret_backend_role = lib.listToAttrs (lib.forEach users
      (user:
        lib.nameValuePair user {
          backend = "aws";
          name = "tester1";
          credential_type = "iam_user";
          iam_groups = [ "developers" ];
        }));

    resource.aws_iam_group = {
      developers = {
        name = "developers";
        path = "/developers/";
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
    };

    resource.aws_iam_user_group_membership = lib.listToAttrs (lib.forEach users
      (user:
        lib.nameValuePair user {
          user = var "aws_iam_user.${user}.name";
          groups = [ (var "aws_iam_group.developers.name") ];
        }));

    resource.aws_iam_user = lib.listToAttrs
      (lib.forEach users (user: lib.nameValuePair user { name = user; }));
  };
}
