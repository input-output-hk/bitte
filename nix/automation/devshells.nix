{
  inputs,
  cell,
}: let
  inherit (inputs.std) std;
  inherit (inputs) capsules nixpkgs;
  inherit (inputs.cells.cli.packages) bitte;
  inherit (bitte) rustPkg rustPlatform;
  l = nixpkgs.lib // builtins;

  rust-dev-pkgs =
    [
      nixpkgs.zlib
      nixpkgs.pkg-config
      rustPkg
      bitte.rust-analyzer
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
    imports = [
      capsules.base
      capsules.tools
      capsules.integrations
      capsules.hooks
    ];
  };
  dev = std.lib.mkShell {
    packages = rust-dev-pkgs;
    language.rust = {
      packageSet = rustPlatform;
      enableDefaultToolchain = false;
    };
    env = [
      {
        name = "RUST_BACKTRACE";
        value = "1";
      }
      {
        name = "RUST_SRC_PATH";
        value = "${rustPkg}/lib/rustlib/src/rust/library";
      }
      {
        name = "PKG_CONFIG_PATH";
        value = l.makeSearchPath "lib/pkgconfig" bitte.buildInputs;
      }
    ];
    imports = [
      "${inputs.std.inputs.devshell}/extra/language/rust.nix"
      capsules.base
      capsules.tools
      capsules.integrations
      capsules.hooks
    ];
    commands = let
      withCategory = category: attrset: attrset // {inherit category;};
      bitte = withCategory "bitte";
    in
      with nixpkgs; [
        (bitte {package = awscli;})
        (bitte {package = cfssl;})
        (bitte {package = cue;})
      ];
  };
}
