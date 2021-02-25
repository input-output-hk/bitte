{ stdenv }:
stdenv.mkDerivation {
  pname = "haproxy-auth-request";
  version = "2020-08-23-unstable";

  src = fetchGit {
    url = "https://github.com/TimWolla/haproxy-auth-request.git";
    ref = "main";
    rev = "c3c9349166fb4aa9a9b3964267f3eaa03117c3a3";
    submodules = true;
  };

  DESTDIR = placeholder "out";

  postInstall = ''
    mkdir -p $out/usr/share/haproxy/haproxy-lua-http
    cp $out/usr/share/haproxy/http.lua $out/usr/share/haproxy/haproxy-lua-http/http.lua
  '';
}
