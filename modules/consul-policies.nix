{ lib, pkgs, config, bittelib, ... }:
let
  inherit (config.instance) bootstrapper;

  consulIntentionsType = with lib.types;
    submodule {
      options = {
        sourceName = lib.mkOption { type = with lib.types; str; };
        destinationName = lib.mkOption { type = with lib.types; str; };
        action = lib.mkOption {
          type = with lib.types; enum [ "allow" "deny" ];
          default = "allow";
        };
      };
    };

  consulRolesType = with lib.types;
    submodule ({ name, ... }@this: {
      options = {
        name = lib.mkOption {
          type = with lib.types; str;
          default = name;
        };

        description = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
          description = ''
            A description of the role.
          '';
        };

        policyIds = lib.mkOption {
          type = with lib.types; listOf str;
          default = [ ];
          description = ''
            IDs of policies to use for this role.
          '';
        };

        policyNames = lib.mkOption {
          type = with lib.types; listOf str;
          default = [ ];
          description = ''
            Names of policies to use for this role.
          '';
        };

        serviceIdentities = lib.mkOption {
          type = with lib.types; listOf str;
          default = [ ];
          description = ''
            Name of a service identity to use for this role.
            May be specified multiple times.
            Format is the SERVICENAME or SERVICENAME:DATACENTER1,DATACENTER2,...
          '';
        };
      };
    });

  consulPoliciesType = let
    policyValueType = with lib.types; enum [ "read" "write" "deny" "list" ];

    consulSinglePolicyType = with lib.types;
      submodule ({ name, ... }: {
        options = {
          policy = lib.mkOption { type = with lib.types; policyValueType; };

          intentions = lib.mkOption {
            type = with lib.types; policyValueType;
            default = "deny";
          };
        };
      });

    consulMultiPolicyType = with lib.types;
      attrsOf (submodule ({ name, ... }: {
        options = {
          policy = lib.mkOption { type = with lib.types; policyValueType; };

          intentions = lib.mkOption {
            type = with lib.types; policyValueType;
            default = "deny";
          };
        };
      }));

    compute = set:
      if builtins.isString set then
        set
      else if set == null then
        set
      else
        builtins.mapAttrs
        (kname: kvalue: { inherit (kvalue) policy intentions; }) set;

    computeValues = set:
      let computed = builtins.mapAttrs (k: compute) set;
      in lib.filterAttrs (k: v: v != null && v != { }) computed;

    single = lib.mkOption {
      type = with lib.types; nullOr policyValueType;
      default = null;
    };

    multi = lib.mkOption {
      type = with lib.types; nullOr consulMultiPolicyType;
      default = null;
    };
  in with lib.types;
  submodule ({ name, ... }@this: {
    options = {
      name = lib.mkOption {
        type = with lib.types; str;
        default = name;
      };

      _json = lib.mkOption {
        type = with lib.types; str;
        default = "";
        apply = _:
          let json = builtins.toJSON this.config._computed;
          in pkgs.runCommandNoCCLocal "consul-policy.json" { } ''
            echo ${json} | ${pkgs.jq}/bin/jq -S > $out
          '';
      };

      # TODO: make this less horrible
      _computed = lib.mkOption {
        type = with lib.types; str;
        default = "";
        apply = _:
          computeValues {
            inherit (this.config)
              acl event key node operator query service session;
            agent_prefix = this.config.agentPrefix;
            event_prefix = this.config.eventPrefix;
            key_prefix = this.config.keyPrefix;
            node_prefix = this.config.nodePrefix;
            query_prefix = this.config.queryPrefix;
            service_prefix = this.config.servicePrefix;
            session_prefix = this.config.sessionPrefix;
          };
      };

      acl = single;
      agent = multi;
      agentPrefix = multi;
      event = multi;
      eventPrefix = multi;
      key = multi;
      keyPrefix = multi;
      keyring = single;
      node = multi;
      nodePrefix = multi;
      operator = single;
      query = multi;
      queryPrefix = multi;
      service = multi;
      servicePrefix = multi;
      session = multi;
      sessionPrefix = multi;
    };
  });

