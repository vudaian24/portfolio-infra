variable "parameter_names" {
  description = "Names of the SecureString parameters under path_prefix. Values are set out of band with the AWS CLI."
  type        = set(string)

  validation {
    condition     = alltrue([for name in var.parameter_names : can(regex("^[a-z0-9-]+$", name))])
    error_message = "Parameter names may contain only lowercase letters, digits and hyphens."
  }
}

variable "path_prefix" {
  description = "SSM path prefix of the parameters, e.g. /portfolio/prod."
  type        = string

  validation {
    condition     = can(regex("^/[a-z0-9/-]+[a-z0-9]$", var.path_prefix))
    error_message = "path_prefix must start with / and contain only lowercase letters, digits, hyphens and slashes."
  }
}
