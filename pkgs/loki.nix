{ stdenv, lib, buildGoModule, fetchFromGitHub, makeWrapper, systemd, fetchpatch }:

buildGoModule rec {
  version = "2.0.0";
  pname = "grafana-loki";

  src = fetchFromGitHub {
    rev = "v${version}";
    owner = "grafana";
    repo = "loki";
    sha256 = "09a0mqdmk754vigd1xqijzwazwrmfaqcgdr2c6dz25p7a65568hj";
  };

  vendorSha256 = null;

  subPackages = [ "..." ];

  patches = [
    (fetchpatch {
      # Fix expected return value in Test_validateDropConfig
      # https://github.com/grafana/loki/issues/2519
      url = "https://github.com/grafana/loki/commit/1316c0f0c5cda7c272c4873ea910211476fc1db8.patch";
      sha256 = "06hwga58qpmivbhyjgyqzb75602hy8212a4b5vh99y9pnn6c913h";
    })
    (fetchpatch {
      # Skip journald bad message
      # https://github.com/grafana/loki/pull/2928
      url = "https://github.com/grafana/loki/commit/69fffc0039fff65d939a382a15a9a8e2b57f7193.patch";
      sha256 = "sha256-8LMbA6Uw0J9RjWkxcPnUr2Wx7jfYSyosh+BG1DdXnLQ=";
    })
  ];

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = stdenv.lib.optionals stdenv.isLinux [ systemd.dev ];

  preFixup = stdenv.lib.optionalString stdenv.isLinux ''
    wrapProgram $out/bin/promtail \
      --prefix LD_LIBRARY_PATH : "${lib.getLib systemd}/lib"
  '';

  doCheck = false;

  meta = with stdenv.lib; {
    description = "Like Prometheus, but for logs";
    license = licenses.asl20;
    homepage = "https://grafana.com/oss/loki/";
    maintainers = with maintainers; [ willibutz globin mmahut ];
    platforms = platforms.unix;
  };
}
