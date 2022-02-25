{ lib }: names: pathFun:
{
  services.nomad.client.host_volume = lib.listToAttrs (lib.forEach names (name: {
    inherit name;
    value = {
      path = pathFun name;
      read_only = false;
    };
  }));
}
