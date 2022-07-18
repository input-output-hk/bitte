{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "vault-backend";
  version = "0.3.0";

  subPackages = ["."];

  src = fetchFromGitHub {
    owner = "gherynos";
    repo = "vault-backend";
    rev = "v${version}";
    sha256 = "sha256-jKhy+0eM4+pVmbckQoCxqCWkCjqp4UhNJwcgY3VQsk4=";
  };

  vendorSha256 = "sha256-ya6wvWGQAZuTqoc1FRT0wpj3th7sJfE0HCojR5CrPBI=";

  meta = with lib; {
    description = "A Terraform HTTP backend that stores the state in a Vault secret.";
    license = licenses.asl20;
    homepage = "https://github.com/gherynos/vault-backend";
    maintainers = [maintainers.manveru];
    platforms = platforms.linux ++ platforms.darwin;
  };
}
