variable "location" {
  type = string
}

variable "node_address_space" {
  default = "172.16.10.0/16"
}

#variable for network range
variable "node_address_prefix" {
  default = "172.16.10.0/24"
}

variable "virtualnetwork" {
  type = string
}

variable "instance_type" {
  default = "t2.micro"
}

variable "windows2022" {
  default = "ami-073bb7464cc51df7c"
}

variable "windows2019" {
  default = "ami-0ddb10e73cf07b977"
}