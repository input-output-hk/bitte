{ipxe, writeText, syslinux}:
let
  embedScript = writeText "ipxe" ''
    #!ipxe

    echo Amazon EC2 - iPXE boot via user-data
    echo CPU: ''${cpuvendor} ''${cpumodel}
    ifstat ||
    dhcp ||
    route ||
    chain -ar http://169.254.169.254/latest/user-data
  '';
in
  (ipxe.overrideAttrs (old: {
    makeFlags = [
      "ECHO_E_BIN_ECHO=echo" "ECHO_E_BIN_ECHO_E=echo" # No /bin/echo here.
      "ISOLINUX_BIN_LIST=${syslinux}/share/syslinux/isolinux.bin"
      "LDLINUX_C32=${syslinux}/share/syslinux/ldlinux.c32"
      # fix for https://github.com/danderson/netboot/pull/117
      "EMBEDDED_IMAGE=${embedScript}"
    ];
  }))
