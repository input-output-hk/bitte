{ stdenv, fetchFromGitHub, buildGoModule, go, removeReferencesTo }:
buildGoModule rec {
  pname = "nomad-autoscaler";
  version = "0.3.3";

  src = fetchFromGitHub {
    owner = "hashicorp";
    repo = "nomad-autoscaler";
    rev = "v${version}";
    sha256 = "sha256-bN/U6aCf33B88ouQwTGG8CqARzWmIvXNr5JPr3l8cVI=";
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

  vendorSha256 = "sha256-Ls8gkfLyxfQD8krvxjAPnZhf1r1s2MhtQfMMfp8hJII=";
}
