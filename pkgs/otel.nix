{
  lib,
  buildGoModule,
  fetchFromGitHub,
  stdenv,
}:
buildGoModule rec {
  pname = "otel-cli";
  version = "0.0.20";

  src = fetchFromGitHub {
    owner = "equinix-labs";
    repo = pname;
    rev = "v${version}";
    sha256 = "sha256-bWdkuw0uEE75l9YCo2Dq1NpWXuMH61RQ6p7m65P1QCE=";
  };

  subPackages = ["."];

  vendorSha256 = "sha256-IJ2Gq5z1oNvcpWPh+BMs46VZMN1lHyE+M7kUinTSRr8=";

  doCheck = false;

  meta = with lib; {
    description = "OpenTelemetry command-line tool for sending events from shell scripts & similar environments";
    license = licenses.asl20;
    homepage = "https://github.com/equinix-labs/otel-cli";
    maintainers = with maintainers; [];
    platforms = platforms.linux;
  };
}
