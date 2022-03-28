{ self, lib, pkgs, config, pkiFiles, gossipEncryptionMaterial, etcEncrypted, dockerAuth, ... }:
let
  # Note: Cert definitions in this file are applicable to AWS deployType clusters.
  # For premSim and prem deploType clusters, see the Rakefilefor cert genertaion details.
  # TODO: Unify the AWS vs. prem/premSim approaches.

  deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
  isSops = deployType == "aws";

  sopsEncrypt =
    "${pkgs.sops}/bin/sops --encrypt --input-type json --kms '${config.cluster.kms}' /dev/stdin";

  sopsDecrypt = path:
    # NB: we can't work on store paths that don't yet exist before they are generated
    assert lib.assertMsg (builtins.isString path) "sopsDecrypt: path must be a string ${toString path}";
    "${pkgs.sops}/bin/sops --decrypt --input-type json ${path}";

  isInstance = config.currentCoreNode != null;

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
      "core.vault.service.consul"
      "active.vault.service.consul"
      "nomad.service.consul"
      "server.${config.cluster.region}.consul"
      "vault.${config.cluster.domain}"
      "consul.${config.cluster.domain}"
      "nomad.${config.cluster.domain}"
      "monitoring.${config.cluster.domain}"
      "127.0.0.1"
    ] ++ (lib.mapAttrsToList (_: i: i.privateIP) config.cluster.coreNodes);
  };
  relEncryptedFolder = lib.last (builtins.split "-" (toString config.secrets.encryptedRoot));

