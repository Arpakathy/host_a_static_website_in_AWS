// Create a variable for our domain name because we'll be using it a lot.
variable "www_domain_name" {
  default = "www.utrainsproject.site"
}

// We'll also need the root domain (also known as zone apex or naked domain).
variable "domain-name" {
  default = "utrainsproject.site"
}

variable "region" {
  type = string
  default = "us-east-2"
}

variable "bucket_name" {
    type = string
    description = "The name of the your bucket"
    default = "utrainsproject.site" # Replace by the name of your bucket note that your bucket name must be 
                            # the same as your domain name for the redirection to work

}

variable "cp-path" {
  type = string
  default = "Restaurantly"
}

variable "file-key" {
  type    = string
  default = "index.html"
}