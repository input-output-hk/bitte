{ lib, pkgs, config, ... }:
let
  inherit (lib) mkOption;
  inherit (config.cluster) kms;

  sopsEncrypt =
    "${pkgs.sops}/bin/sops --encrypt --input-type json --kms '${kms}' /dev/stdin";

  sopsDecrypt = path: "${pkgs.sops}/bin/sops --decrypt --input-type json ${path}";

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

  caJson = pkgs.toPrettyJSON "ca" {
    hosts = [ "consul" ];
    inherit names key;
  };

  caConfigJson = pkgs.toPrettyJSON "ca" {
    signing = {
      default = { expiry = "43800h"; };

      profiles = {
        core = {
          usages = [
            "signing"
            "key encipherment"
            "server auth"
            "client auth"
            "cert sign"
            "crl sign"
          ];
          expiry = "43800h";
        };

        intermediate = {
          usages = [ "signing" "key encipherment" "cert sign" "crl sign" ];
          expiry = "43800h";
          ca_constraint = { is_ca = true; };
        };
      };
    };
  };

  certConfig = pkgs.toPrettyJSON "core" {
    CN = "${config.cluster.domain}";
    inherit names key;
    hosts = [
      "consul.service.consul"
      "vault.service.consul"
      "nomad.service.consul"
      "server.${config.cluster.region}.consul"
      "127.0.0.1"
    ] ++ (lib.mapAttrsToList (_: i: i.privateIP) config.cluster.instances);
  };

in {
    secrets.generate.consul = ''
    export PATH="${
      lib.makeBinPath (with pkgs; [ consul toybox jq coreutils ])
    }"

    encrypt="$(consul keygen)"

    echo '{}' \
    | jq --arg encrypt "$encrypt" '.encrypt = $encrypt' \
    | jq --arg token "$(uuidgen)" '.acl.tokens.master = $token' \
    | ${sopsEncrypt} \
    > encrypted/consul-core.json

    echo '{}' \
    | jq --arg encrypt "$encrypt" '.encrypt = $encrypt' \
    | ${sopsEncrypt} \
    > encrypted/consul-clients.json
  '';

  secrets.install.consul-server = {
    source = self + /encrypted/consul-core.json;
    target = /etc/consul.d/secrets.json;
  };

  secrets.install.consul-clients = {
    source = self + /encrypted/consul-clients.json;
    target = /etc/consul.d/secrets.json;
  };

  secrets.generate.nomad = ''
    export PATH="${lib.makeBinPath (with pkgs; [ nomad jq ])}"

    encrypt="$(nomad operator keygen)"

    echo '{}' \
    | jq --arg encrypt "$encrypt" '.encrypt = $encrypt' \
    | ${sopsEncrypt} \
    > encrypted/nomad.json
  '';

  secrets.install.nomad-server = {
    source = self + /encrypted/nomad-server.json;
    target = /etc/nomad.d/secrets.json;
  };

  secrets.generate.ca = ''
    export PATH="${
      lib.makeBinPath
      (with pkgs; [ cfssl jq coreutils terraform-with-plugins ])
    }"

    ca="$(cfssl gencert -initca ${caJson})"
    echo "$ca" | cfssljson -bare secrets/ca
    echo "$ca" | ${sopsEncrypt} > encrypted/ca.json

    IP="$(terraform output -json cluster | jq -e -r '.instances."core-1".public_ip')"

    certConfigJson="${certConfig}"
    jq --arg ip "$IP" '.hosts += [$ip]' < "$certConfigJson" \
    > cert.config


    cert="$(
      cfssl gencert \
        -ca secrets/ca.pem \
        -ca-key secrets/ca-key.pem \
        -config "${caConfigJson}" \
        -profile core \
        cert.config \
      | jq --arg ca "$(< secrets/ca.pem)" '.ca = $ca'
    )"
    echo "$cert" | cfssljson -bare secrets/cert
    cat secrets/ca.pem <(echo) secrets/cert.pem > full.pem
    cert="$(echo "$cert" | jq --arg full "$(full.pem)" '.full = $full')"
    echo "$cert" | ${sopsEncrypt} > encrypted/cert.json
  '';

  # Only install new certs if they're actually newer.
  secrets.install.certs.script = ''
    export PATH="${
      lib.makeBinPath
      (with pkgs; [ cfssl jq coreutils ])
    }"
    cert="$(${sopsDecrypt (self + /encrypted/cert.json)})"
    echo "$cert" | cfssljson -bare cert
    echo "$cert" | jq -r -e .ca  > "ca.pem"
    echo "$cert" | jq -r -e .full  > "full.pem"

    old="$(cfssl certinfo -cert /etc/ssl/certs/cert.pem | jq -e -r .not_after)"
    new="$(cfssl certinfo -cert cert.pem | jq -e -r .not_after)"

    if [[ "$old" > "$new" ]]; then
      for pem in *.pem; do
        [ -s "$pem" ]
        cp "$pem" "/etc/ssl/certs/$pem"
      done
    fi
  '';
}
