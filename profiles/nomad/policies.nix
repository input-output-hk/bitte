{config, ...}: {
  services.nomad.policies = {
    anonymous = {
      description = "Anonymous (no access)";

      namespace."*" = {policy = "deny";};
      agent.policy = "deny";
      operator.policy = "deny";
      quota.policy = "deny";
      node.policy = "deny";
      hostVolume."*".policy = "deny";
    };

    operator = {
      description = "Operator";

      namespace.default = {policy = "read";};

      node.policy = "write";
      agent.policy = "write";
      operator.policy = "write";
      plugin.policy = "list";
    };

    nomad-autoscaler = {
      description = "Nomad Autoscaler";

      namespace.default = {
        policy = "scale";
        capabilities = ["read-job"];
      };

      node.policy = "write";
    };
  };
}
