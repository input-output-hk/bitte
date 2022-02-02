{ lib
, config
, terralib
, ...
}:

let

  inherit (terralib) allowS3For;
  bucketArn = "arn:aws:s3:::${config.cluster.s3Bucket}";
  allowS3ForBucket = allowS3For bucketArn;

  inherit (terralib) var id;
  c = "create";
  r = "read";
  u = "update";
  d = "delete";
  l = "list";
  s = "sudo";

  secretsFolder = "encrypted";
  starttimeSecretsPath = "kv/nomad-cluster";
  # starttimeSecretsPath = "starttime"; # TODO: migrate job configs; use variables/constants -> nomadlib
  runtimeSecretsPath = "runtime";
in
{
  # cluster level
  # --------------
  tf.hydrate.configuration = {

    locals.policies = {
      vault.admin = {
        path."auth/userpass/users/*".capabilities = [ c r u d l ];
        path."sys/auth/userpass".capabilities = [ c r u d l s ];
      };
      vault.developer = {
        path."kv/*".capabilities = [ c r u d l ]; # TODO: remove
      };
      vault."nomad-cluster" = { };

      # -------------------------
      # nixos reconciliation loop
      # TODO: migrate to more reliable tf reconciliation loop
      consul.developer = {
        service_prefix."midnight-" = {
          policy = "write";
          intentions = "write";
        };
      };

      nomad.developer = {
        host_volume."*".policy = "read";
        agent.policy = "read";
        node.policy = "read";
        quota.policy = "read";
        namespace."midnight-*".policy = "write";
        namespace."default" = {
          policy = "read";
          capabilities = [
            "submit-job"
            "dispatch-job"
            "read-logs"
            "alloc-exec"
            "alloc-node-exec"
            "alloc-lifecycle"
          ];
        };
      };
    };
  };
}

