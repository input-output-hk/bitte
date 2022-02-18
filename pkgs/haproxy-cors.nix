{ stdenv, fetchgit }:
stdenv.mkDerivation {
  pname = "haproxy-lua-cors";
  version = "2020-10-22-unstable";

  src = fetchgit {
    url = "https://github.com/haproxytech/haproxy-lua-cors.git";
    rev = "0cd674749f98657f9a86dde2abacb4bb61eac438";
    sha256 = "15mnhlqa8ipy3bryvy7v9srnvzj0qqcsd3rjvagxn5658hg97r9d";
    fetchSubmodules = true;
  };

  DESTDIR = placeholder "out";

  installPhase = ''
    mkdir -p $out/usr/share/haproxy/haproxy-lua-cors
    cp lib/cors.lua $out/usr/share/haproxy/haproxy-lua-cors/cors.lua
  '';
}
