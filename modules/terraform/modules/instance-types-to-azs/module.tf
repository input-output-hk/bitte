variable "instance_types" {
  type = list(string)
  default = [ "r5a.xlarge", "t3.micro" ]
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ec2_instance_type_offerings" "selected" {
  count = length(data.aws_availability_zones.available.names)
  filter {
    name   = "instance-type"
    values = var.instance_types
  }

  filter {
    name   = "location"
    values = [ data.aws_availability_zones.available.names[count.index] ]
  }

  location_type = "availability-zone"
}

locals {
  reverse_map = zipmap(
    data.aws_availability_zones.available.names,
      data.aws_ec2_instance_type_offerings.selected[*].instance_types
      )
  map = transpose(local.reverse_map)
}

output "reverse_map" {
  value = local.reverse_map
}

output "map" {
  value = local.map
}

output "availability_zones" {
  value = flatten(values(local.map))
}
