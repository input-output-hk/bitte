{ pkgs, lib, config, bittelib, ... }:
let
  inherit (bittelib) ensureDependencies;

  rmModules = arg:
    let
      sanitized = lib.mapAttrsToList (name: value:
        if name == "_module" then
          null
        else {
          inherit name;
          value =
            if builtins.typeOf value == "set" then rmModules value else value;
        }) arg;
    in lib.listToAttrs (lib.remove null sanitized);

  policy2hcl = name: value:
    pkgs.runCommandLocal "json2hcl" {
      src = builtins.toFile "${name}.json" (builtins.toJSON (rmModules value));
      nativeBuildInputs = [ pkgs.json2hcl ];
    } ''
      json2hcl < "$src" > "$out"
    '';

  vaultPolicyOptionsType = with lib.types; submodule (_: {
    options = {
      capabilities = lib.mkOption {
        type =
          with lib.types; listOf (enum [ "create" "read" "update" "delete" "list" "sudo" ]);
      };
    };
  });

  vaultApproleType = with lib.types; submodule (_: {
    options = {
      token_ttl = lib.mkOption { type = with lib.types; str; };
      token_max_ttl = lib.mkOption { type = with lib.types; str; };
      token_policies = lib.mkOption { type = with lib.types; listOf str; };
    };
  });

  vaultPoliciesType = with lib.types; submodule (_: {
    options = {
      path =
        lib.mkOption { type = with lib.types; attrsOf vaultPolicyOptionsType; };
    };
  });

  createNomadRoles = lib.flip lib.mapAttrsToList config.services.nomad.policies
    (name: policy: ''vault write "nomad/role/${name}" "policies=${name}"'');
in {
  options = {
    services.vault.policies = lib.mkOption {
      type = with lib.types; attrsOf vaultPoliciesType;
      default = { };
    };

    services.vault-acl.enable = lib.mkEnableOption "Create Vault roles";
  };

  # TODO: also remove them again.
  config.systemd.services.vault-acl =
    lib.mkIf config.services.vault-acl.enable {
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

        ${lib.concatStringsSep "" (lib.mapAttrsToList (name: value: ''
          vault policy write "${name}" "${policy2hcl name value}"
        '') config.services.vault.policies)}

        keepNames=(default root ${
          toString ((builtins.attrNames config.services.vault.policies)
            ++ (builtins.attrNames
              config.tf.hydrate.configuration.locals.policies.vault))
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

        ${lib.concatStringsSep "\n" createNomadRoles}
        vault write "nomad/role/management" "policies=" "type=management"

        keepNames=(${
          toString ((builtins.attrNames config.services.nomad.policies
            ++ [ "management" ]) ++ (builtins.attrNames
              config.tf.hydrate.configuration.locals.policies.nomad))
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
