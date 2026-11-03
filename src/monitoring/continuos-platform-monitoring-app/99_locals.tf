locals {
  # ---------------------------------------------------------------------------
  # General
  # ---------------------------------------------------------------------------
  prefix                             = "pagopa"
  domain                             = "cpm"
  product                            = "${local.prefix}-${var.env_short}"
  project                            = "${local.product}-${var.location_short}-${local.domain}"
  core_key_vault_name                = "${local.product}-${var.location_short}-core-kv"
  core_key_vault_resource_group_name = "${local.product}-${var.location_short}-core-sec-rg"

  kv_domain_name = "${local.project}-kv"
  kv_domain_rg   = "${local.project}-sec-rg"

  application_owners = [
    "matteo.alongi@pagopa.it",
    "marco.mari@pagopa.it",
    "umberto.coppolabottazzi@pagopa.it",
    "fabio.felici@pagopa.it"
  ]
  # ---------------------------------------------------------------------------
  # Mapping tipo di risorsa Azure => configurazione Icinga
  #
  # resource_properties: proprietà della risorsa usata come address
  #
  # name: regex applicata a resource_properties, il primo match è il nome
  # dell'host Icinga (se assente si usa l'intero valore)
  #
  # parent_type: per le risorse figlie non elencabili direttamente (es. custom
  # domain), tipo del padre da cui leggerle; il dominio è quello del padre
  #
  # exclude: regex applicata a resource_properties, le risorse che fanno match
  # non vengono monitorate
  #
  # bearer_token_secret: prefisso del segreto (kv di dominio) con il token Bearer
  # dei servizi, il nome completo è <prefisso><nome risorsa>; le risorse senza
  # segreto hanno solo l'host
  # ---------------------------------------------------------------------------

  namespace_commands_map = {
    # https sulla root: qualsiasi risposta va bene (4xx => WARNING => host UP),
    # tranne la pagina di Azure delle web app spente
    "Microsoft.Web/sites" = {
      resource_properties = "properties.defaultHostName"
      host_command        = "http"
      host_vars = {
        http_ssl               = "true"
        http_sni               = "true"
        http_expect_body_regex = "This web app is stopped"
        http_invertregex       = "true"
      }
    }
    # address = endpoint AFD che serve il dominio, http_vhost = dominio custom:
    # evita la risoluzione del dominio custom dalla zona DNS privata
    "Microsoft.Cdn/profiles/customdomains" = {
      parent_type         = "Microsoft.Cdn/profiles"
      resource_properties = "properties.hostName"
      exclude             = "\\.azureedge\\.net$" # domini residui della migrazione dal CDN classico
      host_command        = "http"
      host_vars = {
        http_ssl = "true",
        http_sni = "true"
      }
      services = {
        "certificate" = {
          check_command = "http"
          vars = {
            # giorni alla scadenza: WARNING sotto 30, CRITICAL sotto 10 (o già scaduto)
            http_certificate = "30,15"
          }
        }
      }
    }
    # API server AKS: FQDN privato se il cluster è privato, altrimenti quello
    # pubblico (query JMESPath); host UP se la 443 risponde. readyz/livez con il
    # token del ServiceAccount icinga (continuos-platform-monitoring-common)
    "Microsoft.ContainerService/managedClusters" = {
      resource_properties = "properties.privateFQDN || properties.fqdn"
      bearer_token_secret = "aks-icinga-token-"
      name                = "[^.]+"
      host_command        = "tcp"
      host_vars           = { tcp_port = "443" }
      services = {
        "readyz" = {
          check_command = "http"
          vars = {
            http_ssl           = "true"
            http_sni           = "true"
            http_uri           = "/readyz"
            http_expect        = "200"
            http_warn_time     = "1"
            http_critical_time = "5"
          }
        }
        "livez" = {
          check_command = "http"
          vars = {
            http_ssl    = "true"
            http_sni    = "true"
            http_uri    = "/livez"
            http_expect = "200"
          }
        }
      }
    }
    "Microsoft.DBforPostgreSQL/flexibleServers" = {
      resource_properties = "properties.fullyQualifiedDomainName"
      name                = "[^.]+"
      host_command        = "tcp"
      host_vars           = { tcp_port = "5432" }
      services = {
        "pgsql" = {
          check_command = "pgsql"
          vars = {
            pgsql_database = "postgres"
            pgsql_username = data.azurerm_key_vault_secret.metabase_usr.value
            pgsql_password = data.azurerm_key_vault_secret.metabase_psw.value
          }
        }
      }
    }
  }

  # ---------------------------------------------------------------------------
  # API version per tipo di risorsa
  # ---------------------------------------------------------------------------

  # segreti con i token Bearer presenti nel kv di dominio
  bearer_token_prefixes = [
    for v in local.namespace_commands_map : v.bearer_token_secret if can(v.bearer_token_secret)
  ]
  bearer_token_secrets = toset([
    for n in data.azurerm_key_vault_secrets.kv_domain.names : n
    if anytrue([for p in local.bearer_token_prefixes : startswith(n, p)])
  ])

  # tipo => tutte le api version disponibili (es. ["2024-05-01", "2024-03-01", ...])
  api_versions = {
    for k in keys(local.namespace_commands_map) : k => flatten([
      for rt in data.azapi_resource_action.provider[split("/", k)[0]].output.resourceTypes :
      rt.apiVersions
      if lower(rt.resourceType) == lower(trimprefix(k, "${split("/", k)[0]}/"))
    ])
  }

  # tipo => ultima api version stabile (esclude le preview)
  latest_stable = {
    for k, v in local.api_versions : k => reverse(sort([for x in v : x if !strcontains(x, "preview")]))[0]
  }

  # ---------------------------------------------------------------------------
  # Risorse Azure da monitorare
  # ---------------------------------------------------------------------------

  # "<tipo>-<padre>" => risorsa padre da cui leggere le figlie (solo tipi con parent_type)
  parent_resources = merge([
    for k, v in local.namespace_commands_map : {
      for r in data.azurerm_resources.sub_resources[k].resources : "${k}-${r.name}" => {
        type      = k
        parent_id = r.id
        name      = r.name
        domain    = try(r.tags.domain, "notag")
      }
    } if can(v.parent_type)
  ]...)

  # "<tipo>-<nome>" => risorsa Azure (salta i tipi non mappati)
  resource_names_flat = merge(concat(
    [
      for k, v in data.azurerm_resources.sub_resources : {
        for r in v.resources : "${k}-${r.name}" => {
          name   = r.name
          type   = r.type
          id     = r.id
          domain = try(r.tags.domain, "notag")
        }
        if contains(keys(local.namespace_commands_map), r.type)
      }
    ],
    [
      for pk, p in local.parent_resources : {
        for c in data.azapi_resource_list.children[pk].output.value : "${p.type}-${p.name}/${c.name}" => {
          name   = "${p.name}/${c.name}"
          type   = p.type
          id     = c.id
          domain = p.domain
        }
      }
    ]
  )...)

  # ---------------------------------------------------------------------------
  # Front Door: custom domain => endpoint AFD che lo serve (via route)
  # ---------------------------------------------------------------------------

  # "<tipo>-<profilo>" => profilo Front Door con custom domain
  afd_profiles = {
    for k, p in local.parent_resources : k => p if p.type == "Microsoft.Cdn/profiles/customdomains"
  }

  # id endpoint (lowercase) => hostname *.azurefd.net
  afd_endpoints = merge([
    for k, p in local.afd_profiles : {
      for e in data.azapi_resource_list.afd_endpoints[k].output.value : lower(e.id) => e.properties.hostName
    }
  ]...)

  # id custom domain (lowercase) => hostname degli endpoint che lo servono
  afd_custom_domain_endpoints = {
    for x in flatten([
      for eid, routes in data.azapi_resource_list.afd_routes : [
        for r in routes.output.value : [
          for cd in r.properties.customDomains : { cd = lower(cd.id), host = local.afd_endpoints[eid] }
        ]
      ]
    ]) : x.cd => x.host...
  }

  # risorsa arricchita con la configurazione Icinga e l'address letto da Azure
  resources_full = {
    for k, v in local.resource_names_flat : k => merge(v, {
      host_command = try(local.namespace_commands_map[v.type].host_command, "hostalive")
      host_vars    = try(local.namespace_commands_map[v.type].host_vars, {})
      services     = try(local.namespace_commands_map[v.type].services, {})
      # "" se il tipo non usa token
      bearer_token_secret = try("${local.namespace_commands_map[v.type].bearer_token_secret}${v.name}", "")
      property_value      = data.azapi_resource.this[k].output.value
      # per i custom domain l'endpoint AFD, altrimenti il valore letto da Azure
      address = try(local.afd_custom_domain_endpoints[lower(v.id)][0], data.azapi_resource.this[k].output.value)
      icinga_name = try(
        regex(local.namespace_commands_map[v.type].name, data.azapi_resource.this[k].output.value),
        data.azapi_resource.this[k].output.value
      )
    })
    if !can(regex(local.namespace_commands_map[v.type].exclude, data.azapi_resource.this[k].output.value))
  }

  # ---------------------------------------------------------------------------
  # Oggetti Icinga (host e servizi)
  # ---------------------------------------------------------------------------

  # un host Icinga per ogni risorsa
  hosts_flat = {
    for k, r in local.resources_full : k => {
      hostname      = r.icinga_name
      address       = r.address
      check_command = r.host_command
      vars = merge(r.host_vars, {
        http_vhost = r.property_value
        domain     = r.domain
        azure_type = r.type
        azure_id   = r.id
      })
    }
  }

  # un servizio Icinga per ogni coppia (risorsa, servizio)
  services_flat = merge([
    for k, r in local.resources_full : {
      for svc_name, svc in r.services : "${k}-${svc_name}" => {
        host_key      = k
        name          = svc_name
        check_command = svc.check_command
        vars = merge(try(svc.vars, {}), r.bearer_token_secret == "" ? {} : {
          http_header = "Authorization: Bearer ${data.azurerm_key_vault_secret.bearer_tokens[r.bearer_token_secret].value}"
        })
      }
    }
    # senza token i servizi fallirebbero con 401
    if r.bearer_token_secret == "" || contains(local.bearer_token_secrets, r.bearer_token_secret)
  ]...)

  # ---------------------------------------------------------------------------
  # Kubernetes: un servizio per namespace sull'host del cluster AKS, con lo stato
  # dei workload letto da Icinga for Kubernetes (check_k8s_namespace, common)
  # ---------------------------------------------------------------------------

  # cluster AKS, stessa naming di aks-platform (<product>-<location>-<env>-aks);
  # per ognuno un provider kubernetes.<chiave> (99_main.tf) con il kubeconfig in
  # <prefix>/config-<nome>
  aks_clusters = {
    for i in ["itn", "weu"] : i => {
      name             = "${local.product}-${i}-${var.env}-aks"
      kube_config_path = "${var.k8s_kube_config_path_prefix}/config-${local.product}-${i}-${var.env}-aks"
      # host Icinga del cluster (chiave di local.resources_full)
      host_key = "Microsoft.ContainerService/managedClusters-${local.product}-${i}-${var.env}-aks"
    }
  }

  # chiave di local.aks_clusters => namespace del cluster (04_aks_namespaces.tf)
  aks_namespaces = {
    itn = data.kubernetes_resources.namespaces_itn.objects
    weu = data.kubernetes_resources.namespaces_weu.objects
  }

  # "<cluster>-namespace-<ns>" => servizio sull'host Icinga del cluster, solo per
  # i namespace con la label "domain" (nodo del Business Process)
  aks_namespace_services = merge([
    for k, c in local.aks_clusters : {
      for ns in local.aks_namespaces[k] : "${k}-namespace-${ns.metadata.name}" => {
        host_key      = c.host_key
        name          = "namespace-${ns.metadata.name}"
        domain        = ns.metadata.labels.domain
        check_command = "k8s_namespace"
        vars = {
          k8s_cluster   = c.name
          k8s_namespace = ns.metadata.name
          domain        = ns.metadata.labels.domain
        }
      }
      if try(ns.metadata.labels.domain, "") != ""
    }
  ]...)

  # ---------------------------------------------------------------------------
  # Business Process Icinga: <bp_name> > dominio > host > check
  # ---------------------------------------------------------------------------
  bp_name     = "Terraform"
  bp_dir      = "/etc/icingaweb2/modules/businessprocess/processes"
  bp_file     = "${local.bp_dir}/${local.bp_name}.conf"
  bp_sanitize = "/[^A-Za-z0-9_.-]/"

  # tema della vista a tile
  bp_theme      = file("${path.module}/templates/bp-tiles.less")
  bp_theme_dir  = "/usr/share/icingaweb2/public/css/themes"
  bp_theme_file = "${local.bp_theme_dir}/bp-tiles.less"

  # host => dominio + check ("<host>;Hoststatus" e "<host>;<servizio>"), più un
  # nodo k8s_<dominio> con i check dei namespace del dominio su tutti i cluster
  bp_hosts = merge(
    {
      for k, v in local.resources_full :
      replace(v.icinga_name, local.bp_sanitize, "_") => {
        domain = replace(v.domain, local.bp_sanitize, "_")
        checks = concat(
          ["${v.icinga_name};Hoststatus"],
          [for s in local.services_flat : "${v.icinga_name};${s.name}" if s.host_key == k]
        )
      } if v.property_value != null
    },
    {
      for domain, checks in {
        for s in local.aks_namespace_services : s.domain => "${local.resources_full[s.host_key].icinga_name};${s.name}"...
      } :
      "k8s_${replace(domain, local.bp_sanitize, "_")}" => {
        domain = replace(domain, local.bp_sanitize, "_")
        checks = checks
      }
    }
  )

  # dominio => lista degli host
  bp_domains = {
    for node, h in local.bp_hosts : h.domain => node...
  }

  # contenuto del file .conf caricato su Icinga Web 2
  bp_content = templatefile("${path.module}/templates/business_process.conf.tftpl", {
    title   = local.bp_name
    hosts   = local.bp_hosts
    domains = local.bp_domains
  })
}
