{ lib, config, pkgs, ... }:
let
  inherit (lib) mkOption;
  inherit (lib.types) str enum submodule attrsOf;
  inherit (config.cluster) kms;

  secretType = submodule ({ name, ... }: {
    options = {
      name = lib.mkOption { type = str; };
      generate = lib.mkOption { type = str; };
      install = lib.mkOption { type = str; };
    };
  });
in {
  options = {
    secrets = lib.mkOption {
      default = { };
      type = attrsOf secretType;
    };
  };

  config = {
    systemd.services = lib.flip lib.mapAttrs' config.secrets (name: args:
      lib.nameValuePair "secrets-${name}" {
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = "15s";
          WorkingDirectory = "/run/keys";
        };

        path = with pkgs; [ sops jq cfssl coreutils ];
      }
    );

    secrets."consul" = {
      generate = ''
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
      '';

      script = ''
        sops -d ${./encrypted/consul-server.json} > /etc/consul.d/secrets.json
      '';
    };

    secrets."nomad" = {
      script = ''
        sops -d ${./encrypted/nomad.json} > /etc/nomad.d/secrets.json
      '';
    };

    # Only install new certs if they're actually newer.
    secrets."certs" = {
      script = ''
        sops -d ${./encrypted/certs.json} | cfssljson -bare cert
        sops -d --extract '["ca"]' cert.enc.json > "ca.pem"

        cat "ca.pem" <(echo) "cert.pem" > full.pem

        old="$(cfssl certinfo -cert /etc/ssl/certs/cert.pem | jq -e -r .not_after)"
        new="$(cfssl certinfo -cert cert.pem | jq -e -r .not_after)"

        if [[ "$old" > "$new" ]]; then
          for pem in *.pem; do
            [ -s "$pem" ]
            cp "$pem" "/etc/ssl/certs/$pem"
          done
        fi
      '';
    };
  };
}
