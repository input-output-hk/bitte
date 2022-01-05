let

  spireServerConfig = builtins.toJSON {
    server = {
      trust_domain = "iog.io";

      bind_address = "0.0.0.0";
      bind_port = "8081";
      log_level = "INFO";
      data_dir = "";
      default_svid_ttl = "8760h"; # 1 year
      ca_ttl = "43800h"; # 5 years
      ca_subject = {
        country = [ "JP" ];
        organization = [ "IOHK" ];
        common_name = "Bitte Root CA";
      };
    };
    plugins = {
      DataStore.sql = {
          plugin_data = {
              database_type = "sqlite3";
              connection_string = "./credentials/spire/datastore.sqlite3";
          }
      };
      KeyManager.disk = {
          plugin_data = {
              keys_path = "./credentials/spire/keys.json";
          }
      };
    };
  };

in {
  "credentials/oauth/google-api-keys".generate = ''
    # TODO: find a way to fetch them
    # OAUTH2_PROXY_CLIENT_ID=fffff...ffff.apps.googleusercontent.com
    # OAUTH2_PROXY_CLIENT_SECRET=
    # OAUTH2_PROXY_COOKIE_SECRET=
  '';

  "credentials/grafana/password".generate = ''
    xkcdpass
  '';

  "credentials/docker/password".generate = ''
    password="$(pwgen -cB 32)"
    hashed="$(echo "$password" | htpasswd -i -B -n developer)"
    echo '{}' \
      | jq --arg password "$password" '.password = $password' \
      | jq --arg hashed "$hashed" '.hashed = $hashed'
  '';

  "credentials/docker/password.hashed".generate = ''
    age -d /credentials/docker-password | htpasswd -i -B -n developer
  '';

  "credentials/consul/master-token.json".generate = ''
    token="$(uuidgen)"
    echo '{}' | jq --arg token "$token" '.acl.tokens.master = $token'
  '';
  "credentials/consul/encrypt.json".generate = ''
    encrypt="$(consul keygen)"
    echo '{}' | jq --arg encrypt "$encrypt" '.encrypt = $encrypt'
  '';

  "credentials/nomad/encrypt.json".generate = ''
    encrypt="$(nomad operator keygen)"
    echo '{}' | jq --arg encrypt "$encrypt" '.server.encrypt = $encrypt'
  '';

  "credentials/nix/skey".generate = ''
    ssk="$(nix key generate-secret --key-name)"
    nix key convert-secret-to-public < "$ssk" > "credentials/nix/skey.pub"
  '';
}
