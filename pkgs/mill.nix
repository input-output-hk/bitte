{ stdenv, makeWrapper, fetchurl, jre }:
stdenv.mkDerivation rec {
  name = "mill";
  version = "0.6.2";

  src = fetchurl {
    url =
      "https://github.com/lihaoyi/mill/releases/download/${version}/${version}-assembly";
    sha256 = "1ngn8bmdhwk6sllrnv4jawrchsdwgk78ivn98vscl5ymz9pql5jz";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm555 "$src" "$out/bin/.mill-wrapped"
    # can't use wrapProgram because it sets --argv0
    makeWrapper "$out/bin/.mill-wrapped" "$out/bin/mill" \
      --prefix PATH : "${jre}/bin" \
      --set JAVA_HOME "${jre}"
    runHook postInstall
  '';
}
