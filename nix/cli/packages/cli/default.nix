{
  stdenv,
  lib,
  pkg-config,
  openssl,
  zlib,
  makeRustPlatform,
  fenix,
  # darwin dependencies
  darwin,
  toolchain,
}: let
  rustPlatform = makeRustPlatform {inherit (fenix.${toolchain}) cargo rustc;};

  rustPkg = fenix."${toolchain}".withComponents [
    "cargo"
    "clippy"
    "rust-src"
    "rustc"
    "rustfmt"
  ];
in
  rustPlatform.buildRustPackage
  {
    inherit
      (with builtins; (fromTOML (readFile ./Cargo.toml)).package)
      name
      version
      ;

    src = lib.cleanSource ./.;
    cargoLock.lockFile = ./Cargo.lock;
    cargoLock.outputHashes = {
      "deploy-rs-0.1.0" = "sha256-/CTQuJzFK8pO2d4S5uKhHwT+QiNfnbCKSx7O2tW0GXQ=";
    };

    nativeBuildInputs = [pkg-config];
    buildInputs =
      [openssl zlib]
      ++ lib.optionals stdenv.isDarwin
      (with darwin.apple_sdk.frameworks; [
        SystemConfiguration
        Security
        CoreFoundation
        darwin.libiconv
        darwin.libresolv
        darwin.Libsystem
      ]);

    doCheck = false;

    postInstall = ''
      export BITTE_CLUSTER=b
      export BITTE_PROVIDER=aws
      export BITTE_DOMAIN=b.b.b

      mkdir -p $out/share/zsh/site-functions
      $out/bin/bitte comp zsh > $out/share/zsh/site-functions/_bitte

      mkdir -p $out/share/bash-completion/completions
      $out/bin/bitte comp bash > $out/share/bash-completion/completions/bitte
    '';

    passthru = {
      inherit rustPlatform rustPkg;
      inherit (fenix.${toolchain}) rust-src;
      inherit (fenix) rust-analyzer;
    };
  }
  // {
    meta.description = "A swiss knife for the bitte cluster";
  }
