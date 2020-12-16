{ self, cluster, lib, awscli, sops, jq, coreutils, cfssl, consul, utillinux
, vault-bin, toPrettyJSON, writeShellScriptBin, bitte, terraform-with-plugins
, rsync, openssh, gnused, curl, cacert, nixFlakes, nomad }:
let
  inherit (cluster) kms region s3Bucket domain instances autoscalingGroups;
  inherit (lib)
    mkOverride mkIf attrNames concatStringsSep optional flip mapAttrsToList
    forEach makeBinPath;
  s3dir = "s3://${s3Bucket}/infra/secrets/${cluster.name}/${kms}";

  # TODO: check: https://technedigitale.com/archives/639

  names = [{
    O = "IOHK";
    C = "JP";
    ST = "Kantō";
    L = "Tokyo";
  }];

  key = {
    algo = "ecdsa";
    size = 256;
  };

  caJson = toPrettyJSON "ca" {
    hosts = [ "consul" ];
    inherit names key;
  };

  caConfigJson = toPrettyJSON "ca" {
    signing = {
      default = { expiry = "12h"; };

      profiles = {
        bootstrap = {
          usages = [
            "signing"
            "key encipherment"
            "server auth"
            "client auth"
            "cert sign"
            "crl sign"
          ];
          expiry = "12h";
        };

        intermediate = {
          usages = [ "signing" "key encipherment" "cert sign" "crl sign" ];
          expiry = "43800h";
          ca_constraint = { is_ca = true; };
        };
      };
    };
  };

  certConfig = toPrettyJSON "core" {
    CN = "${domain}";
    inherit names key;
    hosts = [
      "consul.service.consul"
      "vault.service.consul"
      "nomad.service.consul"
      "server.${region}.consul"
      "127.0.0.1"
    ] ++ (mapAttrsToList (_: i: i.privateIP) instances);
  };

  generate = writeShellScriptBin "bitte-secrets-generate" ''
    set -exuo pipefail
    export PATH="${
      makeBinPath [
        awscli
        sops
        jq
        coreutils
        cfssl
        consul
        utillinux
        terraform-with-plugins
        nomad
      ]
    }"

    root="$PWD/secrets/certs/${cluster.name}/${kms}"
    ship="$root/ship"

    terraform workspace select core
    terraform init

    IP="$(terraform output -json cluster | jq -e -r '.instances."core-1"."public-ip"')"

    mkdir -p "$root/original" "$root/ship"
    cd "$root/original"

    # CA

    enc="$ship/ca/ca.enc.json"
    mkdir -p "$(dirname "$enc")"

    if [ ! -s "$enc" ]; then
      cert="$(cfssl gencert -initca ${caJson})"

      echo "$cert" \
      | cfssljson -bare ca

      echo "$cert" \
      | sops --encrypt --kms "${kms}" --input-type json --output-type json /dev/stdin \
      > "$enc.new"

      [ -s "$enc.new" ] && mv "$enc.new" "$enc"
    fi

    # Server certs, only valid for twelve hours, meant for bootstrapping.
    # We always regenerate this one.
    # If you take more than twelve hours to get the Vault CA going, you'll
    # probably have to scrap the cluster because it won't be able to recover.

    enc="$ship/server/cert.enc.json"
    mkdir -p "$(dirname "$enc")"

    certConfigJson="${certConfig}"
    jq --arg ip "$IP" '.hosts += [$ip]' < "$certConfigJson" \
    > cert.config

    cert="$(
      cfssl gencert \
        -ca ca.pem \
        -ca-key ca-key.pem \
        -config "${caConfigJson}" \
        -profile bootstrap \
        cert.config
    )"

    echo "$cert" \
    | cfssljson -bare cert

    mkdir -p "$ship/client"
    cp ca.pem "$ship/client/ca.pem"

    echo "$cert" \
    | jq --arg ca "$(< ca.pem)" '.ca = $ca' \
    | sops --encrypt --kms "${kms}" --input-type json --output-type json /dev/stdin \
    > "$enc.new"

    [ -s "$enc.new" ] && mv "$enc.new" "$enc"


    # Consul

    consulEncrypt="$(consul keygen)"

    ## Consul server ACL master token and encrypt secret

    enc="$ship/server/consul-server.enc.json"
    mkdir -p "$(dirname "$enc")"

    if [ ! -s "$enc" ]; then
      token="$(uuidgen)"

      echo '{}' \
      | jq --arg token "$(uuidgen)" '.acl.tokens.master = $token' \
      | jq --arg encrypt "$consulEncrypt" '.encrypt = $encrypt' \
      | sops --encrypt --kms "${kms}" --input-type json --output-type json /dev/stdin \
      > "$enc.new"

      [ -s "$enc.new" ] && mv "$enc.new" "$enc"
    fi

    ## Consul client encrypt secret

    enc="$ship/client/consul-client.enc.json"
    mkdir -p "$(dirname "$enc")"

    if [ ! -s "$enc" ]; then
      echo '{}' \
      | jq --arg encrypt "$consulEncrypt" '.encrypt = $encrypt' \
      | sops --encrypt --kms "${kms}" --input-type json --output-type json /dev/stdin \
      > "$enc.new"

      [ -s "$enc.new" ] && mv "$enc.new" "$enc"
    fi


    ## Nomad

    nomadEncrypt="$(nomad operator keygen)"

    ## Nomad Client

    enc="$ship/client/nomad-client.enc.json"
    mkdir -p "$(dirname "$enc")"

    if [ ! -s "$enc" ]; then
      echo '{}' \
      | jq --arg encrypt "$nomadEncrypt" '.encrypt = $encrypt' \
      | sops --encrypt --kms "${kms}" --input-type json --output-type json /dev/stdin \
      > "$enc.new"
      [ -s "$enc.new" ] && mv "$enc.new" "$enc"
    fi

    ## Nomad Server

    enc="$ship/server/nomad-server.enc.json"
    mkdir -p "$(dirname "$enc")"

    if [ ! -s "$enc" ]; then
      echo '{}' \
      | jq --arg encrypt "$nomadEncrypt" '.encrypt = $encrypt' \
      | sops --encrypt --kms "${kms}" --input-type json --output-type json /dev/stdin \
      > "$enc.new"
      [ -s "$enc.new" ] && mv "$enc.new" "$enc"
    fi
  '';

  upload = writeShellScriptBin "bitte-secrets-upload" ''
    set -exuo pipefail

    export PATH="${makeBinPath [ awscli ]}"

    aws s3 sync --delete "secrets/certs/${cluster.name}/${kms}/ship/" "${s3dir}/"
  '';

  # Used during the initial deploy
  install = writeShellScriptBin "bitte-secrets-install" ''
    set -exuo pipefail

    export PATH="${
      makeBinPath [ awscli sops jq coreutils cfssl vault-bin curl cacert ]
    }"

    dir=/run/keys/bitte-secrets-download
    mkdir -p "$dir"
    cd "$dir"

    aws s3 sync --delete "${s3dir}/$1" .

    case "$1" in
      server)
        mkdir -p /etc/consul.d
        sops --decrypt consul-server.enc.json \
        > /etc/consul.d/secrets.json

        mkdir -p /etc/nomad.d
        sops --decrypt nomad-server.enc.json \
        > /etc/nomad.d/secrets.json

        cdir="/etc/ssl/certs"

        sops --decrypt cert.enc.json \
        | cfssljson -bare cert

        cp cert.pem     "$cdir/cert.pem"
        cp cert-key.pem "$cdir/cert-key.pem"

        sops --decrypt --extract '["ca"]' cert.enc.json \
        > "$cdir/ca.pem.new"

        [ -s "$cdir/ca.pem.new" ]

        mv "$cdir/ca.pem.new" "$cdir/ca.pem"

        cat "$cdir/ca.pem" <(echo) "$cdir/cert.pem" \
        > /etc/ssl/certs/full.pem
      ;;
      client)
        mkdir -p /etc/consul.d
        sops --decrypt consul-client.enc.json \
        > /etc/consul.d/secrets.json

        mkdir -p /etc/nomad.d
        sops --decrypt nomad-client.enc.json \
        > /etc/nomad.d/secrets.json

        unset VAULT_CACERT
        export VAULT_ADDR=https://vault.${domain}
        export VAULT_FORMAT=json
        vault login -method aws header_value=${domain}

        ip="$(curl -f -s http://169.254.169.254/latest/meta-data/local-ipv4)"

        cert="$(
          vault write pki/issue/client \
            common_name=server.${region}.consul \
            ip_sans="127.0.0.1,$ip" \
            alt_names=vault.service.consul,consul.service.consul,nomad.service.consul
        )"

        mkdir -p certs

        echo "$cert" | jq -e -r .data.private_key  > /etc/ssl/certs/cert-key.pem
        echo "$cert" | jq -e -r .data.certificate  > /etc/ssl/certs/cert.pem
        echo "$cert" | jq -e -r .data.certificate  > /etc/ssl/certs/full.pem
        echo "$cert" | jq -e -r .data.issuing_ca  >> /etc/ssl/certs/full.pem
        cat ca.pem                                >> /etc/ssl/certs/full.pem
        cp ca.pem                                    /etc/ssl/certs/ca.pem
      ;;
      *)
        echo "pass 'client' or 'server' as arguments"
    esac
  '';

  orchestrate = writeShellScriptBin "bitte-secrets-orchestrate" ''
    export PATH="${
      makeBinPath [
        bitte
        coreutils
        generate
        rsync
        openssh
        switch
        terraform-with-plugins
        upload
        vault-bin
        jq
      ]
    }"

    set -exuo pipefail

    nix build .#clusters.atala-testnet.tf.network.output && rm -f config.tf.json; cp $(readlink -f ./result) config.tf.json
    terraform workspace select ${cluster.name}_core

    bitte-secrets-generate
    bitte-secrets-upload

    bitte rebuild --dirty
    bitte-secrets-switch
  '';

  switch = writeShellScriptBin "bitte-secrets-switch" ''
    set -exuo pipefail

    export PATH="${
      makeBinPath [
        awscli
        bitte
        coreutils
        gnused
        jq
        rsync
        terraform-with-plugins
        vault-bin
        openssh
        cfssl
      ]
    }"

    set +x

    echo "Waiting for Vault bootstrap..."

    until bitte ssh core-1 test -e /var/lib/vault/.bootstrap-done; do
      sleep 1
    done

    set -x

    # We can't use IAM auth for now...
    # until vault login -method aws header_value=${domain} role=admin-iam; do
    #   sleep 1
    # done

    dir="$(mktemp -d certs.XXXXXXXXXX)"

    function finish {
      rm -rf "$dir"
    }
    trap finish EXIT

    ips=($(terraform output -json cluster | jq -e -r '.instances | map(."public-ip") | .[]'))
    IP="$(terraform output -json cluster | jq -e -r '.instances."core-1"."public-ip"')"

    export VAULT_ADDR="https://$IP:8200"
    export VAULT_FORMAT=json
    export VAULT_CACERT=ca.pem
    export LOG_LEVEL=debug

    # TODO: simplify this...
    VAULT_TOKEN=""
    until test -n "$VAULT_TOKEN"; do
      VAULT_TOKEN="$(
        bitte ssh core-1 sops -d --extract '["root_token"]' /var/lib/vault/vault.enc.json || true
      )"
      test -n "$VAULT_TOKEN" || sleep 1
    done
    export VAULT_TOKEN

    certDir="$PWD/secrets/certs/${cluster.name}/${kms}/original"
    pushd "$dir"
    cp "$certDir/ca.pem" .
    cp "$certDir/ca-key.pem" .

    # This may randomly fail...
    set +e

    until test -s issuing-ca.csr; do
      vault write \
        pki/intermediate/generate/internal \
        common_name="vault.${domain}" \
      | jq -r -e .data.csr \
      > issuing-ca.csr
      test -s issuing-ca.csr || sleep 1
    done

    set -e

    cfssl sign \
      -ca "ca.pem" \
      -ca-key "ca-key.pem" \
      -hostname "vault.service.consul" \
      -config "${caConfigJson}" \
      -profile intermediate \
      issuing-ca.csr \
    | jq -r -e '.cert' \
    | sed '/^$/d' \
    > issuing.pem

    cat ca.pem >> issuing.pem

    vault write pki/intermediate/set-signed certificate=@issuing.pem

    cert="$(
      vault write pki/issue/server \
        common_name=server.${region}.consul \
        ip_sans="127.0.0.1,${
          concatStringsSep "," (mapAttrsToList (_: i: i.privateIP) instances)
        }" \
        alt_names="vault.service.consul,consul.service.consul,nomad.service.consul"
    )"

    mkdir -p certs

    echo "$cert" | jq -e -r .data.private_key  > certs/cert-key.pem
    echo "$cert" | jq -e -r .data.certificate  > certs/cert.pem
    echo "$cert" | jq -e -r .data.certificate  > certs/full.pem
    echo "$cert" | jq -e -r .data.issuing_ca  >> certs/full.pem
    cat ca.pem                                >> certs/full.pem

    # TODO: add something like that to bitte-cli
    for ip in "''${ips[@]}"; do
      rsync -rP certs/ "root@$ip:/etc/ssl/certs/"
    done

    popd

    bitte pssh 'systemctl restart consul'
    bitte pssh 'systemctl restart vault'
    bitte pssh 'systemctl restart nomad'
  '';

  repair = writeShellScriptBin "bitte-secrets-repair" ''
    set -exuo pipefail

    export PATH="${makeBinPath [ coreutils awscli sops jq cfssl ]}"

    dir=/run/keys/bitte-secrets-download
    mkdir -p "$dir"
    cd "$dir"

    aws s3 sync --delete "${s3dir}/$1" .

    mkdir -p /etc/consul.d
    sops --decrypt consul-server.enc.json \
    > /etc/consul.d/secrets.json

    cdir="/etc/ssl/certs"

    sops --decrypt cert.enc.json \
    | cfssljson -bare cert

    cp cert.pem     "$cdir/cert.pem"
    cp cert-key.pem "$cdir/cert-key.pem"

    sops --decrypt --extract '["ca"]' cert.enc.json \
    > "$cdir/ca.pem.new"

    [ -s "$cdir/ca.pem.new" ] && mv "$cdir/ca.pem.new" "$cdir/ca.pem"

    cat "$cdir/ca.pem" <(echo) "$cdir/cert.pem" \
    > /etc/ssl/certs/full.pem

    for s in consul vault nomad vault-agent ingress; do
      /run/current-system/sw/bin/systemctl restart "$s.service"
    done
  '';
in {
  bitte-secrets-orchestrate = orchestrate;
  bitte-secrets-generate = generate;
  bitte-secrets-upload = upload;
  bitte-secrets-switch = switch;
  bitte-secrets-install = install;
  bitte-secrets-repair = repair;
}
