{
  inputs,
  cell,
}: let
  inherit (inputs.std) std;
  inherit (inputs) capsules nixpkgs;
  l = nixpkgs.lib // builtins;

  rust-dev-pkgs =
    [
      nixpkgs.openssl
      nixpkgs.zlib
      nixpkgs.pkg-config
      # rustPkg
      # rust-analyzer-nightly
    ]
    ++ l.optionals nixpkgs.stdenv.isDarwin (with nixpkgs.darwin;
      with nixpkgs.apple_sdk.frameworks; [
        libiconv
        libresolv
        Libsystem
        SystemConfiguration
        Security
        CoreFoundation
      ]);
in {
  default = std.lib.mkShell {
    packages = rust-dev-pkgs;
    env = [
      {
        name = "RUST_BACKTRACE";
        value = "1";
      }
      # {
      #   name = "RUST_SRC_PATH";
      #   value = "${rustPkg}/lib/rustlib/src/rust/library";
      # }
    ];
    imports = [
      capsules.base
      capsules.tools
      capsules.integrations
      capsules.hooks
    ];
  };
}
