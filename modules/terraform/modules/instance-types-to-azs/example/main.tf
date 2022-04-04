provider "aws" {
  region = "us-east-1"
}

module "azs" {
    source = "../"
    instance_types = [ "r5a.xlarge", "t3.micro", "m3.medium" ]
}

output "out" {
  value = module.azs.map
}
