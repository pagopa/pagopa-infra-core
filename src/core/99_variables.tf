variable "prefix" {
  type    = string
  default = "pagopa"
  validation {
    condition = (
      length(var.prefix) <= 6
    )
    error_message = "Max length is 6 chars."
  }
}

variable "env_short" {
  description = "Environment shot version"
  validation {
    condition = (
      length(var.env_short) == 1
    )
    error_message = "Max length is 1 chars."
  }
  type = string
}

variable "env" {
  type        = string
  description = "Contains env description in extend format (dev,uat,prod)"
}




variable "external_domain" {
  type        = string
  default     = null
  description = "Domain for delegation"
}

variable "dns_zone_prefix" {
  type        = string
  default     = null
  description = "The dns subdomain."
}




## Database server postgresl
variable "ecommerce_ingress_hostname" {
  type        = string
  description = "ecommerce ingress hostname"
  default     = null
}

variable "create_wisp_converter" {
  type        = bool
  default     = false
  description = "CREATE WISP dismantling system infra"
}
