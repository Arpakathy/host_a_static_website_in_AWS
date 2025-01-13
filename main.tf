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

  
  redirect_all_requests_to {
        host_name = "https://${var.www_domain_name}"
  }

  depends_on = [aws_s3_bucket.bucket1]

}

# AWS Route53 zone data source with the domain name and private zone set to false
data "aws_route53_zone" "zone" {
  name         = var.domain-name
  private_zone = false
}

# AWS Route53 record resource for certificate validation with dynamic for_each loop and properties for name, records, type, zone_id, and ttl.
resource "aws_route53_record" "cert_validation" {

  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  type            = each.value.type
  zone_id         = data.aws_route53_zone.zone.zone_id
  ttl             = 60
}

# AWS Route53 record resource for the "www" subdomain. The record uses an "A" type record and an alias to the AWS CloudFront distribution with the specified domain name and hosted zone ID. The target health evaluation is set to false.


resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.zone.id
  name    = "www.${var.domain-name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.web-distribution.domain_name
    zone_id                = aws_cloudfront_distribution.web-distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

# AWS Route53 record resource for the apex domain (root domain) with an "A" type record. The record uses an alias to the AWS CloudFront distribution with the specified domain name and hosted zone ID. The target health evaluation is set to false.
resource "aws_route53_record" "apex" {
  zone_id = data.aws_route53_zone.zone.id
  name    = var.domain-name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.web-distribution.domain_name
    zone_id                = aws_cloudfront_distribution.web-distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

# ACM certificate resource with the domain name and DNS validation method, supporting subject alternative names

resource "aws_acm_certificate" "cert" {
  
  domain_name               = var.domain-name
  validation_method         = "DNS"
  subject_alternative_names = [var.domain-name]

  lifecycle {
    create_before_destroy = true
  }
}

# ACM certificate validation resource using the certificate ARN and a list of validation record FQDNs

resource "aws_acm_certificate_validation" "cert" {
 
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
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
    allowed_methods  = ["GET", "HEAD","OPTIONS"]
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
      locations        = []
      restriction_type = "none"
    }
  }
  
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  price_class = "PriceClass_200"

  depends_on = [ aws_s3_bucket.bucket1 , null_resource.upload_files, aws_s3_bucket_acl.bucket1-acl, aws_s3_bucket_policy.allow_access ]
  
}

# CloudFront origin access control for S3 origin type with always signing using sigv4 protocol

resource "aws_cloudfront_origin_access_control" "default" {
  name                              = "cloudfront OAC"
  description                       = "description OAC"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

output "INFO" {
  value = "AWS Resources  has been provisioned yes. Go to http://${aws_cloudfront_distribution.web-distribution.domain_name}"
}