{ stdenv, fetchgit }:
stdenv.mkDerivation {
  pname = "haproxy-auth-request";
  version = "2020-08-23-unstable";

  src = fetchgit {
    url = "https://github.com/TimWolla/haproxy-auth-request.git";
    rev = "c3c9349166fb4aa9a9b3964267f3eaa03117c3a3";
    sha256 = "03vy7hj6xynclnshhmiydnisi6bfglnqkzrkja8snkiigcd9lab0";
    fetchSubmodules = true;
  };

  DESTDIR = placeholder "out";

  postInstall = ''
    mkdir -p $out/usr/share/haproxy/haproxy-lua-http
    cp $out/usr/share/haproxy/http.lua $out/usr/share/haproxy/haproxy-lua-http/http.lua
  '';
}
