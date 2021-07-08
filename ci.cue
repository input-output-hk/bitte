package ci

ci: steps: [
	{
		label: "nixfmt"
		dependencies: "github:NixOS/nixpkgs/nixos-21.05": ["bashInteractive", "coreutils", "git", "cacert", "gnugrep"]
		command: ["/bin/bash", "pkgs/check_fmt.sh"]
	},
]

isMaster: pull_request.base.ref == "master"

// some default values
#step: flake:  string | *".#bitte-ci-env"
#step: enable: bool | *isMaster
#step: datacenters: ["eu-central-1"]
