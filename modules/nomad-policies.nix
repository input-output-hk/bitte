{
  config,
  lib,
  pkgs,
  bittelib,
  ...
}: let
  inherit (pkgs) toPrettyJSON;

  sanitize = set: let
    sanitized = lib.mapAttrsToList (name: value: let
      type = with lib.types; builtins.typeOf value;
    in
      if name == "_module"
      then null
      else if value == null
      then null
      else if
        type
        == "set"
        && (builtins.length (builtins.attrNames value))
        == 0
      then null
      else if type == "list" && (builtins.length value) == 0
      then null
      else {
        inherit name;
        value =
          if type == "set"
          then sanitize value
          else if type == "list"
          then lib.remove null value
          else value;
      })
    set;
  in
    builtins.listToAttrs (lib.remove null sanitized);

  policyOption = lib.mkOption {
    type = with lib.types; enum ["deny" "read" "write" "scale" "list"];
  };

  subPolicyOption = lib.mkOption {
    default = null;
    type = with lib.types;
      nullOr (submodule {options = {policy = policyOption;};});
  };

  nomadPoliciesType = with lib.types;
    submodule ({name, ...}: {
      options = {
        name = lib.mkOption {
          # Disallow "management" to avoid collision with a
          # default Vault nomad/creds/management role
          type = with lib.types;
            addCheck str (x:
              assert lib.assertMsg (x != "management") ''
                The "management" Nomad policy name is reserved, please change it.
              '';
                x != "management");
          default = name;
        };

        description = lib.mkOption {
          default = null;
          type = with lib.types; nullOr str;
        };

        namespace = lib.mkOption {
          default = {};
          type = with lib.types;
            attrsOf (submodule ({name, ...}: {
              options = {
                name = lib.mkOption {
                  type = with lib.types; str;
                  default = name;
                };
                policy = policyOption;
                capabilities = lib.mkOption {
                  default = [];
                  type = with lib.types;
                    listOf (enum [
                      "alloc-exec"
                      "alloc-lifecycle"
                      "alloc-node-exec"
                      "csi-list-volume"
                      "csi-mount-volume"
                      "csi-read-volume"
                      "csi-register-plugin"
                      "csi-write-volume"
                      "deny"
                      "dispatch-job"
                      "list-jobs"
                      "list-scaling-policies"
                      "read-fs"
                      "read-job"
                      "read-job-scaling"
                      "read-logs"
                      "read-scaling-policy"
                      "scale-job"
                      "sentinel-override"
                      "submit-job"
                    ]);
                };
              };
            }));
        };

        hostVolume = lib.mkOption {
          default = {};
          type = with lib.types;
            attrsOf (submodule ({name, ...}: {
              options = {
                name = lib.mkOption {
                  type = with lib.types; str;
                  default = name;
                };
                policy = policyOption;
                capabilities = lib.mkOption {
                  default = [];
                  type =
                    listOf (enum ["deny" "mount-readonly" "mount-readwrite"]);
                };
              };
            }));
        };

        agent = subPolicyOption;
        node = subPolicyOption;
        operator = subPolicyOption;
        plugin = subPolicyOption;
        quota = subPolicyOption;
      };
    });

  policyJson = policy:
    sanitize {
      host_volume = lib.flip builtins.mapAttrs policy.hostVolume (name: value: {
        inherit (value) policy;
        inherit (value) capabilities;
      });
      namespace = lib.flip builtins.mapAttrs policy.namespace (name: value: {
        inherit (value) policy;
        inherit (value) capabilities;
      });
      inherit (policy) agent node operator plugin quota;
    };

  createPolicies =
    lib.flip lib.mapAttrsToList config.services.nomad.policies
    (name: policy: ''
      nomad acl policy apply -description="${policy.description}" "${policy.name}" ${
        toPrettyJSON "nomad-policy-${policy.name}" (policyJson policy)
      }
    '');
in {
  options = {
    services.nomad.policies = lib.mkOption {
      type = with lib.types; attrsOf nomadPoliciesType;
      default = {};
    };

    services.nomad-acl.enable = lib.mkEnableOption "Create Nomad policies";
  };

  config.systemd.services.nomad-acl = lib.mkIf config.services.nomad-acl.enable {
    after = ["nomad.service"];
    wantedBy = ["multi-user.target"];
    description = "Service that creates all Nomad policies";

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "20s";
      WorkingDirectory = "/var/lib/nomad";
      ExecStartPre = bittelib.ensureDependencies pkgs ["nomad"];
    };

    path = with pkgs; [config.services.nomad.package jq];

    environment = {NOMAD_ADDR = "https://127.0.0.1:4646";};

    script = ''
      set -euo pipefail

      NOMAD_TOKEN="$(< bootstrap.token)"
      export NOMAD_TOKEN

      ${lib.concatStringsSep "" createPolicies}

      keepNames=(${
        toString ((builtins.attrNames config.services.nomad.policies)
          ++ (builtins.attrNames
            config.tf.hydrate-cluster.configuration.locals.policies.nomad))
      })
      policyNames=($(nomad acl policy list -json | jq -r -e '.[].Name'))

      for name in "''${policyNames[@]}"; do
        keep=""
        for kname in "''${keepNames[@]}"; do
          if [ "$name" = "$kname" ]; then
            keep="yes"
          fi
        done

        if [ -z "$keep" ]; then
          nomad acl policy delete "$name"
        fi
      done
    '';
  };
}
