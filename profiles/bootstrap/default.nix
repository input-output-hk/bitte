{
  lib,
  pkgs,
  config,
  bittelib,
  pkiFiles,
  hashiTokens,
  gossipEncryptionMaterial,
  nodeName,
  etcEncrypted,
  ...
}: let
  inherit (config.currentCoreNode) datacenter deployType privateIP;

  cfg = config.services.bootstrap;
  premSimDomain = config.currentCoreNode.domain;

  exportVaultRoot =
    if (deployType == "aws")
    then ''
      set +x
      VAULT_TOKEN="$(
        sops -d --extract '["root_token"]' /var/lib/vault/vault.enc.json
      )"
      export VAULT_TOKEN
      set -x
    ''
    else ''
      set +x
      VAULT_TOKEN="$(
        rage -i /etc/ssh/ssh_host_ed25519_key -d /var/lib/vault/vault-bootstrap.json.age | jq -r '.root_token'
      )"
      export VAULT_TOKEN
      set -x
    '';

  exportConsulMaster = ''
    set +x
    CONSUL_HTTP_TOKEN="$(
      jq -e -r '.acl.tokens.master' < ${gossipEncryptionMaterial.consul}
    )"
    export CONSUL_HTTP_TOKEN
    set -x
  '';

  initialVaultSecrets =
    if deployType == "aws"
    then ''
      sops --decrypt --extract '["encrypt"]' ${etcEncrypted}/consul-clients.json \
      | vault kv put kv/bootstrap/clients/consul encrypt=-

      sops --decrypt --extract '["server"]["encrypt"]' ${etcEncrypted}/nomad.json \
      | vault kv put kv/bootstrap/clients/nomad encrypt=-

      sops --decrypt ${etcEncrypted}/nix-cache.json \
      | vault kv put kv/bootstrap/cache/nix-key -
    ''
    else ''
      rage -i /etc/ssh/ssh_host_ed25519_key -d ${config.age.encryptedRoot + "/consul/encrypt.age"} \
        | tr -d '\n' | vault kv put kv/bootstrap/clients/consul encrypt=-
      rage -i /etc/ssh/ssh_host_ed25519_key -d ${config.age.encryptedRoot + "/nomad/encrypt.age"} \
        | tr -d '\n' | vault kv put kv/bootstrap/clients/nomad encrypt=-
      set +x
      NIX_KEY_SECRET="$(
        rage -i /etc/ssh/ssh_host_ed25519_key -d ${config.age.encryptedRoot + "/nix/key.age"}
      )"
      NIX_KEY_PUBLIC="$(cat ${config.age.encryptedRoot + "/nix/key.pub"})"
      echo '{}' \
      | jq \
        -S \
        --arg NIX_KEY_SECRET "$NIX_KEY_SECRET" \
        --arg NIX_KEY_PUBLIC "$NIX_KEY_PUBLIC" \
        '{ private: $NIX_KEY_SECRET, public: $NIX_KEY_PUBLIC }' \
      | vault kv put kv/bootstrap/cache/nix-key -
      set -x
    '';

  initialVaultStaticSecrets = let
    mkStaticTokenCheck = policy: ''
      echo "Checking for ${policy} static token..."
      if ! vault kv get -field token "kv/bootstrap/static-tokens/clients/${policy}" &> /dev/null; then
        echo "Creating ${policy} static token..."
        token="$(${mkStaticToken "${policy}"})"
        echo "Storing ${policy} static token in Vault secrets."
        vault kv put "kv/bootstrap/static-tokens/clients/${policy}" token="$token"
      else
        echo "Found ${policy} static token."
      fi
    '';
    mkStaticToken = policy: ''
      consul acl token create \
        -policy-name="${policy}" \
        -description "${policy} static $(date '+%Y-%m-%d %H:%M:%S')" \
        -format json | \
        jq -e -r .SecretID
    '';
  in ''
    set +x
    ${mkStaticTokenCheck "consul-agent"}
    ${mkStaticTokenCheck "consul-default"}
    ${mkStaticTokenCheck "consul-server-agent"}
    ${mkStaticTokenCheck "consul-server-default"}
    set -x
  '';
