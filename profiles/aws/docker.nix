{ ... }: {
  imports = [ ../docker.nix ];
  # needed to access AWS meta-data after docker starts veth* devices.
  networking.interfaces.ens5.ipv4.routes = [{
    address = "169.254.169.252";
    prefixLength = 30;
  }];
}
