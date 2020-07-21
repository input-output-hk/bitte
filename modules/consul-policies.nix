{ lib, pkgs, config, ... }:
let
  inherit (builtins)
    mapAttrs toJSON readFile concatStringsSep attrValues isString;
  inherit (lib) mkOption mkIf filterAttrs filter flip mkEnableOption;
  inherit (lib.types) attrsOf enum submodule nullOr str listOf;
  inherit (config.instance) bootstrapper;

  consulIntentionsType = submodule {
    options = {
      SourceName = mkOption { type = str; };

      DestinationName = mkOption { type = str; };

      Action = mkOption {
        type = enum [ "allow" "deny" ];
        default = "allow";
      };
    };
  };

  consulRolesType = submodule ({ name, ... }@this: {
    options = {
      name = mkOption {
        type = str;
        default = name;
      };

      description = mkOption {
        type = nullOr str;
        default = null;
        description = ''
          A description of the role.
        '';
      };

      policyIds = mkOption {
        type = listOf str;
        default = [ ];
        description = ''
          IDs of policies to use for this role.
        '';
      };

      policyNames = mkOption {
        type = listOf str;
        default = [ ];
        description = ''
          Names of policies to use for this role.
        '';
      };

      serviceIdentities = mkOption {
        type = listOf str;
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
    policyValueType = enum [ "read" "write" "deny" "list" ];

    consulSinglePolicyType = submodule ({ name, ... }: {
      options = { policy = mkOption { type = policyValueType; }; };
    });

    consulMultiPolicyType = attrsOf (submodule ({ name, ... }: {
      options = { policy = mkOption { type = policyValueType; }; };
    }));

    compute = set:
      if isString set then
        set
      else if set == null then
        set
      else
        mapAttrs (kname: kvalue: { inherit (kvalue) policy; }) set;

    computeValues = set:
      let computed = mapAttrs (k: v: compute v) set;
      in filterAttrs (k: v: v != null && v != { }) computed;

    single = mkOption {
      type = nullOr policyValueType;
      default = null;
    };

    multi = mkOption {
      type = nullOr consulMultiPolicyType;
      default = null;
    };
  in submodule ({ name, ... }@this: {
    options = {
      name = mkOption {
        type = str;
        default = name;
      };

      _json = mkOption {
        type = str;
        default = "";
        apply = _:
          let
            json = toJSON this.config._computed;
            mini = pkgs.writeText "consul-policy.mini.json" json;
          in pkgs.runCommandNoCCLocal "consul-policy.json" { } ''
            ${pkgs.jq}/bin/jq -S < ${mini} > $out
          '';
      };

      # TODO: make this less horrible
      _computed = mkOption {
        type = str;
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
    services.consul.policies = mkOption {
      type = attrsOf consulPoliciesType;
      default = { };
    };

    services.consul.roles = mkOption {
      type = attrsOf consulRolesType;
      default = { };
    };

    services.consul.intentions = mkOption {
      type = listOf consulIntentionsType;
      default = [ ];
    };

    services.consul-policies.enable =
      mkEnableOption "Create consul policies on this machine";
  };

  # TODO: rename to consul-acl
  config = mkIf config.services.consul-policies.enable {
    systemd.services.consul-policies = {
      after = [ "consul.service" ];
      requires = [ "consul.service" ];
      wantedBy = [ "multi-user.target" ];
      description = "Service that creates all Consul policies and tokens.";

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "30s";
        ExecStartPre = pkgs.ensureDependencies [ "consul" ];
      };

      path = with pkgs; [ consul coreutils jq ];

      script = let
        policies = flip mapAttrs config.services.consul.policies
          (polName: policy: pkgs.writeTextDir polName (readFile policy._json));

        policyDir = pkgs.symlinkJoin {
          name = "consul-policies";
          paths = attrValues policies;
        };

        roles = flip mapAttrs config.services.consul.roles (ruleName: rule:
          let
            policyIds = concatStringsSep " "
              (map (id: "-policy-id ${id}") rule.policyIds);

            policyNames = concatStringsSep " "
              (map (name: "-policy-name ${name}") rule.policyNames);

            serviceIdentities = concatStringsSep " "
              (map (name: "service-identities ${name}") rule.serviceIdentities);

            description = toString rule.description;

            cmdify = list: toString (filter (e: e != null) list);

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

            roleActions =
              mapAttrs (name: value: pkgs.writeTextDir name (cmdify value))
              actions;

          in pkgs.symlinkJoin {
            name = "consul-role-actions";
            paths = attrValues roleActions;
          });

        rolesDir = pkgs.symlinkJoin {
          name = "consul-roles";
          paths = attrValues roles;
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

        for policy in $(consul acl policy list -format json | jq -r '.[].Name'); do
          name="$(basename "$policy")"

          [ -s "${policyDir}/$policy" ] && continue
          [ "global-management" = "$name" ] && continue

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

          echo "Deleting role $name"
          consul acl role delete -name "$name"
        done
      '';
    };
  };
}
