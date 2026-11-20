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

  # ---------------------------------------------------------------------------
  # Mapping tipo di risorsa Azure => configurazione Icinga
  #
  # resource_properties: proprietà della risorsa usata come address
  #
  # name: regex applicata a resource_properties, il primo match è il nome
  # dell'host Icinga (se assente si usa l'intero valore)
  #
  # icinga_name_from: "resource" per usare il nome della risorsa Azure come nome
  # dell'host Icinga (ha la precedenza su name)
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
  #
  # address_format: stringa di format() applicata a resource_properties (%s),
  # il risultato è l'address e l'http_vhost (se assente si usa il valore letto)
  #
  # bp_type: tipo mostrato nel titolo del tile del Business Process
  # ("<bp_type>: <nome>"), se assente il tipo Azure
  #
  # variants: per i tipi con più varianti (es. Cosmos DB NoSQL / for MongoDB),
  # variante della risorsa => configurazione che sovrascrive quella del tipo
  # (address_format, bp_type, host_command, host_vars, services). La variante è
  # la capability API della risorsa se presente (variant_capabilities, es.
  # EnableTable), altrimenti il kind; le risorse con una variante non elencata
  # usano la configurazione del tipo
  # ---------------------------------------------------------------------------

  namespace_commands_map = {
    # https sulla root: qualsiasi risposta va bene (4xx => WARNING => host UP),
    # tranne la pagina di Azure delle web app spente
    "Microsoft.Web/sites" = {
      resource_properties = "properties.defaultHostName"
      bp_type             = "App Service"
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
      bp_type             = "Front Door"
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
      bp_type             = "AKS"
      bearer_token_secret = "aks-icinga-token-"
      # l'FQDN contiene un suffisso generato da Azure: host col nome del cluster
      icinga_name_from = "resource"
      host_command     = "tcp"
      host_vars        = { tcp_port = "443" }
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
      bp_type             = "PostgreSQL"
      name                = "[^.]+"
      host_command        = "tcp"
      host_vars           = { tcp_port = "5432" }
      services = {
        # login + percentuale di max_connections usata dai client (esclusi i
        # processi interni); statement_timeout: il server interrompe la query
        # dopo 5s. Una connessione per check, chiusa a fine query
        "pgsql" = {
          check_command = "pgsql"
          vars = {
            pgsql_database       = "postgres"
            pgsql_username       = data.azurerm_key_vault_secret.metabase_usr.value
            pgsql_password       = data.azurerm_key_vault_secret.metabase_psw.value
            pgsql_options        = "options='-c statement_timeout=5000'"
            pgsql_query          = "SELECT round(count(*) * 100.0 / current_setting('max_connections')::int, 2) FROM pg_stat_activity WHERE backend_type = 'client backend'"
            pgsql_query_warning  = "80"
            pgsql_query_critical = "90"
          }
        }
      }
    }
    # Cosmos DB: NoSQL e for MongoDB (RU) hanno lo stesso tipo, cambia il kind
    # (GlobalDocumentDB / MongoDB); Table ha kind GlobalDocumentDB e capability
    # EnableTable. L'endpoint non è tra le proprietà: l'address si costruisce
    # dal nome dell'account
    "Microsoft.DocumentDB/databaseAccounts" = {
      resource_properties  = "name"
      bp_type              = "Cosmos DB"
      variant_capabilities = ["EnableTable", "EnableGremlin", "EnableCassandra"]
      variants = {
        # host UP se il gateway REST risponde 401 (senza autenticazione); 403 =
        # VM non ammessa dal firewall dell'account => DOWN. GET /dbs con un
        # token Entra della managed identity (cosmos_nosql, common), che ha solo
        # readMetadata sull'account (03_cosmos_rbac.tf)
        GlobalDocumentDB = {
          address_format = "%s.documents.azure.com"
          bp_type        = "Cosmos NoSQL"
          host_command   = "http"
          host_vars = {
            http_ssl    = "true"
            http_sni    = "true"
            http_uri    = "/"
            http_expect = "401"
          }
          services = {
            "nosql" = {
              check_command = "cosmos_nosql"
              vars = {
                cosmos_nosql_warning  = "500"
                cosmos_nosql_critical = "2000"
              }
            }
          }
        }
        # Table: stesso gateway e stesso host check del NoSQL, senza servizi
        # (i ruoli data-plane NoSQL non valgono per le API Table)
        EnableTable = {
          address_format = "%s.documents.azure.com"
          bp_type        = "Cosmos Table"
          host_command   = "http"
          host_vars = {
            http_ssl    = "true"
            http_sni    = "true"
            http_uri    = "/"
            http_expect = "401"
          }
        }
        # host UP se l'endpoint Mongo (wire protocol su TLS) completa
        # l'handshake TLS sulla 10255
        MongoDB = {
          address_format = "%s.mongo.cosmos.azure.com"
          bp_type        = "Cosmos Mongo"
          host_command   = "tcp"
          host_vars = {
            tcp_port = "10255"
            tcp_ssl  = "true"
          }
          services = {
            # ping + listDatabases con la read-only key, letta da ARM dal plugin
            # con la managed identity della VM (cosmos_mongo, common); soglie in
            # ms sul tempo della query (listDatabases), connect solo in perfdata
            "mongo" = {
              check_command = "cosmos_mongo"
              vars = {
                cosmos_mongo_warning  = "500"
                cosmos_mongo_critical = "2000"
              }
            }
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

  # variante della risorsa: la prima capability tra le variant_capabilities del
  # tipo, altrimenti il kind (null se assente)
  resource_variants = {
    for k, v in local.resource_names_flat : k => try(
      [
        for c in local.namespace_commands_map[v.type].variant_capabilities : c
        if contains(coalesce(data.azapi_resource.this[k].output.capabilities, []), c)
      ][0],
      data.azapi_resource.this[k].output.kind
    )
  }

  # configurazione Icinga della risorsa: quella del tipo, sovrascritta dalla
  # variante se presente (variants)
  resource_configs = {
    for k, v in local.resource_names_flat : k => merge(
      local.namespace_commands_map[v.type],
      try(local.namespace_commands_map[v.type].variants[local.resource_variants[k]], {})
    )
  }

  # risorsa arricchita con la configurazione Icinga e l'address letto da Azure
  resources_full = {
    for k, v in local.resource_names_flat : k => merge(v, {
      kind         = data.azapi_resource.this[k].output.kind
      variant      = local.resource_variants[k]
      bp_type      = try(local.resource_configs[k].bp_type, v.type)
      host_command = try(local.resource_configs[k].host_command, "hostalive")
      host_vars    = try(local.resource_configs[k].host_vars, {})
      services     = try(local.resource_configs[k].services, {})
      # "" se il tipo non usa token
      bearer_token_secret = try("${local.resource_configs[k].bearer_token_secret}${v.name}", "")
      # valore letto da Azure, formattato con address_format se presente
      property_value = try(
        format(local.resource_configs[k].address_format, data.azapi_resource.this[k].output.value),
        data.azapi_resource.this[k].output.value
      )
      # per i custom domain l'endpoint AFD, altrimenti il valore letto da Azure
      address = try(
        local.afd_custom_domain_endpoints[lower(v.id)][0],
        format(local.resource_configs[k].address_format, data.azapi_resource.this[k].output.value),
        data.azapi_resource.this[k].output.value
      )
      icinga_name = (
        try(local.resource_configs[k].icinga_name_from, "") == "resource" ? v.name : try(
          regex(local.resource_configs[k].name, data.azapi_resource.this[k].output.value),
          data.azapi_resource.this[k].output.value
        )
      )
    })
    if !can(regex(local.resource_configs[k].exclude, data.azapi_resource.this[k].output.value))
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
  # Business Process Icinga: <bp_name> > dominio > host / namespace > check
  # ---------------------------------------------------------------------------
  # titolo mostrato in Icinga Web; bp_name (nome del file e del run command)
  # ammette solo alfanumerici, punti, trattini e underscore
  bp_title    = "pagoPa Platform"
  bp_sanitize = "/[^A-Za-z0-9_.-]/"
  bp_name     = replace(local.bp_title, local.bp_sanitize, "_")
  bp_dir      = "/etc/icingaweb2/modules/businessprocess/processes"
  bp_file     = "${local.bp_dir}/${local.bp_name}.conf"

  # Titoli dei nodi "<tipo><a capo><nome>": l'a capo è U+2028 (LINE SEPARATOR),
  # il file del Business Process separa le righe solo su "\n". Il browser lo
  # mostrerebbe come spazio, il modulo pagopa (common, theme/files/public/js)
  # lo trasforma in <br>
  bp_title_break = "\u2028"

  # namespace => nodo con il solo check del namespace e un titolo leggibile
  # ("AKS" a capo "aca on WEU"): il provider icinga2 non gestisce display_name e
  # Icinga Web mostrerebbe "<servizio> on <host>"
  bp_namespaces = {
    for k, s in local.aks_namespace_services :
    replace("k8s_${k}", local.bp_sanitize, "_") => {
      title  = "AKS${local.bp_title_break}${s.vars.k8s_namespace} on ${upper(regex("^([a-z0-9]+)-namespace-", k)[0])}"
      domain = replace(s.domain, local.bp_sanitize, "_")
      check  = "${local.resources_full[s.host_key].icinga_name};${s.name}"
    }
  }

  # host => titolo ("<bp_type>" a capo "<nome>"), dominio e check ("<host>;Hoststatus"
  # e "<host>;<servizio>")
  bp_hosts = {
    for k, v in local.resources_full :
    replace(v.icinga_name, local.bp_sanitize, "_") => {
      title  = "${v.bp_type}${local.bp_title_break}${v.icinga_name}"
      domain = replace(v.domain, local.bp_sanitize, "_")
      checks = concat(
        ["${v.icinga_name};Hoststatus"],
        [for s in local.services_flat : "${v.icinga_name};${s.name}" if s.host_key == k]
      )
    } if v.property_value != null
  }

  # dominio => host e namespace AKS del dominio (su tutti i cluster)
  bp_domains = {
    for x in concat(
      [for node, h in local.bp_hosts : { domain = h.domain, node = node }],
      [for node, n in local.bp_namespaces : { domain = n.domain, node = node }]
    ) : x.domain => x.node...
  }

  # contenuto del file .conf caricato su Icinga Web 2
  bp_content = templatefile("${path.module}/templates/business_process.conf.tftpl", {
    title      = local.bp_title
    hosts      = local.bp_hosts
    namespaces = local.bp_namespaces
    domains    = local.bp_domains
  })
}
