{ lib, pkgs, config, ... }:

let
  inherit (config.cluster) domain kms region adminNames;

  cfg = config.services.bootstrap;

  exportConsulMaster = ''
    set +x
    CONSUL_HTTP_TOKEN="$(
      ${pkgs.jq}/bin/jq -e -r '.acl.tokens.master' < /etc/consul.d/secrets.json
    )"
    export CONSUL_HTTP_TOKEN
    set -x
  '';

  initialVaultSecrets = ''
    sops --decrypt --extract '["encrypt"]' ${
      config.secrets.encryptedRoot + "/consul-clients.json"
    } | vault kv put kv/bootstrap/clients/consul encrypt=-

    sops --decrypt --extract '["server"]["encrypt"]' ${
      config.secrets.encryptedRoot + "/nomad.json"
    } | vault kv put kv/bootstrap/clients/nomad encrypt=-

    sops --decrypt ${
      config.secrets.encryptedRoot + "/nix-cache.json"
    } | vault kv put kv/bootstrap/cache/nix-key -
  '';
in {
  options = {
    services.bootstrap = {
      extraConsulInitialTokensConfig = lib.mkOption {
        type = with lib.types; lines;
        default = "";
        description = "Extra Consul initial tokens configuration.";
      };
      extraNomadBootstrapConfig = lib.mkOption {
        type = with lib.types; lines;
        default = "";
        description = "Extra Nomad bootstrap configuration.";
      };
      extraVaultBootstrapConfig = lib.mkOption {
        type = with lib.types; lines;
        default = "";
        description = "Extra Vault bootstrap configuration.";
      };
      extraVaultSetupConfig = lib.mkOption {
        type = with lib.types; lines;
        default = "";
        description = "Extra Vault setup configuration.";
      };
    };
  };

  config = {
    systemd.services.consul-initial-tokens =
      lib.mkIf config.services.consul.enable {
        after = [ "consul.service" "consul-acl.service" ];
        wantedBy = [ "multi-user.target" ]
          ++ (lib.optional config.services.vault.enable "vault.service")
          ++ (lib.optional config.services.nomad.enable "nomad.service");
        requiredBy = (lib.optional config.services.vault.enable "vault.service")
          ++ (lib.optional config.services.nomad.enable "nomad.service");

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = "20s";
          WorkingDirectory = "/run/keys";
          ExecStartPre = pkgs.ensureDependencies [ "consul" "consul-acl" ];
        };

        path = with pkgs; [ consul jq systemd sops ];

        script = let
          mkToken = purpose: policy: ''
            consul acl token create \
              -policy-name=${policy} \
              -description "${purpose} $(date '+%Y-%m-%d %H:%M:%S')" \
              -expires-ttl 1h \
              -format json | \
              jq -e -r .SecretID
          '';
        in ''
          set -euo pipefail

          ${exportConsulMaster}

          ##########
          # Consul #
          ##########

          if [ ! -s /etc/consul.d/tokens.json ]; then
            default="$(${
              mkToken "consul-server-default" "consul-server-default"
            })"
            agent="$(${mkToken "consul-server-agent" "consul-server-agent"})"

            echo '{}' \
            | jq \
              -S \
              --arg default "$default" \
              --arg agent "$agent" \
              '.acl.tokens = { default: $default, agent: $agent }' \
            > /etc/consul.d/tokens.json.new

            mv /etc/consul.d/tokens.json.new /etc/consul.d/tokens.json

            systemctl restart consul.service
          fi

          # # # # #
          # Nomad #
          # # # # #

          if [ ! -s /etc/nomad.d/consul-token.json ]; then
            nomad="$(${mkToken "nomad-server" "nomad-server"})"

            mkdir -p /etc/nomad.d

            echo '{}' \
            | jq --arg nomad "$nomad" '.consul.token = $nomad' \
            > /etc/nomad.d/consul-token.json.new

            mv /etc/nomad.d/consul-token.json.new /etc/nomad.d/consul-token.json
          fi

          ################
          # Extra Config #
          ################

          ${cfg.extraConsulInitialTokensConfig}
        '';
      };

    systemd.services.vault-setup = lib.mkIf config.services.vault.enable {
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "20s";
      };

      environment = {
        inherit (config.environment.variables)
          AWS_DEFAULT_REGION VAULT_CACERT VAULT_FORMAT;
        VAULT_ADDR = "https://127.0.0.1:8200";
      };

      path = with pkgs; [ sops vault-bin consul nomad coreutils jq curl ];

      script = let
        consulPolicies =
          map (name: ''vault write "consul/roles/${name}" "policies=${name}"'')
          (lib.attrNames config.services.consul.policies);

        nomadClusterRole = pkgs.toPrettyJSON "nomad-cluster-role" {
          disallowed_policies = "nomad-server,admin,core,client";
          token_explicit_max_ttl = 0;
          name = "nomad-cluster";
          orphan = true;
          token_period = 259200;
          renewable = true;
        };
      in ''
        set -exuo pipefail

        pushd /var/lib/vault

        set +x
        VAULT_TOKEN="$(sops -d --extract '["root_token"]' vault.enc.json)"
        export VAULT_TOKEN
        set -x

        ${lib.concatStringsSep "\n" consulPolicies}

        vault write /auth/token/roles/nomad-cluster @${nomadClusterRole}

        # Finally allow IAM roles to login to Vault

        arn="$(
          curl -f -s http://169.254.169.254/latest/meta-data/iam/info \
          | jq -e -r .InstanceProfileArn \
          | sed 's/:instance.*//'
        )"

        vault write auth/aws/role/core-iam \
          auth_type=iam \
          bound_iam_principal_arn="$arn:role/${config.cluster.name}-core" \
          policies=default,core,nomad-server

        vault write auth/aws/role/${config.cluster.name}-core \
          auth_type=iam \
          bound_iam_principal_arn="$arn:role/${config.cluster.name}-core" \
          policies=default,core,nomad-server

        vault write auth/aws/role/${config.cluster.name}-client \
          auth_type=iam \
          bound_iam_principal_arn="$arn:role/${config.cluster.name}-client" \
          policies=default,client,nomad-server \
          period=24h

        ${lib.concatStringsSep "\n" (lib.forEach adminNames (name: ''
          vault write "auth/aws/role/${name}" \
            auth_type=iam \
            bound_iam_principal_arn="$arn:user/${name}" \
            policies=default,admin \
            max_ttl=24h
        ''))}

        ${initialVaultSecrets}

        ################
        # Extra Config #
        ################

        ${cfg.extraVaultSetupConfig}
      '';
    };

    systemd.services.nomad-bootstrap = lib.mkIf config.services.nomad.enable {
      after = [ "vault.service" "nomad.service" "network-online.target" ];
      wants = [ "vault.service" "nomad.service" "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "20s";
        ExecStartPre = pkgs.ensureDependencies [ "vault" "nomad" ];
      };

      environment = {
        inherit (config.environment.variables) AWS_DEFAULT_REGION NOMAD_ADDR;
        CURL_CA_BUNDLE = "/etc/ssl/certs/full.pem";
      };

      path = with pkgs; [ curl sops coreutils jq nomad vault-bin gawk ];

      script = ''
        set -euo pipefail

        pushd /var/lib/nomad

        if [ -e .bootstrap-done ]; then
          echo "Nomad bootstrap already done."
          exit 0
        fi

        if [ ! -s bootstrap.token ]; then
          token="$(
            curl -f --no-progress-meter -X POST "$NOMAD_ADDR/v1/acl/bootstrap" \
            | jq -e -r .SecretID
          )"
          echo "$token" > bootstrap.token.tmp
          [ -s bootstrap.token.tmp ]
          mv bootstrap.token.tmp bootstrap.token
        fi

        NOMAD_TOKEN="$(< bootstrap.token)"
        export NOMAD_TOKEN

        VAULT_TOKEN="$(sops -d --extract '["root_token"]' /var/lib/vault/vault.enc.json)"
        export VAULT_TOKEN

        nomad_vault_token="$(
          nomad acl token create -type management \
          | grep 'Secret ID' \
          | awk '{ print $4 }'
        )"

        # TODO: this will probably have permission issues and expiring cert.
        vault read nomad/config/access &> /dev/null ||
          vault write nomad/config/access \
            address="$NOMAD_ADDR" \
            token="$nomad_vault_token" \
            ca_cert="$(< ${config.services.nomad.tls.ca_file})" \
            client_cert="$(< ${config.services.nomad.tls.cert_file})" \
            client_key="$(< ${config.services.nomad.tls.key_file})"

        ################
        # Extra Config #
        ################

        ${cfg.extraNomadBootstrapConfig}

        touch /var/lib/nomad/.bootstrap-done
      '';
    };

    systemd.services.vault-bootstrap = lib.mkIf config.services.vault.enable {
      after = [ "vault.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "20s";
        ExecStartPre =
          pkgs.ensureDependencies [ "consul-initial-tokens" "vault" ];
      };

      environment = {
        inherit (config.environment.variables)
          AWS_DEFAULT_REGION VAULT_CACERT VAULT_FORMAT;
        VAULT_ADDR = "https://127.0.0.1:8200/";
      };

      path = with pkgs; [ consul vault-bin sops coreutils jq gnused curl ];

      script = ''
        set -exuo pipefail

        pushd /var/lib/vault

        if [ -e .bootstrap-done ]; then
          echo "Vault bootstrap already done."
          exit 0
        fi

        echo "waiting for Vault to be responsive"

        until vault status &> /dev/null; do
          [[ $? -eq 2 ]] && break
          sleep 1
        done

        echo "Vault launched"

        if vault status | jq -e 'select(.sealed == false)'; then
          echo "Vault already unsealed"
        else
          vault operator init \
            -recovery-shares 1 \
            -recovery-threshold 1 | \
              sops \
              --input-type json \
              --output-type json \
              --kms "${kms}" \
              --encrypt \
              /dev/stdin > vault.enc.json.tmp

          if [ -s vault.enc.json.tmp ]; then
            mv vault.enc.json.tmp vault.enc.json
          else
            echo "Couldnt't bootstrap, something went fatally wrong!"
            exit 1
          fi
        fi

        set +x
        VAULT_TOKEN="$(sops -d --extract '["root_token"]' vault.enc.json)"
        export VAULT_TOKEN

        ${exportConsulMaster}

        # vault audit enable socket address=127.0.0.1:9090 socket_type=tcp

        secrets="$(vault secrets list)"

        echo "$secrets" | jq -e '."aws/"'         || vault secrets enable aws
        echo "$secrets" | jq -e '."consul/"'      || vault secrets enable consul
        echo "$secrets" | jq -e '."kv/"'          || vault secrets enable -version=2 kv
        echo "$secrets" | jq -e '."nomad/"'       || vault secrets enable nomad
        echo "$secrets" | jq -e '."pki/"'         || vault secrets enable pki
        echo "$secrets" | jq -e '."pki-consul/"'  || vault secrets enable -path pki-consul pki

        auth="$(vault auth list)"

        echo "$auth" | jq -e '."aws/"'     || vault auth enable aws

        # This lets Vault issue Consul tokens

        vault read consul/config/access \
        &> /dev/null \
        || vault write consul/config/access \
          ca_cert="$(< ${config.services.consul.caFile})" \
          client_cert="$(< ${config.services.consul.certFile})" \
          client_key="$(< ${config.services.consul.keyFile})" \
          token="$(
            consul acl token create \
              -policy-name=global-management \
              -description "Vault $(date +%Y-%m-%d-%H-%M-%S)" \
              -format json \
            | jq -e -r .SecretID)"

        vault secrets tune -max-lease-ttl=87600h pki

        vault write \
          pki/config/urls \
          issuing_certificates="https://vault.${domain}:8200/v1/pki/ca" \
          crl_distribution_points="https://vault.${domain}:8200/v1/pki/crl"

        vault write \
          pki/roles/server \
          key_type=ec \
          key_bits=256 \
          allow_any_name=true \
          enforce_hostnames=false \
          generate_lease=true \
          max_ttl=72h

        vault write \
          pki/roles/client \
          key_type=ec \
          key_bits=256 \
          allowed_domains=service.consul,${region}.consul \
          allow_subdomains=true \
          generate_lease=true \
          max_ttl=223h

        vault write \
          pki/roles/admin \
          key_type=ec \
          key_bits=256 \
          allow_any_name=true \
          enforce_hostnames=false \
          generate_lease=true \
          max_ttl=12h

        ${initialVaultSecrets}

        ################
        # Extra Config #
        ################

        ${cfg.extraVaultBootstrapConfig}

        touch .bootstrap-done
      '';
    };
  };
}
