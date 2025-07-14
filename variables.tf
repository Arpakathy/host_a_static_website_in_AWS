variable "region" {
  type = string
  default = "us-east-2"
}

variable "bucket_name" {
    type = string
    description = "The name of the your bucket"
    default = "buckethiringly" # replace here by the name of your bucket  
}

variable "cp-path" {
  type = string
  default = "Restaurantly"
}

variable "file-key" {
  type    = string
  default = "index.html"
}

