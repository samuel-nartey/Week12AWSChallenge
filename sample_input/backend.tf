terraform {
  backend "s3" {
    bucket         = "my-terraform-state-bucket-9225"  # dedicated state bucket
    key            = "project_name/terraform.tfstate"   # path for state file
    region         = "us-east-1"
    encrypt        = true
    force_path_style = true
    locking        = true                                # enable S3-native locking
  }
}

