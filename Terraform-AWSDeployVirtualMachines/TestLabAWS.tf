provider "aws" {
  region = var.location
  access_key = "AKIA4J67JDBYN7XICGQ7"
  secret_key = "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"
}

variable "DCcomputername" {
  default = "DC01"
}

variable "EXcomputername" {
  default = "EX01"
}

variable "RDPcomputername" {
  default = "RDP01"
}

resource "aws_vpc" "testlabvpc"{
  cidr_block = var.node_address_prefix
}

resource "aws_subnet" "testlabsubnet" {
  vpc_id = aws_vpc.testlabvpc.id
  cidr_block = "172.16.10.0/24"
  availability_zone = "eu-west-2b"
  tags = {
    name = var.virtualnetwork
  }
}

resource "aws_instance" "dc01" {
  count = 1

  ami                    = var.windows2022 #windows 2022
  instance_type          = var.instance_type
  key_name               = "TerraformPasswordFile"
  subnet_id              = aws_subnet.testlabsubnet.id
  private_ip             = "172.16.10.5"
  vpc_security_group_ids = [ aws_security_group.dc01websg.id ]
  get_password_data      = true
      tags = {
      Name = var.DCcomputername
    }
}
resource "aws_instance" "ex01" {
  count = 1

  ami                    = var.windows2022 #windows 2022
  instance_type          = var.instance_type
  key_name               = "TerraformPasswordFile"
  subnet_id              = aws_subnet.testlabsubnet.id
  private_ip             = "172.16.10.6"
  associate_public_ip_address = true
  vpc_security_group_ids = [ aws_security_group.ex01websg.id ]
  get_password_data      = true
      tags = {
      Name = var.EXcomputername
    }
}
resource "aws_instance" "rdp01" {
  count = 1

  ami                    = var.windows2019 #windows 2019
  instance_type          = var.instance_type
  key_name               = "TerraformPasswordFile"
  subnet_id              = aws_subnet.testlabsubnet.id
  private_ip             = "172.16.10.7"
  associate_public_ip_address = true
  vpc_security_group_ids = [ aws_security_group.rdp01websg.id ]
  get_password_data      = true
      tags = {
      Name = var.RDPcomputername
    }
}


resource "aws_security_group" "dc01websg" {
  name = "dc01-sg01"
  vpc_id = aws_vpc.testlabvpc.id
  ingress {
    protocol = "tcp"
    from_port = 5985
    to_port = 5985
    cidr_blocks = [ "0.0.0.0/0" ]
  }
}

locals {
  ports_in = [
    443,
    5985
  ]
}

resource "aws_security_group" "ex01websg" {
  name = "ex01-sg01"
  vpc_id = aws_vpc.testlabvpc.id
  dynamic "ingress"{
    for_each = toset(local.ports_in)
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }  
  }
}
resource "aws_security_group" "rdp01websg" {
  name = "rdp01-sg01"
  vpc_id = aws_vpc.testlabvpc.id
  ingress {
    protocol = "tcp"
    from_port = 3389
    to_port = 3389
    cidr_blocks = [ "0.0.0.0/0" ]
  }
}

resource "null_resource" "dc01" {
  count = 1

  triggers = {
    password = "${rsadecrypt(aws_instance.dc01.*.password_data[count.index], file("TerraformPasswordFile.pem"))}"
  }
}
resource "null_resource" "ex01" {
  count = 1

  triggers = {
    password = "${rsadecrypt(aws_instance.ex01.*.password_data[count.index], file("TerraformPasswordFile.pem"))}"
  }
}

resource "null_resource" "rdp01" {
  count = 1

  triggers = {
    password = "${rsadecrypt(aws_instance.rdp01.*.password_data[count.index], file("TerraformPasswordFile.pem"))}"
  }
}

output "Administrator_Password_DC01" {
    value = "${null_resource.dc01.*.triggers.password}"
}
output "Administrator_Password_EX01" {
    value = "${null_resource.ex01.*.triggers.password}"
}
output "Administrator_Password_RDP01" {
    value = "${null_resource.rdp01.*.triggers.password}"
}
