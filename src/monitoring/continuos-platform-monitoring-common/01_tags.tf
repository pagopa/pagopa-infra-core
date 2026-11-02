module "tag_config" {
  source      = "../../tag_config"
  domain      = "core" # Must stay core because are used for cost tracking
  environment = var.env
}
