# Rationale:
#
# - This is an auxiliary _input_ for core.nix:
#   - aws_iam_role
#   - aws_iam_role_policy
# - It is also a reference for data points in core.nix & clients.nix
# - Keem these machine AWS IAM policies separate in here for overview
# - Find (more volatile) operator policies in hydrate.nix

{ self, lib, pkgs, config, terralib, ... }:
let
  inherit (terralib) allowS3For;
  bucketArn = "arn:aws:s3:::${config.cluster.s3Bucket}";
  allowS3ForBucket = allowS3For bucketArn;
in {
  cluster.iam = {
    roles = {
      client = {
        assumePolicy = {
          effect = "Allow";
          action = "sts:AssumeRole";
          principal.service = "ec2.amazonaws.com";
        };

        policies = let
          s3Secrets = allowS3ForBucket "secrets"
            "infra/secrets/${config.cluster.name}/${config.cluster.kms}" [
              "client"
              "source"
            ];
          s3Cache = allowS3ForBucket "cache" "infra" [ "binary-cache" ];
        in s3Secrets // s3Cache // {
          ssm = {
            effect = "Allow";
            resources = [ "*" ];
            actions = [
              "ec2:ReportInstanceStatus"
              "ec2messages:AcknowledgeMessage"
              "ec2messages:DeleteMessage"
              "ec2messages:FailMessage"
              "ec2messages:GetEndpoint"
              "ec2messages:GetMessages"
              "ec2messages:SendReply"
              "ssmmessages:CreateControlChannel"
              "ssmmessages:CreateDataChannel"
              "ssmmessages:OpenControlChannel"
              "ssmmessages:OpenDataChannel"
              "ssm:DescribeAssociation"
              "ssm:GetDeployablePatchSnapshotForInstance"
              "ssm:GetDocument"
              "ssm:DescribeDocument"
              "ssm:GetManifest"
              "ssm:GetParameter"
              "ssm:GetParameters"
              "ssm:ListAssociations"
              "ssm:ListInstanceAssociations"
              "ssm:PutInventory"
              "ssm:PutComplianceItems"
              "ssm:PutConfigurePackageResult"
              "ssm:UpdateAssociationStatus"
              "ssm:UpdateInstanceAssociationStatus"
              "ssm:UpdateInstanceInformation"
            ];
          };

          ecr = {
            effect = "Allow";
            resources = [ "*" ];
            actions = [
              "ecr:GetAuthorizationToken"
              "ecr:BatchCheckLayerAvailability"
              "ecr:GetDownloadUrlForLayer"
              "ecr:GetRepositoryPolicy"
              "ecr:DescribeRepositories"
              "ecr:ListImages"
              "ecr:DescribeImages"
              "ecr:BatchGetImage"
              "ecr:GetLifecyclePolicy"
              "ecr:GetLifecyclePolicyPreview"
              "ecr:ListTagsForResource"
              "ecr:DescribeImageScanFindings"
            ];
          };

          nomad = {
            effect = "Allow";
            resources = [ "*" ];
            actions = [ "autoscaling:SetInstanceHealth" ];
          };

          consul = {
            effect = "Allow";
            resources = [ "*" ];
            actions = [
              "ec2:DescribeInstances"
              "ec2:DescribeTags"
              "autoscaling:DescribeAutoScalingGroups"
            ];
          };

          vault = {
            effect = "Allow";
            resources = [ "*" ];
            actions = [
              "ec2:DescribeInstances"
              "iam:GetInstanceProfile"
              "iam:GetUser"
              "iam:GetRole"
              "logs:CreateLogStream"
              "logs:PutLogEvents"
            ];
          };

          kms = {
            effect = "Allow";
            resources = [ config.cluster.kms ];
            actions = [ "kms:Encrypt" "kms:Decrypt" "kms:DescribeKey" ];
          };
        };
      };

      core = {
        assumePolicy = {
          effect = "Allow";
          action = "sts:AssumeRole";
          principal.service = "ec2.amazonaws.com";
        };

        policies = let
          s3Secrets = allowS3ForBucket "secret"
            "infra/secrets/${config.cluster.name}/${config.cluster.kms}" [
              "server"
              "client"
              "source"
            ];
          s3Cache = allowS3ForBucket "cache" "infra" [ "binary-cache" ];
        in s3Secrets // s3Cache // {
          kms = {
            effect = "Allow";
            resources = [ config.cluster.kms ];
            actions = [ "kms:Encrypt" "kms:Decrypt" "kms:DescribeKey" ];
          };

          change-route53 = {
            effect = "Allow";
            resources =
              [ "arn:aws:route53:::hostedzone/*" "arn:aws:route53:::change/*" ];
            actions = [
              "route53:GetChange"
              "route53:ChangeResourceRecordSets"
              "route53:ListResourceRecordSets"
            ];
          };

          list-route53 = {
            effect = "Allow";
            actions = [ "route53:ListHostedZonesByName" ];
            resources = [ "*" ];
          };

          assumeRole = {
            effect = "Allow";
            resources = [
              config.cluster.coreNodes.core-1.iam.instanceProfile.tfArn
              config.cluster.coreNodes.core-2.iam.instanceProfile.tfArn
              config.cluster.coreNodes.core-3.iam.instanceProfile.tfArn
            ];
            actions = [ "sts:AssumeRole" ];
          };

          ssm = {
            effect = "Allow";
            resources = [ "*" ];
            actions = [
              "ec2:ReportInstanceStatus"
              "ec2messages:AcknowledgeMessage"
              "ec2messages:DeleteMessage"
              "ec2messages:FailMessage"
              "ec2messages:GetEndpoint"
              "ec2messages:GetMessages"
              "ec2messages:SendReply"
              "ssmmessages:CreateControlChannel"
              "ssmmessages:CreateDataChannel"
              "ssmmessages:OpenControlChannel"
              "ssmmessages:OpenDataChannel"
              "ssm:DescribeAssociation"
              "ssm:GetDeployablePatchSnapshotForInstance"
              "ssm:GetDocument"
              "ssm:DescribeDocument"
              "ssm:GetManifest"
              "ssm:GetParameter"
              "ssm:GetParameters"
              "ssm:ListAssociations"
              "ssm:ListInstanceAssociations"
              "ssm:PutInventory"
              "ssm:PutComplianceItems"
              "ssm:PutConfigurePackageResult"
              "ssm:UpdateAssociationStatus"
              "ssm:UpdateInstanceAssociationStatus"
              "ssm:UpdateInstanceInformation"
            ];
          };

          nomad = {
            effect = "Allow";
            resources = [ "*" ];
            actions = [
              "autoscaling:CreateOrUpdateTags"
              "autoscaling:DescribeAutoScalingGroups"
              "autoscaling:DescribeScalingActivities"
              "autoscaling:SetInstanceHealth"
              "autoscaling:TerminateInstanceInAutoScalingGroup"
              "autoscaling:UpdateAutoScalingGroup"
            ];
          };

          consul = {
            effect = "Allow";
            resources = [ "*" ];
            actions = [
              "ec2:DescribeInstances"
              "ec2:DescribeTags"
              "autoscaling:DescribeAutoScalingGroups"
            ];
          };

          vault = {
            effect = "Allow";
            resources = [ "*" ];
            actions = [
              "ec2:DescribeInstances"
              "iam:AddUserToGroup"
              "iam:AttachUserPolicy"
              "iam:CreateAccessKey"
              "iam:CreateUser"
              "iam:DeleteAccessKey"
              "iam:DeleteUser"
              "iam:DeleteUserPolicy"
              "iam:DetachUserPolicy"
              "iam:GetInstanceProfile"
              "iam:GetRole"
              "iam:GetUser"
              "iam:ListAccessKeys"
              "iam:ListAttachedUserPolicies"
              "iam:ListGroupsForUser"
              "iam:ListUserPolicies"
              "iam:PutUserPolicy"
              "iam:RemoveUserFromGroup"
              "logs:CreateLogStream"
              "logs:PutLogEvents"
              # TODO: "Resource": ["arn:aws:iam::ACCOUNT-ID-WITHOUT-HYPHENS:user/vault-*"]
            ];
          };
        };
      };
    };
  };
}
