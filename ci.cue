package ci

ci: steps: [
	{
		label: "nixfmt"
		flakes: [
			"github:NixOS/nixpkgs/nixos-21.05#bashInteractive",
			"github:NixOS/nixpkgs/nixos-21.05#coreutils",
			"github:NixOS/nixpkgs/nixos-21.05#git",
			"github:NixOS/nixpkgs/nixos-21.05#cacert",
			"github:NixOS/nixpkgs/nixos-21.05#gnugrep",
		]
		command: ["/bin/bash", "pkgs/check_nixfmt.sh"]
	},
]

isMaster: pull_request.base.ref == "master"

// some default values
#step: flake:  string | *".#bitte-ci-env"
#step: enable: bool | *isMaster
#step: datacenters: ["eu-central-1"]
