{ stdenv, fetchFromGitHub, buildGoModule, go, removeReferencesTo }:
buildGoModule rec {
  pname = "nomad-autoscaler";
  version = "0.3.2";

  src = fetchFromGitHub {
    owner = "hashicorp";
    repo = "nomad-autoscaler";
    # branch: b-gh-472
    rev = "4c58449a37da711db2499489201ceaeb80abd237";
    sha256 = "sha256-TfJCu/sCYQg9JKXLLbPMuOKJm00uNillaqoOxIC1LcM=";
  };

  subPackages = [ "." ];

  nativeBuildInputs = [ removeReferencesTo ];

  postBuild = ''
    make bin/plugins/nomad-target
    make bin/plugins/prometheus
    make bin/plugins/target-value
    make bin/plugins/aws-asg

    mkdir -p $out/share

    for plugin in bin/plugins/*; do
      remove-references-to -t ${go} "$plugin"
      cp "$plugin" $out/share/"$(basename "$plugin")"
    done
  '';

  vendorSha256 = "sha256-C9zl6u6RQ9gPUeXa/nTgf47rFMNVfb+4Hx7Ruo5YGbk=";
}
