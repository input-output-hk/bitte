package ci

ci: steps: [
	{
    flake: "github:NixOS/nixpkgs/nixos-21.05#hello"
		label:   "hello"
		command: "hello"
	},
]

isMaster: pull_request.base.ref == "master"

// some default values
#step: flake:  string | *".#bitte-ci-env"
#step: enable: bool | *isMaster
