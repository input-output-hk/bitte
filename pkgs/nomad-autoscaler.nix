{ stdenv, fetchFromGitHub, buildGoModule, go, removeReferencesTo }:
buildGoModule rec {
  pname = "nomad-autoscaler";
  version = "0.3.2";

  src = fetchFromGitHub {
    owner = "hashicorp";
    repo = "nomad-autoscaler";
    rev = "v${version}";
    sha256 = "sha256-fiVFKv89ZwEetSmZqMZDP33URy0iF/O90vnQMHp7h2g=";
  };

  patches = [
    ./0001-print-region-on-failed-scale-job.patch
    ./0002-log-region-before-api-call.patch
    ./0003-further-log-plugins.patch
    ./0004-further-logging.patch
    ./0005-really-don-t-care-anymore.patch
  ];

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

  vendorSha256 = "sha256-hU8aOQMOSSRs1+/2yUinh6w0PjmefpkC3NQtqG3YxCY=";
}
