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


#
# Feature Flag
#
variable "enabled_features" {
  type = object({
    vnet_ita = bool
  })
  default = {
    vnet_ita = false
  }
  description = "Features enabled in this domain"
}


# DNS
variable "dns_default_ttl_sec" {
  type        = number
  description = "value"
  default     = 3600
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



variable "postgres_private_endpoint_enabled" {
  type        = bool
  default     = false
  description = "Private endpoint database enable?"
}

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
