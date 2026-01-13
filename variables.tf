variable "bucket_name_suffix" {
  description = "A unique suffix to avoid S3 bucket name conflicts (globally unique)."
  type        = string
  default     = "bucket-9225"
}

variable "aws_region" {
  description = "The AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

