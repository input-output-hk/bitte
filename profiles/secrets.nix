{ self, lib, pkgs, config, ... }:
let
  inherit (config.cluster) instances domain region kms;

  sopsEncrypt =
    "${pkgs.sops}/bin/sops --encrypt --input-type json --kms '${kms}' /dev/stdin";

  sopsDecrypt = path:
    "${pkgs.sops}/bin/sops --decrypt --input-type json ${path}";

  isInstance = config.instance != null;

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
    CN = "${domain}";
    inherit names key;
    hosts = [
      "consul.service.consul"
      "vault.service.consul"
      "nomad.service.consul"
      "server.${region}.consul"
      "vault.${domain}"
      "consul.${domain}"
      "nomad.${domain}"
      "monitoring.${domain}"
      "127.0.0.1"
    ] ++ (lib.mapAttrsToList (_: i: i.privateIP) instances);
  };

in {
  secrets.generate.consul = lib.mkIf isInstance ''
    export PATH="${lib.makeBinPath (with pkgs; [ consul toybox jq coreutils ])}"

    encrypt="$(consul keygen)"

    if [ ! -s encrypted/consul-core.json ]; then
      echo '{}' \
      | jq --arg encrypt "$encrypt" '.encrypt = $encrypt' \
      | jq --arg token "$(uuidgen)" '.acl.tokens.master = $token' \
      | ${sopsEncrypt} \
      > encrypted/consul-core.json
    fi

    if [ ! -s encrypted/consul-clients.json ]; then
      echo '{}' \
      | jq --arg encrypt "$encrypt" '.encrypt = $encrypt' \
      | ${sopsEncrypt} \
      > encrypted/consul-clients.json
    fi
  '';

  secrets.install.nomad-server = lib.mkIf isInstance {
    source = config.secrets.encryptedRoot + "/nomad.json";
    target = /etc/nomad.d/secrets.json;
  };

  secrets.install.consul-server = lib.mkIf isInstance {
    source = config.secrets.encryptedRoot + "/consul-core.json";
    target = /etc/consul.d/secrets.json;
  };

  secrets.install.consul-clients = lib.mkIf isInstance {
    source = config.secrets.encryptedRoot + "/consul-clients.json";
    target = /etc/consul.d/secrets.json;
  };

  secrets.generate.nomad = lib.mkIf isInstance ''
    export PATH="${lib.makeBinPath (with pkgs; [ nomad jq ])}"

    if [ ! -s encrypted/nomad.json ]; then
      encrypt="$(nomad operator keygen)"

      echo '{}' \
      | jq --arg encrypt "$encrypt" '.server.encrypt = $encrypt' \
      | ${sopsEncrypt} \
      > encrypted/nomad.json
    fi
  '';

  secrets.generate.cache = lib.mkIf isInstance ''
    export PATH="${lib.makeBinPath (with pkgs; [ coreutils nixFlakes ])}"

    mkdir -p secrets encrypted

    if [ ! -s encrypted/nix-public-key-file ]; then
      if [ ! -s secrets/nix-secret-key-file ] || [ ! -s secrets/nix-public-key-file ]; then
        nix-store \
          --generate-binary-cache-key \
          "${config.cluster.name}-0" \
          secrets/nix-secret-key-file \
          secrets/nix-public-key-file
      fi

      cp secrets/nix-public-key-file encrypted/nix-public-key-file
    fi
  '';

  secrets.generate.ca = lib.mkIf isInstance ''
    export PATH="${
      lib.makeBinPath (with pkgs; [ cfssl jq coreutils terraform-with-plugins ])
    }"

    if [ ! -s secrets/ca.pem ]; then
      ca="$(cfssl gencert -initca ${caJson})"
      echo "$ca" | cfssljson -bare secrets/ca
      echo "$ca" | ${sopsEncrypt} > encrypted/ca.json
    fi

    certConfigJson="${certConfig}"
    jq --arg ip "$IP" '.hosts += [$ip]' < "$certConfigJson" \
    > cert.config

    if [ ! -s encrypted/cert.json ]; then
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
      cat secrets/ca.pem <(echo) secrets/cert.pem > secrets/full.pem
      cert="$(echo "$cert" | jq --arg full "$(< secrets/full.pem)" '.full = $full')"
      echo "$cert" | ${sopsEncrypt} > encrypted/cert.json
    fi

    rm -f cert.config
  '';

  secrets.install.certs = lib.mkIf isInstance {
    script = ''
      export PATH="${lib.makeBinPath (with pkgs; [ cfssl jq coreutils ])}"
      cert="$(${sopsDecrypt (config.secrets.encryptedRoot + "/cert.json")})"
      echo "$cert" | cfssljson -bare cert
      echo "$cert" | jq -r -e .ca  > "ca.pem"
      echo "$cert" | jq -r -e .full  > "full.pem"

      for pem in *.pem; do
      [ -s "$pem" ]
      cp "$pem" "/etc/ssl/certs/$pem"
      done
    '';
  };
}
