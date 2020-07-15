{ config, lib, pkgs, ... }:
let
  inherit (builtins) mapAttrs typeOf listToAttrs length attrNames;
  inherit (lib)
    flip mkOption mkIf mkEnableOption mapAttrsToList remove concatStringsSep;
  inherit (lib.types) str enum submodule nullOr attrsOf listOf;
  inherit (pkgs) toPrettyJSON ensureDependencies;

  sanitize = set:
    let
      sanitized = mapAttrsToList (name: value:
        let type = typeOf value;
        in if name == "_module" then
          null
        else if value == null then
          null
        else if type == "set" && (length (attrNames value)) == 0 then
          null
        else if type == "list" && (length value) == 0 then
          null
        else {
          inherit name;
          value = if type == "set" then
            sanitize value
          else if type == "list" then
            remove null value
          else
            value;
        }) set;
    in listToAttrs (remove null sanitized);

  policyOption =
    mkOption { type = enum [ "deny" "read" "write" "scale" "list" ]; };

  subPolicyOption = mkOption {
    default = null;
    type = nullOr (submodule { options = { policy = policyOption; }; });
  };

  nomadPoliciesType = submodule ({ name, ... }: {
    options = {
      name = mkOption {
        type = str;
        default = name;
      };

      description = mkOption {
        default = null;
        type = nullOr str;
      };

      namespace = mkOption {
        default = { };
        type = attrsOf (submodule ({ name, ... }: {
          options = {
            name = mkOption {
              type = str;
              default = name;
            };
            policy = policyOption;
            capabilities = mkOption {
              default = [ ];
              type = listOf (enum [
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

      hostVolume = mkOption {
        default = { };
        type = attrsOf (submodule ({ name, ... }: {
          options = {
            name = mkOption {
              type = str;
              default = name;
            };
            policy = policyOption;
            capabilities = mkOption {
              default = [ ];
              type =
                listOf (enum [ "deny" "mount-readonly" "mount-readwrite" ]);
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
      host_volume = flip mapAttrs policy.hostVolume (name: value: {
        policy = value.policy;
        capabilities = value.capabilities;
      });
      namespace = flip mapAttrs policy.namespace (name: value: {
        policy = value.policy;
        capabilities = value.capabilities;
      });
      inherit (policy) agent node operator plugin quota;
    };

  createPolicies = flip mapAttrsToList config.services.nomad.policies
    (name: policy: ''
      nomad acl policy apply -description="${policy.description}" "${name}" ${
        toPrettyJSON "nomad-policy-${name}" (policyJson policy)
      }
    '');
in {
  options = {
    services.nomad.policies = mkOption {
      type = attrsOf nomadPoliciesType;
      default = { };
    };

    services.nomad-acl.enable = mkEnableOption "Create Nomad policies";
  };

  config.systemd.services.nomad-acl = mkIf config.services.nomad-acl.enable {
    after = [ "nomad.service" ];
    wantedBy = [ "multi-user.target" ];
    description = "Service that creates all Nomad policies";

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "20s";
      WorkingDirectory = "/var/lib/nomad";
      ExecStartPre = ensureDependencies [ "nomad" ];
    };

    path = with pkgs; [ config.services.nomad.package jq ];

    environment = { NOMAD_ADDR = "https://127.0.0.1:4646"; };

    script = ''
      set -euo pipefail

      NOMAD_TOKEN="$(< bootstrap.token)"
      export NOMAD_TOKEN

      ${concatStringsSep "" createPolicies}

      keepNames=(${toString (attrNames config.services.nomad.policies)})
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
