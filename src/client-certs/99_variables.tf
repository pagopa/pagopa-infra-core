variable "prefix" {
  type = string
  validation {
    condition = (
      length(var.prefix) <= 6
    )
    error_message = "Max length is 6 chars."
  }
}

variable "env" {
  type = string
}

variable "env_short" {
  type = string
  validation {
    condition = (
      length(var.env_short) == 1
    )
    error_message = "Length must be 1 chars."
  }
}

variable "domain" {
  type = string
  validation {
    condition = (
      length(var.domain) <= 12
    )
    error_message = "Max length is 12 chars."
  }
}

variable "location_short" {
  type = string
  validation {
    condition = (
      length(var.location_short) == 3
    )
    error_message = "Length must be 3 chars."
  }
  description = "One of wue, neu"
}

variable "enabled_forwarder_certificates" {
  type    = bool
  default = false
}

variable "stable_promotion_ids" {
  type        = map(string)
  default     = {}
  description = "Promotion ids by certificate name, passed by pipelines at apply time (e.g. -var 'stable_promotion_ids={\"my-cert\":\"<build id>\"}'): a certificate (<name>-pfx) is promoted to its stable secrets (<name>-stable-*) when its id changes. Runs omitting it never promote: the first deploy of a certificate must list it, otherwise no -stable-* secret is created."

  validation {
    condition     = alltrue([for id in values(var.stable_promotion_ids) : can(regex("^[A-Za-z0-9._-]+$", id))])
    error_message = "stable_promotion_ids values must be non-empty strings of letters, digits, '-'."
  }
}