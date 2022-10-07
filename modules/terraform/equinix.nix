{
  self,
  lib,
  pkgs,
  config,
  terralib,
  ...
}: let
  inherit
    (terralib)
    var
    id
    pp
    regions
    awsProviderNameFor
    awsProviderFor
    mkSecurityGroupRule
    nullRoute
    ;

  inherit
    (config.cluster)
    infraType
    vbkBackend
    vbkBackendSkipCertVerification
    ;

  inherit
    (lib)
    filterAttrs
    foldl'
    mapAttrs
    mapAttrsToList
    mkIf
    mkMerge
    unique
    ;

  infraTypeCheck =
    if builtins.elem infraType ["awsExt"]
    then true
    else
      (throw ''
        To utilize the equinix TF attr, the cluster config parameter `infraType`
        must be "awsExt".
      '');

  awsExtNodesEquinix = filterAttrs (_: v: v ? "equinix") config.cluster.awsExtNodes;

  projects = unique (mapAttrsToList (_: v: v.equinix.project) awsExtNodesEquinix);
in {
  tf.equinix.configuration = mkIf infraTypeCheck {
    terraform.backend = mkIf (vbkBackend != "local") {
      http = let
        vbk = "${vbkBackend}/state/${config.cluster.name}/equinix";
      in {
        address = vbk;
        lock_address = vbk;
        unlock_address = vbk;
        skip_cert_verification = vbkBackendSkipCertVerification;
      };
    };

    terraform.required_providers =
      builtins.trace ''

        **************************************************************************

        Equinix TF Requirements:

        1) The equinix TF provider requires an Equinix metal API token obtained by
        out of band methods (ex: equinix metal console) to be exported in your
        shell as METAL_AUTH_TOKEN.

        2) A sops encrypted file of ''${config.secrets.encryptedRoot}/equinix.json
        consisting of a json set of project name keys to id values that needs to be
        available:

        {
          "<project1>": "<project1Id>",
          "<project2>": "<project2Id>",
          ...
        }

        The `project` name will then be passed in the metal awsExtNodes machine
        definition to be utilized by the equinix TF provider.
        **************************************************************************
      ''
      pkgs.terraform-provider-versions;

    provider = {
      equinix = {
        # The auth token is preferentially specified as an env var of METAL_AUTH_TOKEN
        # Ref: https://registry.terraform.io/providers/equinix/equinix/latest/docs#argument-reference
        # auth_token = "$SENSITIVE";
      };
    };

    data.sops_file.equinix-projects.source_file = "${config.secrets.encryptedRoot + "/equinix.json"}";

    # ---------------------------------------------------------------
    # Networking -- should be handled by overlay
    # ---------------------------------------------------------------

    # ---------------------------------------------------------------
    # SSL/TLS - root ssh
    # ---------------------------------------------------------------

    # awsExt nodes shares the aws cloud keypair with each equinix project
    resource.equinix_metal_project_ssh_key = mkIf (config.cluster.generateSSHKey) (foldl' (acc: project:
      acc
      // {
        "${config.cluster.name}-awsExt-${project}" = {
          name = "${config.cluster.name}-awsExt-${project}";
          public_key = var ''file("secrets/ssh-${config.cluster.name}.pub")'';
          project_id = var "jsondecode(data.sops_file.equinix-projects.raw).${project}";
        };
      }) {}
    projects);

    # ---------------------------------------------------------------
    # IAM + Security Group -- currently no TF equinix resources
    # ---------------------------------------------------------------

    # ---------------------------------------------------------------
    # awsExt (AWS external) Nodes
    # ---------------------------------------------------------------

    resource.equinix_metal_device = mkIf (awsExtNodesEquinix != {}) (mapAttrs (
        name: awsExtNode:
          with awsExtNode.equinix;
            mkMerge [
              (mkIf awsExtNode.enable {
                inherit
                  billing_cycle
                  facilities
                  hostname
                  operating_system
                  plan
                  ;

                project_id = var "jsondecode(data.sops_file.equinix-projects.raw).${project}";
                depends_on = ["equinix_metal_project_ssh_key.${config.cluster.name}-awsExt-${project}"];

                custom_data = mkIf (custom_data != null) (builtins.toJSON custom_data);
                hardware_reservation_id = mkIf (hardware_reservation_id != null) hardware_reservation_id;
                storage = mkIf (storage != null) (builtins.toJSON storage);
                user_data = mkIf (user_data != null) user_data;

                tags = tags ++ ["Project:${var "jsondecode(data.sops_file.equinix-projects.raw).${project}"}"];

                # When not specified, all user keys authorized to a project and all project specific keys are automatically added.
                # Keys can only be added once as TF resources or an error is thrown, regardless of key name being unique.
                # To avoid key collision errors, add further keys on the nix level.
                project_ssh_key_ids = [(var "equinix_metal_project_ssh_key.${config.cluster.name}-awsExt-${project}.id")];

                lifecycle = [{ignore_changes = ["user_data"];}];
              })
            ]
      )
      awsExtNodesEquinix);
  };
}
