{ lib, pkgs, config, ... }:

let
  inherit (lib) mkOverride mkIf attrNames concatStringsSep optional;
  inherit (config.cluster) region instances kms;
  inherit (config.instance) privateIP;

  exportConsulMaster = ''
    set +x
    CONSUL_HTTP_TOKEN="$(
      ${pkgs.jq}/bin/jq -e -r '.acl.tokens.master' < /etc/consul.d/master-token.json
    )"
    export CONSUL_HTTP_TOKEN
    set -x
  '';
in {
  options = { };

  config = {
    systemd.services.consul-initial-tokens =
      mkIf config.services.consul.enable {
        after = [ "consul.service" "consul-policies.service" ];
        requires = [ "consul.service" "consul-policies.service" ];
        wantedBy = [ "multi-user.target" ]
          ++ (optional config.services.vault.enable "vault.service")
          ++ (optional config.services.nomad.enable "nomad.service");
        requiredBy = (optional config.services.vault.enable "vault.service")
          ++ (optional config.services.nomad.enable "nomad.service");

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = "30s";
          inherit (config.systemd.services.consul.serviceConfig)
            WorkingDirectory;
        };

        path = with pkgs; [ consul jq systemd  sops];

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

          # # # # #
          # Vault #
          # # # # #

          if [ ! -s /var/lib/nginx/vault.enc.json ]; then
            mkdir -p /var/lib/nginx

            vaultToken="$(
              consul acl token create \
                -policy-name=vault-client \
                -description "vault-client $(date +%Y-%m-%d-%H-%M-%S)" \
                -format json \
              | jq -e -r .SecretID
            )"

            echo '{}' \
            | jq --arg token "$vaultToken" '.storage.consul.token = $token' \
            | jq --arg token "$vaultToken" '.service_registration.consul.token = $token' \
            | sops \
              --input-type json \
              --output-type json \
              --kms "${kms}" \
              --encrypt \
              /dev/stdin > /var/lib/nginx/vault.enc.json.new

            mv /var/lib/nginx/vault.enc.json.new /var/lib/nginx/vault.enc.json
          fi
        '';
      };

    systemd.services.vault-setup = mkIf config.services.vault.enable {
      after = [ "upload-bootstrap.service" "consul-policies.service" "vault-consul-token.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "30s";
      };

      environment = {
        inherit (config.environment.variables)
          AWS_DEFAULT_REGION VAULT_CACERT VAULT_ADDR VAULT_FORMAT;
      };

      path = with pkgs; [ sops vault-bin glibc gawk consul nomad coreutils jq ];

      script = let
        consulPolicies =
          map (name: ''vault write "consul/roles/${name}" "policies=${name}"'')
          (attrNames config.services.consul.policies);
      in ''
        set -exuo pipefail

        pushd /var/lib/vault

        set +x
        VAULT_TOKEN="$(sops -d --extract '["root_token"]' vault.enc.json)"
        export VAULT_TOKEN
        set -x

        ${concatStringsSep "\n" consulPolicies}
      '';
    };

    systemd.services.nomad-bootstrap = mkIf config.services.nomad.enable {
      after = [ "vault.service" "nomad.service" "network-online.target" ];
      requires = [ "vault.service" "nomad.service" "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "30s";
      };

      environment = {
        inherit (config.environment.variables) AWS_DEFAULT_REGION NOMAD_ADDR;
        CURL_CA_BUNDLE = "/etc/ssl/certs/ca.pem";
      };

      path = with pkgs; [ curl sops coreutils jq nomad gawk glibc vault-bin ];

      # TODO: silence the sensitive parts
      script = ''
        set -exuo pipefail

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

        vault read nomad/config/access &> /dev/null ||
          vault write nomad/config/access \
            address="$NOMAD_ADDR" \
            token="$nomad_vault_token" \
            ca_cert="$(< ${config.services.nomad.tls.caFile})" \
            client_cert="$(< ${config.services.nomad.tls.certFile})" \
            client_key="$(< ${config.services.nomad.tls.keyFile})"

        touch /var/lib/nomad/.bootstrap-done
      '';
    };

    systemd.services.vault-bootstrap = mkIf config.services.vault.enable {
      after = [
        "consul-initial-tokens.service"
        "vault.service"
        "network-online.target"
        "vault-consul-token.service"
      ];
      requires = [ "consul-initial-tokens.service" "vault.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "30s";
      };

      environment = {
        inherit (config.environment.variables)
          AWS_DEFAULT_REGION VAULT_CACERT VAULT_ADDR VAULT_FORMAT;
      };

      path = with pkgs; [ consul vault-bin glibc gawk sops coreutils jq ];

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

        vault secrets list | jq -e '."aws/"'     || vault secrets enable aws
        vault secrets list | jq -e '."consul/"'  || vault secrets enable consul
        vault secrets list | jq -e '."kv/"'      || vault secrets enable -version=2 kv
        vault secrets list | jq -e '."nomad/"'   || vault secrets enable nomad
        vault secrets list | jq -e '."pki/"'     || vault secrets enable pki

        vault auth list | jq -e '."approle/"' || vault auth enable approle
        vault auth list | jq -e '."aws/"'     || vault auth enable aws

        vault secrets tune -max-lease-ttl=8760h pki

        # TODO: pull ARN from terraform outputs or query aws at runtime?

        vault write auth/aws/role/core-iam \
          auth_type=iam \
          bound_iam_principal_arn=arn:aws:iam::276730534310:role/${config.cluster.name}-core \
          policies=default,core \
          max_ttl=1h

        vault write auth/aws/role/clients-iam \
          auth_type=iam \
          bound_iam_principal_arn=arn:aws:iam::276730534310:role/${config.cluster.name}-client \
          policies=default,clients \
          max_ttl=1h

        vault read consul/config/access \
        &> /dev/null \
        || vault write consul/config/access \
          address=127.0.0.1:${toString config.services.consul.ports.https} \
          scheme=https \
          ca_cert="$(< ${config.services.consul.caFile})" \
          client_cert="$(< ${config.services.consul.certFile})" \
          client_key="$(< ${config.services.consul.keyFile})" \
          token="$(
            consul acl token create \
              -policy-name=global-management \
              -description "Vault $(date +%Y-%m-%d-%H-%M-%S)" \
              -format json \
            | jq -e -r .SecretID)"

        touch .bootstrap-done
      '';
    };

    # systemd.services.upload-bootstrap = {
    #   after = [
    #     "nomad-bootstrap.service"
    #     "consul-bootstrap.service"
    #     "vault-bootstrap.service"
    #   ];
    #   requires = [
    #     "nomad-bootstrap.service"
    #     "consul-bootstrap.service"
    #     "vault-bootstrap.service"
    #   ];
    #   wantedBy = [ "multi-user.target" ];
    #
    #   serviceConfig = {
    #     Type = "oneshot";
    #     RemainAfterExit = true;
    #     Restart = "on-failure";
    #     RestartSec = "30s";
    #   };
    #
    #   environment = {
    #     inherit (config.environment.variables)
    #       AWS_DEFAULT_REGION VAULT_CACERT VAULT_ADDR VAULT_FORMAT;
    #   };
    #
    #   path = with pkgs; [ sops vault-bin coreutils jq ];
    #
    #   script = ''
    #     set -exuo pipefail
    #
    #     pushd /run/keys
    #
    #     echo "Waiting for Consul, Vault, and Nomad bootstrap to be done..."
    #
    #     until [ -e /var/lib/consul/.bootstrap-done ]; do sleep 1; done
    #     until [ -e /var/lib/nomad/.bootstrap-done  ]; do sleep 1; done
    #     until [ -e /var/lib/vault/.bootstrap-done  ]; do sleep 1; done
    #
    #     set +x
    #     VAULT_TOKEN="$(sops -d --extract '["root_token"]' vault.enc.json)"
    #     export VAULT_TOKEN
    #     set -x
    #
    #     sops -d --extract '["SecretID"]' consul.enc.json | \
    #       vault kv put kv/bootstrap/consul.token token=-
    #
    #     sops -d --extract '["SecretID"]' nomad.enc.json | \
    #       vault kv put kv/bootstrap/nomad.token token=-
    #
    #     sops -d --extract '["root_token"]' vault.enc.json | \
    #       vault kv put kv/bootstrap/vault.token token=-
    #   '';
    # };
  };
}
