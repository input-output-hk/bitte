{ pkgs, lib, config, ... }:
let
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

  vaultPolicyOptionsType = with lib.types;
    submodule (_: {
      options = {
        capabilities = lib.mkOption {
          type = with lib.types;
            listOf (enum [ "create" "read" "update" "delete" "list" "sudo" ]);
        };
      };
    });

  vaultApproleType = with lib.types;
    submodule (_: {
      options = {
        token_ttl = lib.mkOption { type = with lib.types; str; };
        token_max_ttl = lib.mkOption { type = with lib.types; str; };
        token_policies = lib.mkOption { type = with lib.types; listOf str; };
      };
    });

  vaultPoliciesType = with lib.types;
    submodule (_: {
      options = {
        path = lib.mkOption {
          type = with lib.types; attrsOf vaultPolicyOptionsType;
        };
      };
    });

  createNomadRoles = lib.flip lib.mapAttrsToList config.services.nomad.policies
    (name: policy: ''vault write "nomad/role/${name}" "policies=${name}"'');

  createConsulRoles =
    map (name: ''vault write "consul/roles/${name}" "policies=${name}"'')
    (builtins.attrNames config.services.consul.policies);
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
      after = [ "vault.service" ];
      wantedBy = [ "multi-user.target" ];
      description = "Service that creates all Vault policies.";

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "20s";
        WorkingDirectory = "/var/lib/vault";
        ExecStartPre = pkgs.ensureDependencies [ "vault" ];
      };

      environment = {
        inherit (config.environment.variables)
          AWS_DEFAULT_REGION VAULT_FORMAT NOMAD_ADDR;
        VAULT_ADDR = "https://127.0.0.1:8200";
        VAULT_CACERT = config.age.secrets.vault-full.path;
        VAULT_CLIENT_KEY = config.age.secrets.vault-client-key.path;
        VAULT_CLIENT_CERT = config.age.secrets.vault-client.path;
      };

      path = with pkgs; [ vault-bin sops jq nomad curl cacert ];

      script = ''
        set -euo pipefail

        res="$(vault login -method cert -no-store)"
        echo "Our vault token uses $(echo "$res" | jq .auth.policies)"
        VAULT_TOKEN="$(echo "$res" | jq -e -r .auth.client_token)"
        export VAULT_TOKEN

        # Vault Policies

        ${builtins.concatStringsSep "" (lib.mapAttrsToList (name: value: ''
          vault policy write "${name}" "${policy2hcl name value}"
        '') config.services.vault.policies)}

        keepNames=(default root ${
          toString (builtins.attrNames config.services.vault.policies)
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
            echo "Delete policy $name"
            vault policy delete "$name"
          fi
        done

        # Consul Policies

        res="$(vault login -method cert -no-store)"
        echo "Our vault token uses $(echo "$res" | jq .auth.policies)"
        VAULT_TOKEN="$(echo "$res" | jq -e -r .auth.client_token)"
        export VAULT_TOKEN

        echo "linking Consul roles into Vault..."
        set -x
        ${builtins.concatStringsSep "\n" createConsulRoles}
        set +x

        # Nomad Policies

        set -x
        ${builtins.concatStringsSep "\n" createNomadRoles}
        set +x

        keepNames=(${
          toString (builtins.attrNames config.services.nomad.policies)
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
            echo "Delete vault nomad role $role"
            vault delete "nomad/role/$role"
          fi
        done
      '';
    };
}
