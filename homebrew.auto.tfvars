# Homebrew packages deployed via Jamf Self Service.
# icon_url: official-logo PNG (homarr-labs/dashboard-icons via jsDelivr CDN).
#   CLIs/libraries without a brand logo in the set use a generic terminal icon.
homebrew_packages = {
  atlas = {
    formula        = "mongodb-atlas-cli"
    display_name   = "MongoDB Atlas CLI"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/mongodb.png"
    enabled        = true
    smart_group_id = 0
  }
  auth0_cli = {
    formula        = "auth0/auth0-cli/auth0"
    display_name   = "Auth0 CLI"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/okta.png"
    enabled        = true
    smart_group_id = 0
  }
  awscli = {
    formula        = "awscli"
    display_name   = "AWS CLI"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/aws.png"
    enabled        = true
    smart_group_id = 0
  }
  bria = {
    formula        = "bria"
    display_name   = "Bria"
    tap            = ""
    cask           = true
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/terminal.png"
    enabled        = true
    smart_group_id = 0
  }
  buf = {
    formula        = "buf"
    display_name   = "Buf CLI"
    tap            = "bufbuild/buf"
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/terminal.png"
    enabled        = true
    smart_group_id = 0
  }
  bun = {
    formula        = "bun"
    display_name   = "Bun JavaScript Runtime"
    tap            = "oven-sh/bun"
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/terminal.png"
    enabled        = true
    smart_group_id = 0
  }
  cairo = {
    formula        = "cairo"
    display_name   = "Cairo Graphics Library"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/terminal.png"
    enabled        = true
    smart_group_id = 0
  }
  clickhouse = {
    formula        = "clickhouse"
    display_name   = "ClickHouse CLI"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/clickhouse.png"
    enabled        = true
    smart_group_id = 0
  }
  cmctl = {
    formula        = "cmctl"
    display_name   = "cert-manager CLI"
    tap            = "jetstack/tap"
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/cert-manager.png"
    enabled        = true
    smart_group_id = 0
  }
  cloud_sql_proxy = {
    formula        = "cloud-sql-proxy"
    display_name   = "Google Cloud SQL Proxy"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/google-cloud-platform.png"
    enabled        = true
    smart_group_id = 0
  }
  dbmate = {
    formula        = "dbmate"
    display_name   = "Dbmate Database Migrations"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/terminal.png"
    enabled        = true
    smart_group_id = 0
  }
  dlv = {
    formula        = "delve"
    display_name   = "Delve Go Debugger"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/go.png"
    enabled        = true
    smart_group_id = 0
  }
  docker_credential_gcloud = {
    formula      = "docker-credential-gcloud"
    display_name = "Docker Credential Helper for GCloud"
    tap          = ""
    icon_url     = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/docker.png"
    # DISABLED 2026-08-24 (daily compliance): "docker-credential-gcloud" is not a
    # Homebrew formula (brew formula API 404) and has no tap — every install/
    # remediation run fails fleet-wide. The binary ships inside the Google Cloud
    # CLI, which is already deployed via the "Install Google Cloud CLI" policy,
    # so this package is redundant. Re-enable only if a real formula exists.
    enabled        = false
    smart_group_id = 0
  }
  glib = {
    formula        = "glib"
    display_name   = "GLib Core Library"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/terminal.png"
    enabled        = true
    smart_group_id = 0
  }
  go = {
    formula        = "go"
    display_name   = "Go Programming Language"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/go.png"
    enabled        = true
    smart_group_id = 0
  }
  golangci_lint = {
    formula        = "golangci-lint"
    display_name   = "Go Linters Runner"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/go.png"
    enabled        = true
    smart_group_id = 0
  }
  gomplate = {
    formula        = "gomplate"
    display_name   = "Gomplate Template Renderer"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/go.png"
    enabled        = true
    smart_group_id = 0
  }
  grpcurl = {
    formula        = "grpcurl"
    display_name   = "gRPCurl CLI"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/terminal.png"
    enabled        = true
    smart_group_id = 0
  }
  haproxy = {
    formula        = "haproxy"
    display_name   = "HAProxy Load Balancer"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/haproxy.png"
    enabled        = true
    smart_group_id = 0
  }
  helm = {
    formula        = "helm"
    display_name   = "Helm Kubernetes Package Manager"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/helm.png"
    enabled        = true
    smart_group_id = 0
  }
  helmfile = {
    formula        = "helmfile"
    display_name   = "Helmfile Declarative Helm"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/helm.png"
    enabled        = true
    smart_group_id = 0
  }
  gh = {
    formula        = "gh"
    display_name   = "GitHub CLI"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/github.png"
    enabled        = true
    smart_group_id = 0
  }
  jira = {
    formula        = "jira-cli"
    display_name   = "Jira CLI"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/atlassian-jira.png"
    enabled        = true
    smart_group_id = 0
  }
  k6 = {
    formula        = "k6"
    display_name   = "k6 Load Testing"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/grafana.png"
    enabled        = true
    smart_group_id = 0
  }
  kube_ps1 = {
    formula        = "kube-ps1"
    display_name   = "Kubernetes PS1 Prompt"
    tap            = "jonmosco/kube-ps1"
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/kubernetes.png"
    enabled        = true
    smart_group_id = 0
  }
  kubectl = {
    formula        = "kubectl"
    display_name   = "Kubernetes CLI"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/kubernetes.png"
    enabled        = true
    smart_group_id = 0
  }
  kubectx = {
    formula        = "kubectx"
    display_name   = "Kubectx Context Switcher"
    tap            = "ahmetb/kubectx"
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/kubernetes.png"
    enabled        = true
    smart_group_id = 0
  }
  kubens = {
    formula      = "kubens"
    display_name = "Kubens Namespace Switcher"
    tap          = "ahmetb/kubectx"
    icon_url     = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/kubernetes.png"
    # DISABLED 2026-08-24 (daily compliance): the "ahmetb/kubectx" tap no longer
    # exists (GitHub 404) and there is no standalone "kubens" formula — the
    # kubens binary is built and installed by the core "kubectx" formula
    # (see homebrew-core kubectx.rb: output: bin/"kubens"). The "kubectx"
    # package above already deploys it, so this entry is redundant and always
    # fails. Re-enable only if kubens becomes independently installable.
    enabled        = false
    smart_group_id = 0
  }
  kustomize = {
    formula        = "kustomize"
    display_name   = "Kustomize Kubernetes Config"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/kubernetes.png"
    enabled        = true
    smart_group_id = 0
  }
  libpq = {
    formula        = "libpq"
    display_name   = "PostgreSQL Client (psql)"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/postgresql.png"
    enabled        = true
    smart_group_id = 0
  }
  micromamba = {
    formula        = "micromamba"
    display_name   = "Micromamba Package Manager"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/python.png"
    enabled        = true
    smart_group_id = 0
  }
  mongosh = {
    formula        = "mongosh"
    display_name   = "MongoDB Shell"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/mongodb.png"
    enabled        = true
    smart_group_id = 0
  }
  pango = {
    formula        = "pango"
    display_name   = "Pango Text Layout Library"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/terminal.png"
    enabled        = true
    smart_group_id = 0
  }
  neovim = {
    formula        = "neovim"
    display_name   = "Neovim"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/terminal.png"
    enabled        = true
    smart_group_id = 0
  }
  node = {
    formula        = "node"
    display_name   = "Node.js"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/nodejs.png"
    enabled        = true
    smart_group_id = 0
  }
  nvm = {
    formula        = "nvm"
    display_name   = "Node Version Manager"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/nodejs.png"
    enabled        = true
    smart_group_id = 0
  }
  rpk = {
    formula        = "redpanda"
    display_name   = "Redpanda CLI (rpk)"
    tap            = "redpanda-data/tap"
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/terminal.png"
    enabled        = true
    smart_group_id = 0
  }
  rust = {
    formula        = "rust"
    display_name   = "Rust Programming Language"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/rust.png"
    enabled        = true
    smart_group_id = 0
  }
  rustup = {
    formula        = "rustup"
    display_name   = "Rust Toolchain Installer"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/rust.png"
    enabled        = true
    smart_group_id = 0
  }
  socat = {
    formula        = "socat"
    display_name   = "Socat Network Utility"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/terminal.png"
    enabled        = true
    smart_group_id = 0
  }
  stunnel = {
    formula        = "stunnel"
    display_name   = "Stunnel"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/terminal.png"
    enabled        = true
    smart_group_id = 0
  }
  thanos = {
    formula        = "thanos"
    display_name   = "Thanos CLI"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/thanos.png"
    enabled        = true
    smart_group_id = 0
  }
  tofu = {
    formula        = "opentofu"
    display_name   = "OpenTofu IaC"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/opentofu.png"
    enabled        = true
    smart_group_id = 0
  }
  uv = {
    formula        = "uv"
    display_name   = "UV Python Package Manager"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/astral.png"
    enabled        = true
    smart_group_id = 0
  }
  weasyprint = {
    formula        = "weasyprint"
    display_name   = "Weasy Print"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/python.png"
    enabled        = true
    smart_group_id = 0
  }
  yarn = {
    formula        = "yarn"
    display_name   = "Yarn Package Manager"
    tap            = ""
    icon_url       = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/terminal.png"
    enabled        = true
    smart_group_id = 0
  }
}
