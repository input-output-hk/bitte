{ lib, stdenv, buildGoModule, nomad-source }:

buildGoModule rec {
  pname = "nomad";
  version = "1.1.3";

  subPackages = [ "." ];

  src = nomad-source;

  vendorSha256 = "sha256-2aN1yf5+UHhCgbU4uyYtoeIXs51tLp55yY6KJE5+5Cs=";

  # ui:
  #  Nomad release commits include the compiled version of the UI, but the file
  #  is only included if we build with the ui tag.
  # nonvidia:
  #  We disable Nvidia GPU scheduling on Linux, as it doesn't work there:
  #  Ref: https://github.com/hashicorp/nomad/issues/5535
  preBuild = let
    tags = [ "ui" ] ++ lib.optional stdenv.isLinux "nonvidia";
    tagsString = lib.concatStringsSep " " tags;
  in ''
    export buildFlagsArray=(
      -tags="${tagsString}"
    )
  '';

  meta = with lib; {
    homepage = "https://www.nomadproject.io/";
    description = "A Distributed, Highly Available, Datacenter-Aware Scheduler";
    platforms = platforms.unix;
    license = licenses.mpl20;
    maintainers = with maintainers; [ rushmorem pradeepchhetri endocrimes ];
  };
}
