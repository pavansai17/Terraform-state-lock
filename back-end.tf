terraform {
  backend "s3" {
    bucket         = "terraform-project-bucket17"
    key            = "state-file/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-table"
    encrypt        = true
  }
}