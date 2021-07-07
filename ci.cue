package ci

ci: steps: [
	{
    flake: "github:input-output-hk/bitte#ci-env"
		label:   "hello"
		command: "hello"
	},
]

isMaster: pull_request.base.ref == "master"

// some default values
#step: flake:  string | *".#bitte-ci-env"
#step: enable: bool | *isMaster
#step: datacenters:  ["eu-central-1"]
