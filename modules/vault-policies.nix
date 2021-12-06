{ pkgs, lib, config, bittelib, ... }:
let
  inherit (builtins) toJSON typeOf toFile attrNames;
  inherit (lib)
    mkOption mkIf mkEnableOption mapAttrsToList concatStringsSep remove
    listToAttrs flip forEach;
  inherit (lib.types) listOf enum attrsOf str submodule nullOr;
  inherit (bittelib) ensureDependencies;

  rmModules = arg:
    let
      sanitized = mapAttrsToList (name: value:
        if name == "_module" then
          null
        else {
          inherit name;
          value = if typeOf value == "set" then rmModules value else value;
        }) arg;
    in listToAttrs (remove null sanitized);

  policy2hcl = name: value:
    pkgs.runCommandLocal "json2hcl" {
      src = toFile "${name}.json" (toJSON (rmModules value));
      nativeBuildInputs = [ pkgs.json2hcl ];
    } ''
      json2hcl < "$src" > "$out"
    '';

  vaultPolicyOptionsType = submodule ({ ... }: {
    options = {
      capabilities = mkOption {
        type =
          listOf (enum [ "create" "read" "update" "delete" "list" "sudo" ]);
      };
    };
  });

  vaultApproleType = submodule ({ ... }: {
    options = {
      token_ttl = mkOption { type = str; };
      token_max_ttl = mkOption { type = str; };
      token_policies = mkOption { type = listOf str; };
    };
  });

  vaultPoliciesType = submodule ({ ... }: {
    options = { path = mkOption { type = attrsOf vaultPolicyOptionsType; }; };
  });

  createNomadRoles = flip mapAttrsToList config.services.nomad.policies
    (name: policy: ''vault write "nomad/role/${name}" "policies=${name}"'');
in {
  options = {
    services.vault.policies = mkOption {
      type = attrsOf vaultPoliciesType;
      default = { };
    };

    services.vault-acl.enable = mkEnableOption "Create Vault roles";
  };

  # TODO: also remove them again.
  config.systemd.services.vault-acl = mkIf config.services.vault-acl.enable {
    after = [ "vault.service" "vault-bootstrap.service" ];
    wantedBy = [ "multi-user.target" ];
    description = "Service that creates all Vault policies.";

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "20s";
      WorkingDirectory = "/var/lib/vault";
      ExecStartPre = ensureDependencies pkgs [ "vault-bootstrap" "vault" ];
    };

    environment = {
      inherit (config.environment.variables)
        AWS_DEFAULT_REGION VAULT_CACERT VAULT_ADDR VAULT_FORMAT NOMAD_ADDR;
    };

    path = with pkgs; [ vault-bin sops jq nomad curl cacert ];

    script = ''
      set -euo pipefail

      VAULT_TOKEN="$(sops -d --extract '["root_token"]' vault.enc.json)"
      export VAULT_TOKEN
      export VAULT_ADDR=https://127.0.0.1:8200

      set -x

      # Vault Policies

      ${concatStringsSep "" (mapAttrsToList (name: value: ''
        vault policy write "${name}" "${policy2hcl name value}"
      '') config.services.vault.policies)}

      keepNames=(default root ${
        toString (attrNames config.services.vault.policies)
      })
      policyNames=($(vault policy list | jq -e -r '.[]'))

      for name in "''${policyNames[@]}"; do
        keep=""
        for kname in "''${keepNames[@]}"; do
          if [ "$name" = "$kname" ]; then
            keep="yes"
          fi
        done

        if [ -z "$keep" ]; then
          vault policy delete "$name"
        fi
      done

      # Nomad Policies and Default Management Role

      ${concatStringsSep "\n" createNomadRoles}
      vault write "nomad/role/management" "policies=" "type=management"

      keepNames=(${
        toString (attrNames config.services.nomad.policies ++ [ "management" ])
      })
      nomadRoles=($(nomad acl policy list -json | jq -r -e '.[].Name'))

      for role in "''${nomadRoles[@]}"; do
        keep=""
        for kname in "''${keepNames[@]}"; do
          if [ "$role" = "$kname" ]; then
            keep="yes"
          fi
        done

        if [ -z "$keep" ]; then
          vault delete "nomad/role/$role"
        fi
      done
    '';
  };
}