in {
  options = {
    services.consul.policies = lib.mkOption {
      type = with lib.types; attrsOf consulPoliciesType;
      default = { };
    };

    services.consul.roles = lib.mkOption {
      type = with lib.types; attrsOf consulRolesType;
      default = { };
    };

    services.consul.intentions = lib.mkOption {
      type = with lib.types; listOf consulIntentionsType;
      default = [ ];
    };

    services.consul-acl.enable =
      lib.mkEnableOption "Create consul policies on this machine";
  };

  # TODO: rename to consul-acl
  config = lib.mkIf config.services.consul-acl.enable {
    systemd.services.consul-acl = {
      after = [ "consul.service" ];
      wants = [ "consul.service" ];
      wantedBy = [ "multi-user.target" ];
      description = "Service that creates all Consul policies and tokens.";

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "30s";
        ExecStartPre = bittelib.ensureDependencies pkgs [ "consul" ];
      };

      path = with pkgs; [ consul coreutils jq ];

      script = let
        policies = lib.flip builtins.mapAttrs config.services.consul.policies
          (polName: policy:
            pkgs.writeTextDir polName (builtins.readFile policy._json));

        policyDir = pkgs.symlinkJoin {
          name = "consul-acl";
          paths = builtins.attrValues policies;
        };

        roles = lib.flip builtins.mapAttrs config.services.consul.roles
          (ruleName: rule:
            let
              policyIds = builtins.concatStringsSep " "
                (map (id: "-policy-id ${id}") rule.policyIds);

              policyNames = builtins.concatStringsSep " "
                (map (name: "-policy-name ${name}") rule.policyNames);

              serviceIdentities = builtins.concatStringsSep " "
                (map (name: "service-identities ${name}")
                  rule.serviceIdentities);

              description = toString rule.description;

              cmdify = list: toString (lib.filter (e: e != null) list);

              actions = {
                "${ruleName}/create" = [
                  "consul acl role create"
                  "-name"
                  rule.name
                  policyIds
                  policyNames
                  serviceIdentities
                  description
                ];

                "${ruleName}/update" = [
                  "consul acl role update"
                  "-no-merge"
                  "-name"
                  rule.name
                  policyIds
                  policyNames
                  serviceIdentities
                  description
                  "$@"
                ];
              };

              roleActions = builtins.mapAttrs
                (name: value: pkgs.writeTextDir name (cmdify value)) actions;

            in pkgs.symlinkJoin {
              name = "consul-role-actions";
              paths = builtins.attrValues roleActions;
            });

        rolesDir = pkgs.symlinkJoin {
          name = "consul-roles";
          paths = builtins.attrValues roles;
        };
      in ''
        set -euo pipefail

        # set +x
        CONSUL_HTTP_TOKEN="$(
          jq -e -r '.acl.tokens.master' < /etc/consul.d/secrets.json
        )"
        export CONSUL_HTTP_TOKEN
        # set -x

        # Add/Update Consul Policies

        for policy in ${policyDir}/*; do
          [ -s "$policy" ] || continue
          echo "Checking policy $policy ..."

          name="$(basename "$policy")"

          if consul acl policy read -name "$name" &> /dev/null; then
            echo "Resetting policy $name"
            consul acl policy update \
              -no-merge \
              -name "$name" \
              -description "Generated from $policy" \
              -rules @"$policy"
          else
            echo "Creating policy $name"
            consul acl policy create \
              -name "$name" \
              -description "Generated from $policy" \
              -rules @"$policy"
          fi
        done

        # Remove Consul Policies
        keepNames=(${
          toString
          (__attrNames config.tf.hydrate.configuration.locals.policies.consul)
        })

        for policy in $(consul acl policy list -format json | jq -r '.[].Name'); do
          name="$(basename "$policy")"

          [ -s "${policyDir}/$policy" ] && continue
          [ "global-management" = "$name" ] && continue
          [ " ''${keepNames[*]} " =~ " $name " ] && continue

          echo "Deleting policy $name"
          consul acl policy delete -name "$name"
        done

        # Add/Update Consul Roles
        set -x

        for role in ${rolesDir}/*; do
          [ -d "$role" ] || continue
          echo "Checking role $role ..."

          name="$(basename "$role")"

          json="$(consul acl role read -name "$name" -format json || true)"

          if [ -n "$json" ]; then
            echo "Resetting role $name"
            . "$role/update" -id "$(echo "$json" | jq -r .ID)"
          else
            echo "Creating role $name"
            . "$role/create"
          fi
        done

        # Remove Consul Roles

        for role in $(consul acl role list -format json | jq -r '.[].Name'); do
          name="$(basename "$role")"

          [ -d "${rolesDir}/$role" ] && continue
          [ " ''${keepNames[*]} " =~ " $role " ] && continue

          echo "Deleting role $name"
          consul acl role delete -name "$name"
        done
      '';
    };
  };
}
