{ ... }: {
  imports = [ ../nomad/client.nix ];
  services.nomad.datacenter = "dc1";
}
