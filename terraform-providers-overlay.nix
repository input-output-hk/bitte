inputs: let
  inherit (inputs) nixpkgs;
  inherit (nixpkgs) lib;
in
  final: prev: {
    inherit (prev) terraform_0_13 terraform_0_14;

    terraform-provider-names = ["acme" "aws" "consul" "local" "nomad" "null" "sops" "tls" "vault" "rabbitmq" "postgresql" "bitwarden"];

    terraform-provider-versions = lib.listToAttrs (map (name: let
      provider = final.terraform-providers.${name};
      provider-source-address =
        provider.provider-source-address or "registry.terraform.io/nixpkgs/${name}";
      parts = lib.splitString "/" provider-source-address;
      source = lib.concatStringsSep "/" (lib.tail parts);
    in
      lib.nameValuePair name {
        inherit source;
        version = "= ${provider.version}";
      }) final.terraform-provider-names);

    terraform-providers =
      prev.terraform-providers
      // (let
        inherit (prev) buildGoModule;
        buildWithGoModule = data:
          buildGoModule {
            pname = data.repo;
            inherit (data) version;
            subPackages = ["."];
            src = prev.fetchFromGitHub {inherit (data) owner repo rev sha256;};
            vendorSha256 = data.vendorSha256 or null;

            # Terraform allow checking the provider versions, but this breaks
            # if the versions are not provided via file paths.
            postBuild = "mv $NIX_BUILD_TOP/go/bin/${data.repo}{,_v${data.version}}";
            passthru = data;
          };
      in {
        acme = buildWithGoModule {
          provider-source-address = "registry.terraform.io/getstackhead/acme";
          version = "1.5.0-patched2";
          vendorSha256 = "0qapar40bdbyf7igf7fg5riqdjb2lgzi4z0l19hj7q1xmx4m8mgx";
          owner = "getstackhead";
          repo = "terraform-provider-acme";
          rev = "v1.5.0-patched2";
          sha256 = "1h6yk0wrn1dxsy9dsh0dwkpkbs8w9qjqqc6gl9nkrqbcd558jxfb";
        };
        aws = buildWithGoModule {
          provider-source-address = "registry.terraform.io/hashicorp/aws";
          version = "3.27.0";
          vendorSha256 = "sha256-moTiCt/1dB7ZmpQcqX/yeztZmH/GNQWERih5jZcBAV4=";
          owner = "hashicorp";
          repo = "terraform-provider-aws";
          rev = "v3.27.0";
          sha256 = "sha256-rdO2eb41I5eBY/htRTCqdN843eWnnwqCW3ER824txUI=";
        };
        local = buildWithGoModule {
          provider-source-address = "registry.terraform.io/hashicorp/local";
          version = "2.0.0";
          vendorSha256 = null;
          owner = "hashicorp";
          repo = "terraform-provider-local";
          rev = "v2.0.0";
          sha256 = "sha256-5ZMDyzCFyNwdQ3mpccx5jzz/9N6eAkQvkhUPSIeZNTA=";
        };
        null = buildWithGoModule {
          provider-source-address = "registry.terraform.io/hashicorp/null";
          version = "3.0.0";
          vendorSha256 = null;
          owner = "hashicorp";
          repo = "terraform-provider-null";
          rev = "v3.0.0";
          sha256 = "sha256-+eR9JaAZBhHxMOwlw5bJsrOo0LzB7QYLikIkk5jeM2Q=";
        };
        consul = buildWithGoModule {
          provider-source-address = "registry.terraform.io/hashicorp/consul";
          version = "2.11.0";
          vendorSha256 = null;
          owner = "hashicorp";
          repo = "terraform-provider-consul";
          rev = "v2.11.0";
          sha256 = "007v7blzsfh0gd3i54w8jl2czbxidwk3rl2wgdncq423xh9pkx1d";
        };
        vault = buildWithGoModule {
          provider-source-address = "registry.terraform.io/hashicorp/vault";
          version = "2.18.0";
          vendorSha256 = null;
          owner = "hashicorp";
          repo = "terraform-provider-vault";
          rev = "v2.18.0";
          sha256 = "0lmgh9w9n0qvg9kf4av1yql2dh10r0jjxy5x3vckcpfc45lgsy40";
        };
        sops = buildWithGoModule {
          version = "0.6.3";
          vendorSha256 = "sha256-kBQVgxeGTu0tLgbjoCMdswwMvfZI3tEXNHa8buYJXME=";
          owner = "carlpett";
          repo = "terraform-provider-sops";
          rev = "v0.6.3";
          sha256 = "sha256-yfHO/vGk7M5CbA7VkrxLVldAMexhuk0wTEe8+5g8ZrU=";
        };
        rabbitmq = buildWithGoModule {
          provider-source-address = "registry.terraform.io/cyrilgdn/rabbitmq";
          version = "1.6.0";
          vendorSha256 = "sha256-wbnjAM2PYocAtRuY4fjLPGFPJfzsKih6Q0YCvFyMulQ=";
          owner = "cyrilgdn";
          repo = "terraform-provider-rabbitmq";
          rev = "v1.6.0";
          sha256 = "sha256-gtqH+/Yg5dCovdDlg/JrDqOKfxTKPwfCvnV8MUAjLGs=";
        };
        postgresql = buildWithGoModule {
          provider-source-address = "registry.terraform.io/cyrilgdn/postgresql";
          version = "1.14.0";
          vendorSha256 = null;
          owner = "cyrilgdn";
          repo = "terraform-provider-postgresql";
          rev = "v1.14.0";
          sha256 = "sha256-2VDPKpBedX0Q6xWwUL/2afGvtvlRSQhK+wdXTLyI6CM=";
        };
        bitwarden = buildWithGoModule {
          provider-source-address = "registry.terraform.io/maxlaverse/bitwarden";
          version = "0.1.0";
          vendorSha256 = "sha256-oS7N9tTHUngos8lCtQ60KQOeQ7YsFOy+9vGimSECYWU=";
          owner = "maxlaverse";
          repo = "terraform-provider-bitwarden";
          rev = "v0.1.0";
          sha256 = "sha256-giQiehlry6RCYkTh/N9nLlrO8wN7X0gnKEg0Ozptyxo=";
        };
      });

    terraform-with-plugins =
      final.terraform_0_13.withPlugins
      (lib.attrVals final.terraform-provider-names);
  }
