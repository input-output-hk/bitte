{ name, skopeo, lib, json, dockerImages, writeShellScriptBin, vault-bin, awscli
, coreutils, jq, nomad, consul, nixFlakes, docker, curl, gnugrep, gitMinimal }:
let
  pushImage = imageId: image:
    let
      parts = builtins.split "/" image.imageName;
      registry = builtins.elemAt parts 0;
      repo = builtins.elemAt parts 2;
      url =
        "https://developer:$dockerPassword@${registry}/v2/${repo}/tags/list";
    in ''
      echo -n "Pushing ${image.imageName}:${image.imageTag} ... "

      if curl -s "${url}" | grep "${image.imageTag}" &> /dev/null; then
        echo "Image already exists in registry"
      else
        storePath="$(nix-store -r ${
          builtins.unsafeDiscardStringContext image.drvPath
        })"

        skopeo --insecure-policy \
               copy --dest-creds developer:$dockerPassword \
               "docker-archive:$storePath" \
               docker://${registry}/${image.imageName}:${image.imageTag}
      fi
    '';
  pushImages = lib.mapAttrsToList pushImage dockerImages;
in writeShellScriptBin "nomad-run" ''
  export PATH="${
    lib.makeBinPath [
      vault-bin
      awscli
      coreutils
      jq
      nomad
      consul
      nixFlakes
      curl
      gnugrep
      gitMinimal
      docker
      skopeo
    ]
  }"
  echo "running job: ${json}"

  set -euo pipefail

  vault token lookup &> /dev/null \
  || vault login -method github -path github-employees -no-print

  aws s3 ls &> /dev/null \
  || (
    echo "Generating AWS Credentials and setting them in $AWS_PROFILE ..."

    if grep "\[$AWS_PROFILE\]" ~/.aws/credentials; then
      echo "found existing profile, updating credentials..."
    else
      echo "adding $AWS_PROFILE profile..."
      mkdir -p ~/.aws
      printf "\\n[$AWS_PROFILE]" >> ~/.aws/credentials
    fi

    creds="$(vault read -format json aws/creds/developer)"
    aws configure set --profile "$AWS_PROFILE" aws_access_key_id "$( echo "$creds" | jq -r -e .data.access_key )"
    aws configure set --profile "$AWS_PROFILE" aws_secret_access_key "$(echo "$creds" | jq -r -e .data.secret_key)"
    echo "Waiting ten seconds for AWS to catch up..."
    sleep 10
  )

  echo "Checking for Nomad credentials..."
  if nomad acl token self | grep -v  'Secret ID'; then
    echo "Nomad token found"
  else
    echo "generating new NOMAD_TOKEN from Vault"
    NOMAD_TOKEN="$(vault read -field secret_id nomad/creds/developer)"
    export NOMAD_TOKEN
  fi

  echo "Checking for Consul credentials"
  if consul acl token read -self | grep -v SecretID | grep github-employees; then
    echo "Consul token found"
  else
    echo "generating new CONSUL_HTTP_TOKEN from Vault"
    CONSUL_HTTP_TOKEN="$(vault read -field token consul/creds/developer)"
    export CONSUL_HTTP_TOKEN
  fi

  if [ -n "''${COPY_NIX_CACHE:-}" ]; then
    cache="$(nix eval ".#clusters.$BITTE_CLUSTER.proto.config.cluster.s3Cache" --raw)"

    if [ ! -s secrets/nix-secret-key-file ]; then
      mkdir -p secrets
      vault kv get -field private kv/cache/nix-key > secrets/nix-secret-key-file
    fi

    echo "Copying closure to the binary cache..."
    nix copy --to "$cache&secret-key=secrets/nix-secret-key-file" ${json}
  fi

  ${lib.optionalString ((builtins.length pushImages) > 0) ''
    dockerPassword="$(vault kv get -field value kv/nomad-cluster/docker-developer-password)"
    domain="$(nix eval ".#clusters.x86_64-linux.$BITTE_CLUSTER.proto.config.cluster.domain" --raw)"
    echo "$dockerPassword" | docker login "docker.$domain" -u developer --password-stdin
  ''}

  ${builtins.concatStringsSep "\n" pushImages}

  echo "Submitting Job..."
  jq --arg token "$CONSUL_HTTP_TOKEN" '.Job.ConsulToken = $token' < ${json} \
  | curl -s -q \
    --cacert ~/Downloads/fakelerootx1.pem \
    -X POST \
    -H "X-Nomad-Token: $NOMAD_TOKEN" \
    -H "X-Vault-Token: $(vault print token)" \
    -d @- \
    "$NOMAD_ADDR/v1/jobs"
''