in {
  imports = [./options.nix];

  config = {
    systemd.services.consul-initial-tokens = lib.mkIf config.services.consul.enable {
      after = ["consul.service" "consul-acl.service"];
      wantedBy =
        ["multi-user.target"]
        ++ (lib.optional config.services.vault.enable "vault.service")
        ++ (lib.optional config.services.nomad.enable "nomad.service");
      requiredBy =
        (lib.optional config.services.vault.enable "vault.service")
        ++ (lib.optional config.services.nomad.enable "nomad.service");

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "20s";
        WorkingDirectory = "/run/keys";
        ExecStartPre =
          bittelib.ensureDependencies pkgs ["consul" "consul-acl"];
      };

      path = with pkgs; [consul jq systemd sops];

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

        if [ ! -s ${hashiTokens.consuld-json} ]; then
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
          > ${hashiTokens.consuld-json}.new

          mv ${hashiTokens.consuld-json}.new ${hashiTokens.consuld-json}

          systemctl restart consul.service
        fi

        # # # # #
        # Nomad #
        # # # # #

        if [ ! -s ${hashiTokens.nomadd-consul-json} ]; then
          nomad="$(${mkToken "nomad-server" "nomad-server"})"

          mkdir -p /etc/nomad.d

          echo '{}' \
          | jq --arg nomad "$nomad" '.consul.token = $nomad' \
          > ${hashiTokens.nomadd-consul-json}.new

          mv ${hashiTokens.nomadd-consul-json}.new ${hashiTokens.nomadd-consul-json}
        fi

        ################
        # Extra Config #
        ################

        ${cfg.extraConsulInitialTokensConfig}
      '';
    };

    systemd.services.vault-setup = lib.mkIf config.services.vault.enable {
      after = ["consul-acl.service" "${hashiTokens.consul-vault-srv}.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "20s";
        ExecStartPre = bittelib.ensureDependencies pkgs [
          "consul-acl"
          "${hashiTokens.consul-vault-srv}"
        ];
      };

      environment =
        {
          inherit (config.environment.variables) VAULT_CACERT VAULT_FORMAT VAULT_ADDR;
        }
        // (lib.optionalAttrs (config.environment.variables ? "AWS_DEFAULT_REGION") {
          inherit (config.environment.variables) AWS_DEFAULT_REGION;
        });

      path = with pkgs; [sops rage vault-bin consul nomad coreutils jq curl];

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

        ${exportVaultRoot}
        ${exportConsulMaster}

        ${lib.concatStringsSep "\n" consulPolicies}

        vault write /auth/token/roles/nomad-cluster @${nomadClusterRole}

        ${lib.optionalString (deployType == "aws") ''
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
            period=24h || true # only available after 'tf.clients.apply'

          vault write auth/aws/role/${config.cluster.name}-routing \
            auth_type=iam \
            bound_iam_principal_arn="$arn:role/${config.cluster.name}-core" \
            policies=default,routing \
            period=24h

          vault write auth/aws/role/${config.cluster.name}-hydra \
            auth_type=iam \
            bound_iam_principal_arn="$arn:role/${config.cluster.name}-core" \
            policies=default,hydra \
            period=24h || true # only available if a hydra is deployed

          ${lib.concatStringsSep "\n" (lib.forEach config.cluster.adminNames (name: ''
            vault write "auth/aws/role/${name}" \
              auth_type=iam \
              bound_iam_principal_arn="$arn:user/${name}" \
              policies=default,admin \
              max_ttl=24h
          ''))}
        ''}

        ${
          lib.optionalString (deployType != "aws") ''
            # Finally allow cert roles to login to Vault

            vault write auth/cert/certs/vault-agent-core \
              display_name=vault-agent-core \
              policies=vault-agent-core \
              certificate=@"/etc/ssl/certs/server.pem" \
              ttl=3600

            vault write auth/cert/certs/vault-agent-client \
              display_name=vault-agent-client \
              policies=vault-agent-client \
              certificate=@"/etc/ssl/certs/client.pem" \
              ttl=3600

            vault write auth/cert/certs/vault-agent-routing \
              display_name=vault-agent-routing \
              policies=routing \
              certificate=@"/etc/ssl/certs/client.pem" \
              ttl=3600''
        }

        ${initialVaultSecrets}

        ${initialVaultStaticSecrets}

        ################
        # Extra Config #
        ################

        ${cfg.extraVaultSetupConfig}
      '';
    };

    systemd.services.nomad-bootstrap = lib.mkIf config.services.nomad.enable {
      after = ["vault.service" "nomad.service" "network-online.target"];
      wants = ["vault.service" "nomad.service" "network-online.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "20s";
        ExecStartPre = bittelib.ensureDependencies pkgs ["vault" "nomad"];
      };

      environment =
        {
          inherit (config.environment.variables) NOMAD_ADDR;
          CURL_CA_BUNDLE =
            if deployType == "aws"
            then pkiFiles.certChainFile
            else pkiFiles.serverCertChainFile;
        }
        // (lib.optionalAttrs (config.environment.variables ? "AWS_DEFAULT_REGION") {
          inherit (config.environment.variables) AWS_DEFAULT_REGION;
        });

      path = with pkgs; [curl sops rage coreutils jq nomad vault-bin gawk];

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

        ${exportVaultRoot}

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
      after = [
        "consul-initial-tokens.service"
        "vault.service"
        "${hashiTokens.consul-vault-srv}.service"
      ];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "20s";
        ExecStartPre = bittelib.ensureDependencies pkgs [
          "consul-initial-tokens"
          "${hashiTokens.consul-vault-srv}"
        ];
      };

      environment =
        {
          inherit (config.environment.variables) VAULT_CACERT VAULT_FORMAT VAULT_ADDR;
        }
        // (lib.optionalAttrs (config.environment.variables ? "AWS_DEFAULT_REGION") {
          inherit (config.environment.variables) AWS_DEFAULT_REGION;
        });

      path = with pkgs; [
        consul
        vault-bin
        sops
        rage
        coreutils
        jq
        gnused
        curl
        netcat
        openssh
      ];

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
          ${
          if deployType == "aws"
          then ''
            vault operator init \
              -recovery-shares 1 \
              -recovery-threshold 1 | \
                sops \
                --input-type json \
                --output-type json \
                --kms "${config.cluster.kms}" \
                --encrypt \
                /dev/stdin > vault.enc.json.tmp

            if [ -s vault.enc.json.tmp ]; then
              mv vault.enc.json.tmp vault.enc.json
            else
              echo "Couldnt't bootstrap, something went fatally wrong!"
              exit 1
            fi''
          else ''
            vault operator init > /var/lib/vault/vault-bootstrap.json
            readarray -t unseal_keys < <(jq < /var/lib/vault/vault-bootstrap.json -e -r '.unseal_keys_b64[0,1,2]')

            for vault in ${lib.concatStringsSep " " config.services.vault.serverNodeNames}; do
              echo "Unsealing $vault"
              for key in "''${unseal_keys[@]}"; do
                result="${toString (builtins.length config.services.vault.serverNodeNames * 3)}"
                until [ "$result" -eq 0 ]; do
                  echo "Unsealing $vault with key"
                  ssh "$vault" \
                    -i /etc/ssh/ssh_host_ed25519_key \
                    -o UserKnownHostsFile=/dev/null \
                    -o StrictHostKeyChecking=no \
                    -- 'bash -c "until CHECK=\"$(vault status)\" &> /dev/null; do [[ $? -eq 2 ]] && break; sleep 1; done; until vault status | jq -e \"select(.initialized == true)\"; do sleep 1; done; vault operator unseal "'"$key"
                  result="$?"
                  echo "Unsealed $vault with key result: $result"
                  sleep 1
                done
              done
              echo "Sleeping 10 seconds to allow next vault to initialize..."
              sleep 10
            done
            rage -i /etc/ssh/ssh_host_ed25519_key -a -e /var/lib/vault/vault-bootstrap.json \
              -o /var/lib/vault/vault-bootstrap.json.age.tmp
            if [ -s /var/lib/vault/vault-bootstrap.json.age.tmp ]; then
              rm /var/lib/vault/vault-bootstrap.json
              [ -s /var/lib/vault/vault-bootstrap.json.age ] && mv /var/lib/vault/vault-bootstrap.json.age /var/lib/vault/vault-bootstrap.json.age-$(date -u +"%F-%T")
              mv /var/lib/vault/vault-bootstrap.json.age.tmp /var/lib/vault/vault-bootstrap.json.age
            else
              echo "Couldnt't bootstrap, something went fatally wrong!"
              exit 1
            fi
            set -x''
        }
        fi

        ${exportVaultRoot}
        ${exportConsulMaster}

        set -x
        # vault audit enable socket address=127.0.0.1:9090 socket_type=tcp

        secrets="$(vault secrets list)"

        ${
          lib.optionalString (deployType == "aws") ''
            echo "$secrets" | jq -e '."aws/"'       || vault secrets enable aws''
        }

        echo "$secrets" | jq -e '."consul/"'      || vault secrets enable consul
        echo "$secrets" | jq -e '."kv/"'          || vault secrets enable -version=2 kv
        echo "$secrets" | jq -e '."nomad/"'       || vault secrets enable nomad
        echo "$secrets" | jq -e '."pki/"'         || vault secrets enable pki

        auth="$(vault auth list)"

        ${
          lib.optionalString (deployType == "aws") ''
            echo "$auth" | jq -e '."aws/"'          || vault auth enable aws''
        }

        ${
          lib.optionalString (deployType != "aws") ''
            echo "$auth" | jq -e '."cert/"'         || vault auth enable cert''
        }

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
          ${
          if deployType != "premSim"
          then ''
            issuing_certificates="https://vault.${config.cluster.domain}:8200/v1/pki/ca" \
            crl_distribution_points="https://vault.${config.cluster.domain}:8200/v1/pki/crl"''
          else ''
            issuing_certificates="https://vault.${premSimDomain}:8200/v1/pki/ca" \
            crl_distribution_points="https://vault.${premSimDomain}:8200/v1/pki/crl"''
        }

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
          ${
          if deployType == "aws"
          then ''
            allowed_domains=service.consul,${config.cluster.region}.consul \''
          else ''
            allowed_domains=service.consul,${datacenter}.consul \''
        }
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
