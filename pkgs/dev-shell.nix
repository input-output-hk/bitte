{pkgs}:
with pkgs;
  mkShell.override {stdenv = stdenvNoCC;} {
    # TF_LOG = "TRACE";

    LOG_LEVEL = "debug";

    buildInputs = [
      awscli2
      cfssl
      consul
      consul-template
      dnsutils
      ipcalc
      jq
      nixfmt
      nixpkgs-fmt
      nodePackages.prettier
      nomad
      openssl
      shfmt
      sops
      ssm-session-manager-plugin
      terraform-with-plugins
      treefmt
      vault-bin
    ];
  }
