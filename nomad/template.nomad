job "${__SERVICE__}-${__ENVIRONMENT__}" {
  meta {
    run_uuid = "${uuidv4()}"
  }

  type        = "service"
  datacenters = ${__DATACENTERS__}
  namespace   = "${__NAMESPACE__}"

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

  constraint {
    distinct_hosts = true
  }

  spread {
    attribute = "${node.unique.name}"
    weight    = 50
  }

  # Rolling updates: health_check=checks gates deploy on Nomad service checks below.
  # count>=2 (production) keeps one allocation healthy while another updates.
  update {
    max_parallel      = 1
    stagger           = "10s"
    health_check      = "checks"
    min_healthy_time  = "10s"
    healthy_deadline  = "5m"
    progress_deadline = "10m"
    auto_revert       = true
    auto_promote      = false
    canary            = 0
  }

  group "${__SERVICE__}-${__ENVIRONMENT__}" {
    count = ${__GROUP_COUNT__}

    scaling {
      enabled = true
      min     = ${__GROUP_COUNT__}
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
        image              = "${__IMAGE_NAME__}:${__IMAGE_TAG__}"
        image_pull_timeout = "10m"
        ports              = ["http"]
        force_pull         = true
        auth {
          username = "${__REGISTRY_USERNAME__}"
          password = "${__REGISTRY_PASSWORD__}"
        }
        volumes = [
          "local/server.conf:/etc/nginx/conf.d/server.conf:ro"
        ]
        healthchecks {
          disable = true
        }
      }

      template {
        data = <<EOH
upstream site_upstream {
    # Using env for now. TODO: Lookup service with service discovery/service mesh.
    server {{ env "NOMAD_ADDR_http" }};
}
upstream cms_upstream {
    # Using env for now. TODO: Lookup service with service discovery/service mesh.
    # server {{ env "NOMAD_ADDR_decap_api" }};
    
    # TODO: Temporarily reusing site_upstream since decap_api is not deployed yet.
    server {{ env "NOMAD_ADDR_http" }};
}
EOH
        destination = "local/server.conf"
        change_mode = "restart"
      }

      env {
        # true = Decap CMS (decap.conf + server.conf); false = static only (default.conf)
        USE_DECAP = "${__USE_DECAP__}"
      }

      restart {
        attempts = 3
        interval = "5m"
        delay    = "15s"
        mode     = "fail"
      }

      service {
        name     = "${__SERVICE__}-${__ENVIRONMENT__}"
        port     = "http"
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

        check {
          type     = "http"
          path     = "/"
          interval = "10s"
          timeout  = "2s"
        }
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}
