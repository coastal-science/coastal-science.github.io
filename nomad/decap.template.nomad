# Job template: site + Decap CMS in one group (same allocation, shared network).
# Parameterize with __SERVICE__, __ENVIRONMENT__, __USE_DECAP__, __IMAGE_*__, __REGISTRY_*__,
# and Decap-specific: __DECAP_IMAGE_NAME__, __DECAP_IMAGE_TAG__, __ORIGINS__, __OAUTH_CLIENT_ID__, __OAUTH_CLIENT_SECRET__, __CMS_BACKEND_DEBUG__ (optional).
job "${__SERVICE__}-${__ENVIRONMENT__}" {
  meta {
    run_uuid = "${uuidv4()}"
  }

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
      port "decap-http" {
        to = 80
      }
      port "decap-api" {
        to = 3000
      }
    }

    # Site task (nginx + Hugo); server.conf proxies /auth, /callback to decap-cms in same group
    task "${__SERVICE__}-${__ENVIRONMENT__}" {
      driver = "${__JOB_DRIVER__}"
      config {
        image = "${__IMAGE_NAME__}:${__IMAGE_TAG__}"
        image_pull_timeout = "10m"
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
    server {{ env "NOMAD_ADDR_http" }};
}
upstream cms_upstream {
    server {{ env "NOMAD_ADDR_decap_api" }};
}
EOH
        destination = "local/server.conf"
        change_mode = "restart"
      }

      env {
        # true = Decap CMS (decap.conf + server.conf); false = static only (default.conf)
        USE_DECAP = "${__USE_DECAP__}"
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
        cpu    = 500
        memory = 256
      }
    }

    # Decap CMS task (same group: site nginx reaches decap via NOMAD_ADDR_decap_api)
    task "decap-cms" {
      driver = "docker"
      config {
        image = "${__DECAP_IMAGE_NAME__}:${__DECAP_IMAGE_TAG__}"
        ports = ["decap-http", "decap-api"]
      }

      env {
        CMS_BACKEND_DEBUG = "${__CMS_BACKEND_DEBUG__}"
        ORIGINS           = "${__ORIGINS__}"
        OAUTH_CLIENT_ID   = "${__OAUTH_CLIENT_ID__}"
        OAUTH_CLIENT_SECRET = "${__OAUTH_CLIENT_SECRET__}"
      }

      service {
        name = "${__SERVICE__}-${__ENVIRONMENT__}-decap-cms"
        port = "decap-http"
        provider = "nomad"
        tags = [
          "traefik.enable=true",
        ]
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}
