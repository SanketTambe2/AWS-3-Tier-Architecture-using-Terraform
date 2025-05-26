variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.10.0.0/16"
}


variable "instance_type" {
  description = "EC2 Instance type"
  type        = string
  default     = "t2.micro"  # or any other instance type you want to use
}
