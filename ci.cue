package ci

ci: steps: [
	{
		flake: "github:input-output-hk/bitte?rev=7315e2deaa33b4cf9d64273540a7d79f519a9808#ci-env"
		label: "hello"
		command: ["hello", "world"]
	},
]

isMaster: pull_request.base.ref == "master"

// some default values
#step: flake:  string | *".#bitte-ci-env"
#step: enable: bool | *isMaster
#step: datacenters: ["eu-central-1"]
