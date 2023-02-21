{
  inputs,
  cell,
}: let
  inherit (inputs) std;
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
  default = std.lib.dev.mkShell {
    name = nixpkgs.lib.mkForce "Bitte";
    imports = [
      std.std.devshellProfiles.default
      capsules.base
      capsules.tools
      capsules.integrations
    ];
  };
  cli = std.lib.dev.mkShell {
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
      "${std.inputs.devshell}/extra/language/rust.nix"
      capsules.base
      capsules.tools
      capsules.integrations
    ];
    commands = let
      withCategory = category: attrset: attrset // {inherit category;};
      bitte = withCategory "bitte";
    in
      with nixpkgs; [
        (bitte {package = awscli2;})
        (bitte {package = cfssl;})
        (bitte {package = cue;})
      ];
  };
}
