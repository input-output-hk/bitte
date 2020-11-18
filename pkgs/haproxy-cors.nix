{ stdenv }:
stdenv.mkDerivation {
  pname = "haproxy-lua-cors";
  version = "2020-10-22-unstable";

  src = fetchGit {
    url = "https://github.com/haproxytech/haproxy-lua-cors.git";
    rev = "0cd674749f98657f9a86dde2abacb4bb61eac438";
    submodules = true;
  };

  DESTDIR = placeholder "out";

  installPhase = ''
    mkdir -p $out/usr/share/haproxy/haproxy-lua-cors
    cp lib/cors.lua $out/usr/share/haproxy/haproxy-lua-cors/cors.lua
  '';
}
