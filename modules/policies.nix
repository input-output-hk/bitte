{ pkgs, lib, config, ... }:
let
  inherit (builtins) toJSON readFile attrValues typeOf toFile;
  inherit (lib)
    mkOption mkOptionType mapAttrs filterAttrs mkIf mkEnableOption
    mapAttrsToList concatStringsSep isString makeBinPath filter remove
    listToAttrs;
  inherit (lib.types) listOf enum attrsOf str submodule nullOr;
  inherit (pkgs) jq writeText runCommandNoCCLocal;

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

  nomadPoliciesType = submodule { options = { }; };

in {
  options = {
    services.vault.policies = mkOption {
      type = attrsOf vaultPoliciesType;
      default = { };
    };

    services.nomad.policies = mkOption {
      type = attrsOf nomadPoliciesType;
      default = { };
    };

    services.vault-acl.enable = mkEnableOption "Create Vault roles";
  };

  # TODO: also remove them again.
  config.systemd.services.vault-acl = mkIf config.services.vault-acl.enable {
    after = [ "vault-bootstrap.service" ];
    requires = [ "vault-bootstrap.service" ];
    wantedBy = [ "multi-user.target" ];
    description = "Service that creates all Vault policies.";

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "30s";

      WorkingDirectory = "/var/lib/vault";
    };

    environment = {
      inherit (config.environment.variables)
        AWS_DEFAULT_REGION VAULT_CACERT VAULT_ADDR VAULT_FORMAT;
    };

    path = with pkgs; [ vault-bin glibc gawk sops ];

    script = let
      rmModule = arg: removeAttrs arg [ "_module" ];

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
    in ''
      set -euo pipefail

      set +x
      VAULT_TOKEN="$(sops -d --extract '["root_token"]' vault.enc.json)"
      export VAULT_TOKEN
      set -x

      ${concatStringsSep "\n" (mapAttrsToList (name: value: ''
        vault policy write "${name}" "${policy2hcl name value}"
      '') config.services.vault.policies)}
    '';
  };
}
