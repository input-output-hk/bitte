{ lib, pkgs, inputs, ... }:
let
  configs = inputs.self.nixosConfigurations;

  ssh = host: ''
    ssh ${host} \
      -i ./age-bootstrap \
      -o UserKnownHostsFile=/dev/null \
      -o StrictHostKeyChecking=no \
  '';

  deage = path: "age -d -i ${./age-bootstrap} ${path}";

  copyKeys = lib.forEach [ "core0" "core1" "core2" "client0" ] (machine: ''
    key="$(${deage ../. + "/encrypted/ssh/${machine}.age"})"

    echo "$key" | ${ssh machine} tee /etc/ssh/ssh_host_ed25519_key
    ${ssh machine} chmod 0600 /etc/ssh/ssh_host_ed25519_key
    echo "$(< ${../. + "/encrypted/ssh/${machine}.pub"})" \
      | ${ssh machine} tee /etc/ssh/ssh_host_ed25519_key.pub

    # The activate script can now decrypt all secrets
    ${ssh machine} /run/current-system/activate
  '');

  adminScriptPreRestart = pkgs.writeBashChecked "admin-pre.sh" ''
    set -exuo pipefail

    cp -r ${inputs.self} bitte
    pushd bitte

    cp tests/age-bootstrap age-bootstrap
    chmod 0600 age-bootstrap

    ${lib.concatStringsSep "\n" copyKeys}
  '';

  # TODO: it's very hard to get a flake built without internet connection.
  #
  # This was an idea of running nixos-rebuild after fetching the automatically
  # generated SSH keys from each host and re-encrypting the files in
  # ./encrypted/
  # That way we wouldn't need to keep the private host keys in the repo and
  # simplify adding new machines.
  #
  # agenixJSON="$(remarshal -if toml -of json < .agenix.toml)"
  #
  # while read -r line; do
  #   echo line: "$line"
  #   agenixJSON="$(
  #     echo "$agenixJSON" | jq \
  #       --arg host "$(echo "$line" | awk '{print $1}')" \
  #       --arg key "$(echo "$line" | awk '{print $2 " " $3}')" \
  #       '.identities[$host] = $key'
  #   )"
  # done < <(ssh-keyscan -t ed25519 core0 core1 core2)
  #
  # echo "$agenixJSON" | remarshal -if json -of toml > .agenix.toml
  #
  # fd . -e age encrypted -x agenix -i ${./age-bootstrap} --rekey
  #
  # for host in core0 core1 core2; do
  #   nixos-rebuild switch --flake ".#test-$host" --target-host "$host"
  # done

  bootstrapVaultPolicy = pkgs.writeText "bootstrap.hcl" ''
    path "*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }
  '';

  adminScriptPostRestart = pkgs.writeBashChecked "admin-post.sh" ''
    set -exuo pipefail

    pushd bitte

    ${ssh "core0"} vault operator init | tee /tmp/vault-bootstrap

    readarray -t keys < <(jq < /tmp/vault-bootstrap -e -r '.unseal_keys_b64[0,1,2]')
    VAULT_TOKEN="$(jq < /tmp/vault-bootstrap -e -r '.root_token')"
    export VAULT_TOKEN

    set +xe
    for core in core0 core1 core2; do
      echo "Unsealing $core"
      for key in "''${keys[@]}"; do
        result=9
        until [ "$result" -eq 0 ]; do
          echo "Unsealing $core with $key"
          ssh "$core" \
            -i ./age-bootstrap \
            -o UserKnownHostsFile=/dev/null \
            -o StrictHostKeyChecking=no \
            -- vault operator unseal "$key"
          result="$?"

          echo "Unsealed $core with $key result: $result"
          sleep 1
        done
      done
    done

    set -xe

    ${deage ../encrypted/ssl/ca.age} > /tmp/ca.pem
    ${deage ../encrypted/ssl/client.age} > /tmp/client.pem
    ${deage ../encrypted/ssl/client-key.age} > /tmp/client-key.pem
    ${deage ../encrypted/ssl/server.age} > /tmp/server.pem
    cat /tmp/ca.pem <(echo) /tmp/server.pem > /tmp/full.pem

    export VAULT_FORMAT=json
    export VAULT_ADDR=https://core0:8200
    export VAULT_CACERT=/tmp/ca.pem

    for core in core1 core2; do
      vault operator raft join -address "https://$core:8200"
      vault operator raft list-peers -address "https://$core:8200"
    done

    vault auth enable userpass

    vault write auth/userpass/users/manveru \
      password=letmein \
      policies=admin

    vault auth enable cert

    # This policy only exists until the vault-acl service finishes running
    vault policy write bootstrap ${bootstrapVaultPolicy}

    vault write auth/cert/certs/bootstrap \
      display_name=bootstrap \
      policies=bootstrap \
      certificate="$(${deage ../encrypted/ssl/client.age})" \
      ttl=3600

    vault write auth/cert/certs/vault-agent-core \
      display_name=vault-agent-core \
      policies=vault-agent-core \
      certificate="$(${deage ../encrypted/ssl/client.age})" \
      ttl=3600

    vault write auth/cert/certs/vault-agent-client \
      display_name=vault-agent-client \
      policies=vault-agent-client \
      certificate="$(${deage ../encrypted/ssl/client.age})" \
      ttl=3600

    ###
    ### Consul
    ###

    export CONSUL_HTTP_ADDR=https://core0:8501
    export CONSUL_CAPATH=/tmp/ca.pem
    export CONSUL_CLIENT_CERT=/tmp/client.pem
    export CONSUL_CLIENT_KEY=/tmp/client-key.pem
    CONSUL_HTTP_TOKEN="$(${deage ../encrypted/consul/token-master.age})"
    export CONSUL_HTTP_TOKEN

    vault secrets enable consul

    vault_consul_token_response="$(
      consul acl token create \
        -policy-name=global-management \
        -description "Vault $(date +%Y-%m-%d-%H-%M-%S)" \
        -format json
    )"

    vault_consul_token="$(echo "$vault_consul_token_response" | jq -e -r .SecretID)"

    vault write consul/config/access \
      ca_cert="$(${deage ../encrypted/ssl/ca.age})" \
      client_cert="$(${deage ../encrypted/ssl/client.age})" \
      client_key="$(${deage ../encrypted/ssl/client-key.age})" \
      token="$vault_consul_token"

    vault secrets enable pki
    vault secrets enable -version=2 kv

    ###
    ### Nomad
    ###

    vault secrets enable nomad

    for core in core{0,1,2}; do
      echo waiting for "$core" ...
      set +x
      until nc -z -v "$core" 4646; do sleep 1; done
      set -x
    done

    curl https://core0:4646/v1/acl/bootstrap --cacert /tmp/full.pem -f -s -X POST > /tmp/nomad-bootstrap.json
    NOMAD_TOKEN="$(jq < /tmp/nomad-bootstrap.json -r -e .SecretID)"
    export NOMAD_TOKEN

    # TODO: replace with renewable tokens in vault-agent
    echo "$NOMAD_TOKEN" | ${ssh "core0"} tee /var/lib/nomad/bootstrap.token
    echo "$NOMAD_TOKEN" | ${ssh "core0"} tee /var/lib/vault/nomad_token

    export NOMAD_ADDR=https://core0:4646
    export NOMAD_CAPATH=/tmp/ca.pem
    export NOMAD_CLIENT_CERT=/tmp/client.pem
    export NOMAD_CLIENT_KEY=/tmp/client-key.pem

    nomad_vault_token="$(
      nomad acl token create -type management \
      | awk '/Secret ID/ { print $4 }'
    )"

    vault write nomad/config/access \
      address="https://127.0.0.1:4646" \
      token="$nomad_vault_token" \
      ca_cert="$(< /tmp/ca.pem)" \
      client_cert="$(< /tmp/client.pem)" \
      client_key="$(< /tmp/client-key.pem)"
  '';

  consulCheck = pkgs.writeBashChecked "consul.sh" ''
    set -exuo pipefail

    export PATH="${lib.makeBinPath (with pkgs; [ jq consul bat ])}"

    CONSUL_HTTP_TOKEN="$(jq -r -e < /etc/consul.d/token-master.json .acl.tokens.master)"
    export CONSUL_HTTP_TOKEN

    consul members
  '';

  nomadJob = builtins.toFile "hello.hcl" ''
    job "test" {
      datacenters = ["dc0"]
      group "test" {
        task "hello" {
          driver = "exec"

          config {
            command = "hello"
            args = ["Hello World!"]
          }
        }
      }
    }
  '';

  developerScript = pkgs.writeBashChecked "dev.sh" ''
    set -exuo pipefail

    ${deage ../encrypted/ssl/ca.age} > /tmp/ca.pem
    ${deage ../encrypted/ssl/client.age} > /tmp/client.pem
    ${deage ../encrypted/ssl/client-key.age} > /tmp/client-key.pem

    vault login -method userpass username=manveru password=letmein

    CONSUL_HTTP_TOKEN="$(vault read -field token consul/creds/admin)"
    export CONSUL_HTTP_TOKEN
    NOMAD_TOKEN="$(vault read -field secret_id nomad/creds/admin)"
    export NOMAD_TOKEN

    consul members
    nomad agent-info

    nomad job run ${nomadJob}

    sleep 60
  '';

  cluster = (import ./cluster.nix { }).cluster;

  extra = name: ip: {
    users.users.root.openssh.authorizedKeys.keys =
      [ (builtins.readFile ./age-bootstrap.pub) ];

    networking.firewall.enable = false;
    networking.useDHCP = false;
    networking.firewall.logRefusedPackets = true;
    networking.interfaces.eth1.ipv4.addresses = [{
      address = ip;
      prefixLength = 16;
    }];

    _module.args.nodeName = name;
    _module.args.self = { inherit inputs; };
  };

  mkCore = name: {
    imports = [ (extra name cluster.instances.${name}.privateIP) ./cluster.nix ]
      ++ cluster.instances.${name}.modules;
  };

  mkWork = name: {
    imports = [ (extra name cluster.instances.${name}.privateIP) ./cluster.nix ]
      ++ cluster.instances.${name}.modules;
  };

  sessionVariables = {
    VAULT_ADDR = "https://core0:8200";
    VAULT_CACERT = "/tmp/ca.pem";

    CONSUL_HTTP_ADDR = "https://core0:8501";
    CONSUL_CAPATH = "/tmp/ca.pem";
    CONSUL_CLIENT_CERT = "/tmp/client.pem";
    CONSUL_CLIENT_KEY = "/tmp/client-key.pem";

    NOMAD_ADDR = "https://core0:4646";
    NOMAD_CAPATH = "/tmp/ca.pem";
    NOMAD_CLIENT_CERT = "/tmp/client.pem";
    NOMAD_CLIENT_KEY = "/tmp/client-key.pem";
  };
