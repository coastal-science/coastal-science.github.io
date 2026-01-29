job "${__SERVICE__}-${__ENVIRONMENT__}" {
  datacenters = ${__DATACENTERS__}
  namespace = "${__NAMESPACE__}"

  constraint {
    attribute = "${meta.role}"
    operator  = "set_contains"
    value     = "non-data-portal"
  }
  
  constraint {
    attribute = "${meta.role}"
    operator  = "!="
    value     = "rcg-ingress"
  }

  #constraint {
  #  attribute = "${node.unique.name}"
  #  operator  = "="
  #  value     = "nomad-hallo-apps.novalocal"
  #}

  constraint {
    distinct_hosts = true
  }

  spread {
    attribute = "${node.unique.name}"
    weight    = 50
  }

  update {
    stagger      = "10s"
    max_parallel = 1
  }

  group "${__SERVICE__}-${__ENVIRONMENT__}" {
      count = 1

      scaling {
        enabled = true
        min     = 1
        max     = 10
      }

      network {
        port "http" {
          to = 80
        }
   }

    task "${__SERVICE__}-${__ENVIRONMENT__}" {
      driver = "${__JOB_DRIVER__}"
      config {
        image = "${__IMAGE_NAME__}:${__IMAGE_TAG__}"
        ports = ["http"]
        force_pull = true
        auth {
          username = "${__REGISTRY_USERNAME__}"
          password = "${__REGISTRY_PASSWORD__}"
        }
        volumes = [
          "local/server.conf:/etc/nginx/conf.d/server.conf:ro"
        ]
      }

      template {
        data = <<EOH
upstream site_upstream {
    # Using env for now. TODO: Lookup service with service discovery/service mesh.
    # server {{ env "NOMAD_ADDR_http" }};
    server {{ range nomadService "orca-dev" }}{{ .Address }}:{{ .Port }}{{ end }};
}
upstream cms_upstream {
    # Using env for now. TODO: Lookup service with service discovery/service mesh.
    # server {{ env "NOMAD_ADDR_decap_http" }};
}
EOH
        destination = "local/server.conf"
        change_mode = "restart"
      }

      env {
        # 
      }

    service {
      name = "${__SERVICE__}-${__ENVIRONMENT__}"
      port = "http"
      provider = "nomad"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.rcg-${__SERVICE__}-${__ENVIRONMENT__}.rule=Host(`${__WEB_URL__}`)",
        "traefik.http.routers.rcg-${__SERVICE__}-${__ENVIRONMENT__}-nossl.rule=Host(`${__WEB_URL__}`)",
        "traefik.http.routers.rcg-${__SERVICE__}-${__ENVIRONMENT__}.tls=true",
        "traefik.http.routers.rcg-${__SERVICE__}-${__ENVIRONMENT__}.entrypoints=websecure",
        
        "traefik.http.routers.researchcomputinggroup-${__SERVICE__}-${__ENVIRONMENT__}.rule=Host(`${__SERVICE__}-${__ENVIRONMENT__}.${__RESEARCHER__}.researchcomputinggroup.ca`)",
        "traefik.http.routers.researchcomputinggroup-${__SERVICE__}-${__ENVIRONMENT__}-nossl.rule=Host(`${__SERVICE__}-${__ENVIRONMENT__}.${__RESEARCHER__}.researchcomputinggroup.ca`)",
        "traefik.http.routers.researchcomputinggroup-${__SERVICE__}-${__ENVIRONMENT__}.tls=true",
        "traefik.http.routers.researchcomputinggroup-${__SERVICE__}-${__ENVIRONMENT__}.entrypoints=websecure",
      ]
    }

    resources {
      cpu = 500
      memory = 256
      }

    }
  }
}
