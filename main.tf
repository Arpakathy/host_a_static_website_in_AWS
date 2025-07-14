terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.36.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# --------------------- Create a Private S3 Bucket ---------------------- #

resource "aws_s3_bucket" "bucket1" {
  bucket         = var.bucket_name
  force_destroy  = true
}

# Enforce bucket owner control
resource "aws_s3_bucket_ownership_controls" "rule" {
  bucket = aws_s3_bucket.bucket1.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "bucket_access_block" {
  bucket                  = aws_s3_bucket.bucket1.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DO NOT assign any ACL (like public-read) — omit aws_s3_bucket_acl

# Remove the insecure bucket policy — bucket remains private

# -------------------- Upload Files to Private Bucket ------------------- #

resource "null_resource" "upload_files" {
  provisioner "local-exec" {
    command = "aws s3 sync ./${var.cp-path} s3://${aws_s3_bucket.bucket1.bucket}/ --region ${var.region}"
  }

  depends_on = [
    aws_s3_bucket.bucket1,
    aws_s3_bucket_public_access_block.bucket_access_block,
    aws_s3_bucket_ownership_controls.rule
  ]
}

# ------------------ Bucket Website Config (still supported) ------------------- #

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

# ---------------- Configure CloudFront with Private Bucket ----------------

locals {
  s3_origin_id   = "${var.bucket_name}-origin"
}

# Optional: Use Origin Access Control instead of OAI
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "s3-access-control"
  description                       = "Access control for private S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "web-distribution" {
  enabled = true

  origin {
    domain_name = aws_s3_bucket.bucket1.bucket_regional_domain_name
    origin_id   = local.s3_origin_id

    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id

    s3_origin_config {
      origin_access_identity = "" # Required to be empty with OAC
    }
  }

  default_cache_behavior {
    target_origin_id       = local.s3_origin_id
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = true
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
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

  depends_on = [
    aws_s3_bucket.bucket1,
    aws_cloudfront_origin_access_control.oac,
    null_resource.upload_files
  ]
}

output "INFO" {
  value = "AWS resources have been provisioned. Visit your site at: http://${aws_cloudfront_distribution.web-distribution.domain_name}"
}
