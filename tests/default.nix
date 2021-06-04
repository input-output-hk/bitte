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

  copyKeys = lib.forEach [ "core0" "core1" "core2" ] (machine: ''
    key="$(${deage ../. + "/encrypted/ssh/${machine}.age"})"

    echo "$key" | ${ssh machine} tee /etc/ssh/ssh_host_ed25519_key
    echo "$key" | ${ssh machine} chmod 0600 /etc/ssh/ssh_host_ed25519_key
    echo "$(< ${../. + "/encrypted/ssh/${machine}.pub"})" \
      | ${ssh machine} tee /etc/ssh/ssh_host_ed25519_key.pub
  '');

  adminScriptPreRestart = pkgs.writeBashChecked "admin.sh" ''
    set -exuo pipefail

    export PATH="${
      lib.makeBinPath
      (with pkgs; [ age agenix-cli consul jq coreutils openssh iproute ])
    }"

    cp -r ${inputs.self} bitte
    pushd bitte

    cp tests/age-bootstrap age-bootstrap
    chmod 0600 age-bootstrap

    ${lib.concatStringsSep "\n" copyKeys}
  '';

  bootstrapVaultPolicy = pkgs.writeText "bootstrap.hcl" ''
    path "*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }
  '';

  adminScriptPostRestart = pkgs.writeBashChecked "admin.sh" ''
    set -exuo pipefail

    export PATH="${
      lib.makeBinPath (with pkgs; [
        age
        agenix-cli
        consul
        jq
        coreutils
        openssh
        iproute
        vault-bin
      ])
    }"

    pushd bitte

    echo "****************************************************************"
    ${ssh "core0"} vault operator init | tee /tmp/vault-bootstrap

    readarray -t keys < <(jq < /tmp/vault-bootstrap -e -r '.unseal_keys_b64[0,1,2]')
    VAULT_TOKEN="$(jq < /tmp/vault-bootstrap -e -r '.root_token')"

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

    export VAULT_TOKEN
    export VAULT_FORMAT=json
    export VAULT_ADDR=https://core0:8200
    export VAULT_CACERT=/tmp/ca.pem
    export CONSUL_HTTP_ADDR=https://core0:8501
    export CONSUL_CAPATH=/tmp/ca.pem
    export CONSUL_CLIENT_CERT=/tmp/client.pem
    export CONSUL_CLIENT_KEY=/tmp/client-key.pem
    CONSUL_HTTP_TOKEN="$(${deage ../encrypted/consul/token-master.age})"
    export CONSUL_HTTP_TOKEN

    for core in core1 core2; do
      vault operator raft join -address "https://$core:8200"
      vault operator raft list-peers -address "https://$core:8200"
    done

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

    vault secrets enable nomad
    vault secrets enable pki
    vault secrets enable -version=2 kv

    echo "****************************************************************"
  '';

  consulCheck = pkgs.writeBashChecked "consul.sh" ''
    set -exuo pipefail

    export PATH="${lib.makeBinPath (with pkgs; [ jq consul bat ])}"

    CONSUL_HTTP_TOKEN="$(jq -r -e < /etc/consul.d/token-master.json .acl.tokens.master)"
    export CONSUL_HTTP_TOKEN

    consul members
  '';

  # cluster = import ../lib/clusters.nix {
  #   inherit pkgs lib;
  #   root = ../.;
  #   self = inputs.self;
  #   _module.args.nodeName = "core0";
  #   _module.args.self = { inherit inputs; };
  # };

  clusterFile = import ../clusters/test { };
  inherit (clusterFile) cluster;
  extra = name: ip: {
    users.users.root.openssh.authorizedKeys.keys =
      [ (builtins.readFile ./age-bootstrap.pub) ];

    services.consul.bindAddr = ip;
    services.consul.advertiseAddr = ip;
    services.consul.addresses.http = "${ip} 127.0.0.1";

    networking.firewall.enable = false;
    networking.useDHCP = false;
    networking.firewall.logRefusedPackets = true;
    networking.interfaces.eth1.ipv4.addresses = [{
      address = ip;
      prefixLength = 16;
    }];
    services.amazon-ssm-agent.enable = false;

    _module.args.nodeName = name;
    _module.args.self = { inherit inputs; };
  };
in {
  testBitte = pkgs.nixosTest {
    name = "bitte";

    nodes = {
      admin = { };

      core0 = {
        imports =
          [ ../clusters/test (extra "core0" cluster.instances.core0.privateIP) ]
          ++ cluster.instances.core0.modules;
      };

      core1 = {
        imports =
          [ ../clusters/test (extra "core1" cluster.instances.core1.privateIP) ]
          ++ cluster.instances.core1.modules;
      };

      core2 = {
        imports =
          [ ../clusters/test (extra "core2" cluster.instances.core2.privateIP) ]
          ++ cluster.instances.core2.modules;
      };
    };

    testScript = ''
      cores = [core0, core1, core2]
      start_all()

      [core.wait_for_unit("sshd") for core in cores]

      admin.systemctl("is-system-running --wait")
      admin.log(admin.succeed("${adminScriptPreRestart}"))

      [core.shutdown() for core in cores]
      [core.start() for core in cores]

      [core.wait_for_unit("vault") for core in cores]
      [core.wait_for_open_port("8200") for core in cores]

      core0.log(core0.succeed("bat /etc/consul.d/*"))

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

      admin.sleep(10)

      core0.log(core0.succeed("journalctl -e -u nomad.service"))
    '';
  };
}
