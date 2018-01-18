variable "region" {
  default = "eu-central-1"
}

variable "amis" {
  type = "map"
  default = {
    "eu-central-1" = "ami-13b8337c"
  }
}

variable "public_key" { }
