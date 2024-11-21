terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.67.0" 
    }
  }
}

# configure the AWS provider

provider "aws" {
  region = var.region
}

#Create a S3 Bucket 

resource "random_string" "unique" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket" "buck-1" {
  bucket = "my-bucket-${random_string.unique.result}"

}

#Setup an S3 bucket with versioning enabled

resource "aws_s3_bucket_versioning" "versioning_example" {
  bucket   = aws_s3_bucket.buck-1.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Add key to S3 Bucket 

resource "aws_s3_object" "provision_key_file" {
    bucket  = aws_s3_bucket.buck-1.id
    key     = var.file-key

}


resource "aws_dynamodb_table" "table_1" {
  name           = "${var.table_name}"
  billing_mode   = "${var.table_billing_mode}"
  hash_key       = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
   tags = {
    name       = "${var.table_name}"
  }
}

output "INFO" {
  value = "your Bucket ARN is ${aws_s3_bucket.buck-1.id}"
}