in pkgs.nixosTest {
  name = "bitte";

  nodes = {
    developer = {
      environment.systemPackages = with pkgs; [
        age
        agenix-cli
        consul
        coreutils
        curl
        gawk
        iproute
        jq
        netcat
        nomad
        openssh
        vault-bin
      ];
      environment.sessionVariables = sessionVariables;
    };

    admin = { pkgs, ... }: {
      _module.args.self = { inherit inputs; };
      imports = [ ../../profiles/nix.nix ];
      environment.systemPackages = with pkgs; [
        age
        agenix-cli
        consul
        fd
        jq
        nomad
        remarshal
        vault-bin
        nixFlakes
        which
      ];
      environment.sessionVariables = sessionVariables;
    };

    core0 = mkCore "core0";
    core1 = mkCore "core1";
    core2 = mkCore "core2";

    client0 = mkWork "client0";
  };

  testScript = ''
    cores = [core0, core1, core2]
    start_all()

    [core.wait_for_unit("sshd") for core in cores]
    client0.wait_for_unit("sshd")

    admin.systemctl("is-system-running --wait")
    admin.log(admin.succeed("${adminScriptPreRestart}"))

    [core.wait_for_unit("vault") for core in cores]
    [core.wait_for_open_port("8200") for core in cores]

    admin.log(admin.succeed("${adminScriptPostRestart}"))

    [core.log(core.succeed("vault status")) for core in cores]

    [core.wait_for_unit("consul") for core in cores]
    [core.wait_for_open_port(8500) for core in cores]
    [core.wait_for_open_port("8501") for core in cores]

    [
        core.log(core.succeed("${consulCheck}"))
        for core in cores
    ]

    [core.wait_for_unit("vault-agent") for core in cores]
    core0.wait_for_unit("consul-acl")
    [core.wait_for_unit("nomad") for core in cores]
    core0.wait_for_unit("nomad-acl")
    core0.wait_for_unit("vault-acl")

    client0.wait_for_unit("vault-agent")
    client0.sleep(30)
    client0.log(client0.succeed("journalctl -o cat -e -u vault-agent.service"))
    client0.log(client0.succeed("bat /etc/consul.d/*"))
    client0.log(client0.succeed("bat /etc/nomad.d/*"))
    client0.wait_for_unit("consul")
    client0.wait_for_unit("nomad")

    developer.log(developer.succeed("${developerScript}"))
  '';
}
