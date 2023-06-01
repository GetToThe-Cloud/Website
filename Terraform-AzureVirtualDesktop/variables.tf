variable "resource_group_location" {
default     = "westeurope"
description = "Location of the resource group."
}

variable "rg_name" {
type        = string
default     = "rg-gettothecloudAVD"
description = "Name of the Resource group in which to deploy service objects"
}

variable "workspace" {
type        = string
description = "Name of the Azure Virtual Desktop workspace"
default     = "AVD-Workspace"
}

variable "hostpool" {
type        = string
description = "Name of the Azure Virtual Desktop host pool"
default     = "AVD-Hostpool"
}

variable "rfc3339" {
type        = string
default     = "2023-06-10T12:43:13Z"
description = "Registration token expiration"
}

variable "prefix" {
type        = string
default     = "GttC"
description = "Prefix of the name of the AVD machine(s)"
}

variable "node_address_space" {
  default = ["10.0.0.0/16"]
}

#variable for network range
variable "node_address_prefix" {
  default = "10.0.1.0/24"
}

variable "virtualnetwork" {
    type = string
  default = "AVD-VirtualNetwork"
}
variable "subnet_range" {
  default = ["10.0.1.0/24"]

}
variable "subnet_name" {
  default = "AVD-Subnet"
  type = string
}