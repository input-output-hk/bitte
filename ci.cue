package ci

ci: steps: [
	{
		flake: "github:input-output-hk/bitte?rev=36475b8c57927ad0ccdad52497cd05aea64b4171#ci-env"
		label: "hello"
		command: ["hello", "world"]
	},
]

isMaster: pull_request.base.ref == "master"

// some default values
#step: flake:  string | *".#bitte-ci-env"
#step: enable: bool | *isMaster
#step: datacenters: ["eu-central-1"]