in {
  environment.etc.encrypted.source = config.secrets.encryptedRoot; # etcEncrypted

  secrets.generate.consul = lib.mkIf (isInstance && isSops) ''
    export PATH="${lib.makeBinPath (with pkgs; [ consul toybox jq coreutils ])}"

    encrypt="$(consul keygen)"

    if [ ! -s ${relEncryptedFolder}/consul-core.json ]; then
      echo generating ${relEncryptedFolder}/consul-core.json
      echo '{}' \
      | jq --arg encrypt "$encrypt" '.encrypt = $encrypt' \
      | jq --arg token "$(uuidgen)" '.acl.tokens.master = $token' \
      | ${sopsEncrypt} \
      > ${relEncryptedFolder}/consul-core.json
    fi

    if [ ! -s ${relEncryptedFolder}/consul-clients.json ]; then
      echo generating ${relEncryptedFolder}/consul-clients.json
      echo '{}' \
      | jq --arg encrypt "$encrypt" '.encrypt = $encrypt' \
      | ${sopsEncrypt} \
      > ${relEncryptedFolder}/consul-clients.json
    fi
  '';

  secrets.install.docker-login = lib.mkIf (!isInstance && isSops) {
    source = "${etcEncrypted}/docker-passwords.json";
    target = dockerAuth;
    /*
      {
        "auths": {
          "docker.infra.aws.iohkdev.io": {
            "auth": "ffffffffffffffffffffff"
          }
        },
        "HttpHeaders": {
          "User-Agent": "Docker-Client/19.03.12 (linux)"
        }
      }
    */
  };

  secrets.install.nomad-server = lib.mkIf (isInstance && isSops) {
    source = "${etcEncrypted}/nomad.json";
    target = gossipEncryptionMaterial.nomad;
  };

  secrets.install.consul-server = lib.mkIf (isInstance && isSops) {
    source = "${etcEncrypted}/consul-core.json";
    target = gossipEncryptionMaterial.consul;
  };

  secrets.install.consul-clients = lib.mkIf (!isInstance && isSops) {
    source = "${etcEncrypted}/consul-clients.json";
    target = gossipEncryptionMaterial.consul;
    script = ''
      ${pkgs.systemd}/bin/systemctl restart consul.service
    '';
  };

  secrets.generate.nomad = lib.mkIf (isInstance && isSops) ''
    export PATH="${lib.makeBinPath (with pkgs; [ nomad jq ])}"

    if [ ! -s ${relEncryptedFolder}/nomad.json ]; then
      echo generating ${relEncryptedFolder}/nomad.json
      encrypt="$(nomad operator keygen)"

      echo '{}' \
      | jq --arg encrypt "$encrypt" '.server.encrypt = $encrypt' \
      | ${sopsEncrypt} \
      > ${relEncryptedFolder}/nomad.json
    fi
  '';

  secrets.generate.cache = lib.mkIf (isInstance && isSops) ''
    export PATH="${lib.makeBinPath (with pkgs; [ coreutils nix jq ])}"

    mkdir -p secrets encrypted

    if [ ! -s ${relEncryptedFolder}/nix-public-key-file ]; then
      if [ ! -s secrets/nix-secret-key-file ] || [ ! -s secrets/nix-public-key-file ]; then
        echo generating Nix cache keys
        nix-store \
          --generate-binary-cache-key \
          "${config.cluster.name}-0" \
          secrets/nix-secret-key-file \
          secrets/nix-public-key-file
      fi

      cp secrets/nix-public-key-file ${relEncryptedFolder}/nix-public-key-file
    fi

    if [ ! -s ${relEncryptedFolder}/nix-cache.json ]; then
      echo generating ${relEncryptedFolder}/nix-cache.json
      echo '{}' \
      | jq --arg private "$(< secrets/nix-secret-key-file)" '.private = $private' \
      | jq --arg public "$(< secrets/nix-public-key-file)" '.public = $public' \
      | ${sopsEncrypt} \
      > ${relEncryptedFolder}/nix-cache.json
    fi
  '';

  secrets.generate.ca = lib.mkIf (isInstance && isSops) ''
    export PATH="${
      lib.makeBinPath (with pkgs; [ cfssl jq coreutils terraform-with-plugins ])
    }"

    if [ ! -s ${relEncryptedFolder}/ca.json ]; then
      ca="$(cfssl gencert -initca ${caJson})"
      echo "$ca" | cfssljson -bare secrets/ca
      echo "$ca" | ${sopsEncrypt} > ${relEncryptedFolder}/ca.json
    fi

    if [ ! -s ${relEncryptedFolder}/cert.json ]; then
      cert="$(
        cfssl gencert \
          -ca secrets/ca.pem \
          -ca-key secrets/ca-key.pem \
          -config "${caConfigJson}" \
          -profile core \
          ${certConfig} \
        | jq --arg ca "$(< secrets/ca.pem)" '.ca = $ca'
      )"
      echo "$cert" | cfssljson -bare secrets/cert
      cat secrets/cert.pem secrets/ca.pem > secrets/full.pem
      cert="$(echo "$cert" | jq --arg full "$(< secrets/full.pem)" '.full = $full')"
      echo "$cert" | ${sopsEncrypt} > ${relEncryptedFolder}/cert.json
    fi
  '';

  secrets.install.certs = lib.mkIf (isInstance && isSops) {
    script = ''
      export PATH="${lib.makeBinPath (with pkgs; [ cfssl jq coreutils ])}"
      cert="$(${sopsDecrypt "${etcEncrypted}/cert.json"})"
      echo "$cert" | cfssljson -bare cert
      cp ${builtins.baseNameOf pkiFiles.certFile} ${pkiFiles.certFile}
      cp ${builtins.baseNameOf pkiFiles.keyFile} ${pkiFiles.keyFile}

      echo "$cert" | jq -r -e .ca  > "${pkiFiles.caCertFile}"
      echo "$cert" | jq -r -e .full  > "${pkiFiles.certChainFile}"
    '';
  };

  age.secrets.consul-token-master = lib.mkIf (config.services.consul.server && !isSops) {
    file = config.age.encryptedRoot + "/consul/token-master.age";
    path = gossipEncryptionMaterial.consul;
    mode = "0444";
    script = ''
      if [ -s "${gossipEncryptionMaterial.consul}" ]; then
        CONTENTS="$(< "${gossipEncryptionMaterial.consul}")"
      else
        CONTENTS="{}"
      fi
      echo "$CONTENTS" \
        | ${pkgs.jq}/bin/jq \
          --arg token "$(< "$src")" \
          '.acl.tokens.master = $token' \
        > $out
    '';
  };

  age.secrets.consul-encrypt = lib.mkIf (config.services.consul.enable && !isSops) {
    file = config.age.encryptedRoot + /consul/encrypt.age;
    path = gossipEncryptionMaterial.consul;
    mode = "0444";
    script = ''
      if [ -s "${gossipEncryptionMaterial.consul}" ]; then
        CONTENTS="$(< "${gossipEncryptionMaterial.consul}")"
      else
        CONTENTS="{}"
      fi
      echo "$CONTENTS" \
        | ${pkgs.jq}/bin/jq \
          --arg encrypt "$(< "$src")" \
          '.encrypt = $encrypt' \
        > $out
    '';
  };

  age.secrets.nomad-encrypt = lib.mkIf (config.services.nomad.server.enabled && !isSops) {
    file = config.age.encryptedRoot + /nomad/encrypt.age;
    path = gossipEncryptionMaterial.nomad;
    mode = "0444";
    script = ''
      echo '{}' \
        | ${pkgs.jq}/bin/jq \
          --arg encrypt "$(< "$src")" \
          '.server.encrypt = $encrypt' \
        > $out
    '';
  };
}
