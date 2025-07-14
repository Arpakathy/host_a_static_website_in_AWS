terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.36.0"
    }
  }
}

# ~~~~~~~~~~~~~~~~~~~~ Configure the AWS provider ~~~~~~~~~~~~~~~~~~~~ #

provider "aws" {
  region = var.region
}
 
# ~~~~~~~~~~~ Configure the remote BACKEND to enable others to work on the same code ~~~~~~~~~~~ #

# terraform {
#   backend "s3" {
#     bucket         = "my-bucket-2ya13uvf"          // Paste the id of the bucket we priviously created 
#     key            = "terraform.tfstate"           // Paste the key of the same bucket
#     region         = "us-east-2"
#     dynamodb_table = "terraform-locking"   // From the DynamoDB table we previously created to prevent the state file from being corrupted when more than one collaborator executes the Terraform Apply command at the same time
#     encrypt        = true
#   }
# }

# ~~~~~~~~~~~~~~~~~~~~~~~~ Create the bucket ~~~~~~~~~~~~~~~~~~~~~~~~~~ #

resource "aws_s3_bucket" "bucket1" {

  bucket = var.bucket_name
  force_destroy = true
  
}

# ~~~~~~~~~~~ Configure public access parameters in the bucket ~~~~~~~~ #
resource "aws_s3_bucket_ownership_controls" "rule" {

  bucket = aws_s3_bucket.bucket1.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }

}
resource "aws_s3_bucket_public_access_block" "bucket_access_block" {
  bucket = aws_s3_bucket.bucket1.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}
resource "aws_s3_bucket_acl" "bucket1-acl" {

  bucket = aws_s3_bucket.bucket1.id
  acl    = "public-read"

  depends_on = [ aws_s3_bucket_ownership_controls.rule, aws_s3_bucket_public_access_block.bucket_access_block,aws_s3_bucket_acl.bucket1-acl]

}

# ~~~~~~~~~~~~~~~~~~~ Configure The Bucket policy ~~~~~~~~~~~~~~~~~~ #

resource "aws_s3_bucket_policy" "allow_access" {
  bucket = aws_s3_bucket.bucket1.id
  policy = data.aws_iam_policy_document.allow_access_from_another_account.json

  depends_on = [ aws_s3_bucket_acl.bucket1-acl ]
}

data "aws_iam_policy_document" "allow_access_from_another_account" {
  statement {
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "s3:*"
    ]

    resources = [
      aws_s3_bucket.bucket1.arn,
      "${aws_s3_bucket.bucket1.arn}/*",
    ]
  }
}

# ~~~~~~~~~~~~~~~~~ Upload the site content in the bucket ~~~~~~~~~~~~~

resource "null_resource" "upload_files" {

  provisioner "local-exec"  {
      command = "aws s3 sync ./${var.cp-path} s3://${aws_s3_bucket.bucket1.bucket}/ --region ${var.region} --debug" 
}
 
depends_on = [aws_s3_bucket.bucket1 , aws_s3_bucket_policy.allow_access]
 
}


# ~~~~~~~~~~~ Configure the web hosting parameters in the bucket ~~~~~~~

resource "aws_s3_bucket_website_configuration" "bucket" {
  bucket = aws_s3_bucket.bucket1.id

  index_document {
    suffix = var.file-key
  }

  error_document {
    key = var.file-key
  }

  depends_on = [aws_s3_bucket.bucket1]

}

# ~~~~~~~~~~~~~~~~~~~~~~ Configure CloudFont ~~~~~~~~~~~~~~~~~~~~~

locals {
  s3_origin_id   = "${var.bucket_name}-origin"
  s3_domain_name = "${var.bucket_name}.s3-website.${var.region}.amazonaws.com"
}

resource "aws_cloudfront_distribution" "web-distribution" {
  
  enabled = true
  
  origin {
    origin_id                = local.s3_origin_id
    domain_name              = local.s3_domain_name
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1"]
    }
  }

  default_cache_behavior {
    
    target_origin_id = local.s3_origin_id
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]

    forwarded_values {
      query_string = true

      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  price_class = "PriceClass_200"

  depends_on = [ aws_s3_bucket.bucket1 , null_resource.upload_files, aws_s3_bucket_acl.bucket1-acl, aws_s3_bucket_policy.allow_access ]
  
}

output "INFO" {
  value = "AWS Resources  has been provisioned yes. Go to http://${aws_cloudfront_distribution.web-distribution.domain_name}"
}
