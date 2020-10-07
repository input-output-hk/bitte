{ stdenv }: stdenv.mkDerivation {
  pname = "haproxy-auth-request";
  version = "2020-08-23-unstable";

  src = fetchGit {
    url = https://github.com/TimWolla/haproxy-auth-request.git;
    rev = "30bb1c3695786a2dfd320b5a589d19ccef0abab4";
    submodules = true;
  };

  DESTDIR = placeholder "out";

  postInstall = ''
    mkdir -p $out/usr/share/haproxy/haproxy-lua-http
    cp $out/usr/share/haproxy/http.lua $out/usr/share/haproxy/haproxy-lua-http/http.lua
  '';
}
