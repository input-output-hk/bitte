package ci

ci: steps: [
	{
		flake: "github:input-output-hk/bitte?rev=fa03cb3ab0ba2bee8700daccbddc30b2993d501a#ci-env"
		label: "hello"
		command: ["hello", "world"]
	},
]

isMaster: pull_request.base.ref == "master"

// some default values
#step: flake:  string | *".#bitte-ci-env"
#step: enable: bool | *isMaster
#step: datacenters: ["eu-central-1"]
