terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Use a recent version
    }
  }
  required_version = ">= 1.5.0" # Ensures you have a recent Terraform version
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1" # Change to your preferred region
  # Credentials are automatically loaded from ~/.aws/credentials via AWS CLI
}

