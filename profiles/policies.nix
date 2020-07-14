{ config, ... }:
{ }

# nomad = {
#   admin = {
#     description = "Root token (full-access)";
#     namespace."*" = {
#       policy = "write";
#       capabilities = [ "alloc-node-exec" ];
#     };
#     agent.policy = "write";
#     operator.policy = "write";
#     quota.policy = "write";
#     node.policy = "write";
#     host_volume."*".policy = "write";
#   };
#
#   nomad-client = { };
#
#   nomad-server = { };
#
#   anonymous = {
#     description = "Anonymous policy (full-access)";
#
#     namespace."*" = {
#       policy = "write";
#       capabilities = [ "alloc-node-exec" ];
#     };
#     agent.policy = "write";
#     operator.policy = "write";
#     quota.policy = "write";
#     node.policy = "write";
#     host_volume."*".policy = "write";
#   };
# };
