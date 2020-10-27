{ ... }: {

  services = {
    dockerRegistry = {
      enable = true;
      enableDelete = true;
      enableRedisCache = true;
    };
  };

}
