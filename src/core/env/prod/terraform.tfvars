# general
env_short = "p"
env       = "prod"
enabled_features = {
  vnet_ita = false
}


# main vnet

# common

# specific
external_domain = "pagopa.it"
dns_zone_prefix = "platform"


# todo change to Premium before launch
# redis_sku_name = "Premium"
# redis_family   = "P"

# postgresql
postgres_private_endpoint_enabled = false

# ecommerce ingress hostname
ecommerce_ingress_hostname = "weuprod.ecommerce.internal.platform.pagopa.it"

# WISP-dismantling-cfg
create_wisp_converter = true
