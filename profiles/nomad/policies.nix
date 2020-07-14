{ config, ... }: {
  services.nomad.policies = {
    admin = {
      description = "Admin (full access)";
      namespace."*" = {
        policy = "write";
        capabilities = [ "alloc-node-exec" ];
      };
      agent.policy = "write";
      operator.policy = "write";
      quota.policy = "write";
      node.policy = "write";
      hostVolume."*".policy = "write";
    };

    anonymous = {
      description = "Anonymous (no access)";

      namespace."*" = { policy = "deny"; };
      agent.policy = "deny";
      operator.policy = "deny";
      quota.policy = "deny";
      node.policy = "deny";
      hostVolume."*".policy = "deny";
    };

    developer = {
      description = "Developer";

      namespace.default = {
        policy = "read";
        capabilities = [ "submit-job" "dispatch-job" "read-logs" ];
      };
    };

    operator = {
      description = "Operator";

      namespace.default = { policy = "read"; };

      node.policy = "write";
      agent.policy = "write";
      operator.policy = "write";
      plugin.policy = "list";
    };
  };
}
