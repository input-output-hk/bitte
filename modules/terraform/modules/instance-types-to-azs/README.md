# instance-types-to-azs

Takes a list of instance types and returns a map from each given instance type to a list of the availability zones that support it:

``` shell
$ cd example
$ terraform init
Initializing modules...
- azs in ..

Initializing the backend...

Initializing provider plugins...
- Finding latest version of hashicorp/aws...
- Installing hashicorp/aws v3.27.0...
- Installed hashicorp/aws v3.27.0 (unauthenticated)

The following providers do not have any version constraints in configuration,
so the latest version was installed.

To prevent automatic upgrades to new major versions that may contain breaking
changes, we recommend adding version constraints in a required_providers block
in your configuration, with the constraint strings suggested below.

* hashicorp/aws: version = "~> 3.27.0"

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.

$ terraform apply
module.azs.data.aws_availability_zones.available: Refreshing state...
module.azs.data.aws_ec2_instance_type_offerings.selected[0]: Refreshing state...
module.azs.data.aws_ec2_instance_type_offerings.selected[5]: Refreshing state...
module.azs.data.aws_ec2_instance_type_offerings.selected[2]: Refreshing state...
module.azs.data.aws_ec2_instance_type_offerings.selected[1]: Refreshing state...
module.azs.data.aws_ec2_instance_type_offerings.selected[4]: Refreshing state...
module.azs.data.aws_ec2_instance_type_offerings.selected[3]: Refreshing state...

An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:

Terraform will perform the following actions:

Plan: 0 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes


Apply complete! Resources: 0 added, 0 changed, 0 destroyed.

Outputs:

out = {
  "m3.medium" = [
    "us-east-1a",
    "us-east-1c",
    "us-east-1d",
    "us-east-1e",
  ]
  "r5a.xlarge" = [
    "us-east-1a",
    "us-east-1b",
    "us-east-1c",
    "us-east-1d",
    "us-east-1f",
  ]
  "t3.micro" = [
    "us-east-1a",
    "us-east-1b",
    "us-east-1c",
    "us-east-1d",
    "us-east-1f",
  ]
}
```
