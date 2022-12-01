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
    sshArgs
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

  relEncryptedFolder = let
    path = with config;
      if (cluster.infraType == "prem")
      then age.encryptedRoot
      else secrets.encryptedRoot;
  in
    lib.last (builtins.split "/nix/store/.{32}-" (toString path));

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

        Equinix TF Pre-provisioning Requirements:

        1) The equinix TF provider requires an Equinix metal API token obtained by
        out of band methods (ex: equinix metal console) to be exported in your
        shell as METAL_AUTH_TOKEN.

        2) A sops encrypted file consisting of a json set of project name keys to
        id values needs to be available.  Example format is:

        {
          "<project1>": "<project1Id>",
          "<project2>": "<project2Id>",
          ...
        }

        The `project` name will then be passed in the metal awsExtNodes machine
        definition to be utilized by the equinix TF provider.  The expected file
        path is:

        ${relEncryptedFolder}/equinix.json


        --------------------------------------------------------------------------


        Equinix TF Post-provisioning Requirements:

        1) The publicIP of the Equinix machine is not known prior to provisioning
        and must be updated in the awsExt node declaration when provisioning
        completes and before any additional deployments from a local deployer are
        done.

        2) During the provisioning process, Equinix machine specific configuration
        files are retrieved and placed in the local repo.  These config files need
        to be included in the nixosConfiguration modules or any subsequent
        deployment will likely break the machine by rendering it network
        inaccessible.  By default, these files will be placed at:

        ${relEncryptedFolder}/../equinix/$AWSEXT_NODE_NAME

        3) Keeping an encrypted ssh config.d drop in file up to date for Equinix
        provisioned machines which others can utilize is good practice since
        these machines currently do not utilize the bitte cli.

        ${relEncryptedFolder}/equinix-${config.cluster.name}-ssh.conf

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
                provisioner = let
                  publicIP = var "self.access_public_ipv4";
                in [
                  {
                    local-exec = {
                      command = "${
                        self.nixosConfigurations."${config.cluster.name}-${name}".config.secrets.generateScript
                      }/bin/generate-secrets";
                    };
                  }
                  {
                    local-exec = let
                      ssh = "ssh ${sshArgs} -i ./secrets/ssh-${config.cluster.name}";
                      command = pkgs.writeShellApplication {
                        name = "awsExt-provision";
                        runtimeInputs = with pkgs; [
                          coreutils
                          gitMinimal
                          openssh
                          rsync
                          sops
                        ];
                        text = ''
                          ip="''${1?Must provide IP}"
                          ssh_target="root@$ip"
                          echo Waiting for host to become ready ...
                          until ${ssh} "$ssh_target" -- uptime &>/dev/null; do
                            sleep 1
                          done

                          echo Pulling equinix machine config...
                          rsync -a -e "${ssh}" "root@$ip:/etc/nixos/*" "$(realpath ${relEncryptedFolder}/../equinix/${name})/"
                          git add "$(realpath ${relEncryptedFolder}/../equinix/${name})/"

                          echo Pushing awsExt enablement...
                          CONFIG=$(sops -d ${relEncryptedFolder}/awsExt-config)
                          CREDENTIALS=$(sops -d ${relEncryptedFolder}/awsExt-credentials)
                          CMD1="mkdir -p /etc/aws /root/.aws; echo \"$CONFIG\" > /etc/aws/config; echo \"$CREDENTIALS\" > /etc/aws/credentials"
                          CMD2="cp /etc/aws/* /root/.aws/; chmod 0700 /root/.aws; chmod 0600 /root/.aws/credentials"
                          ${ssh} "$ssh_target" -- "$CMD1; $CMD2"

                          echo "Provisioning complete.  Public IP is: $ip"
                        '';
                      };
                    in {
                      command = "${command}/bin/${command.name} ${publicIP}";
                      interpreter = ["${pkgs.bash}/bin/bash" "-c"];
                    };
                  }
                ];
              })
            ]
      )
      awsExtNodesEquinix);
  };
}
