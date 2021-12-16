({ lib, ... }: {
  _file = ./warnings.nix;
  options = {
    warnings = lib.mkOption {
      internal = true;
      default = [];
      example = [ "The `foo' service is deprecated and will go away soon!" ];
      description = ''
        This option allows (sub-)modules to show warnings to users during
        the evaluation of the system configuration.
      '';
    };
    assertions = lib.mkOption {
      type = lib.types.listOf lib.types.unspecified;
      internal = true;
      default = [];
      example = [ { assertion = false; message = "you can't enable this for that reason"; } ];
      description = ''
        This option allows modules to express conditions that must
        hold for the evaluation of the system configuration to
        succeed, along with associated error messages for the user.
      '';
    };
  };
})
