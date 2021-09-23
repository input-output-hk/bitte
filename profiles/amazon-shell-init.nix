{ pkgs, config, ... }:

let
  script = ''
    #!${pkgs.runtimeShell} -eu

    userData=/etc/ec2-metadata/user-data
    if grep '# amazon-shell-init' $userData; then
      source $userData
    else
      echo script not recognized, ignoring
    fi
  '';
in {
  systemd.services.amazon-shell-init = {
    inherit script;
    description = "Reconfigure the system from EC2 userdata shell script on startup";

    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];
    requires = [ "network-online.target" ];

    restartIfChanged = false;
    unitConfig.X-StopOnRemoval = false;

    path = [ pkgs.awscli config.nix.package pkgs.gnutar pkgs.xz pkgs.gawk pkgs.wget pkgs.curl ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };
}
