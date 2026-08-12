#!/usr/bin/env bash
set -Eeuo pipefail

die() {
  printf 'bootstrap: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage: bootstrap-debian.sh --runtime-root /opt/mmgo --server-name example.com

Installs Docker Engine from Docker's official Debian repository, creates the
MMGO runtime directories, installs non-secret Compose/env templates, and adds
a separate nginx site when the hostname is not already managed. Existing MMGO
configuration is never overwritten.
USAGE
}

runtime_root=""
server_name=""
assets_dir="$(cd -P -- "$(dirname -- "$0")" && pwd)"

while (($# > 0)); do
  case "$1" in
    --runtime-root)
      (($# >= 2)) || die "--runtime-root requires a value"
      runtime_root="$2"
      shift 2
      ;;
    --server-name)
      (($# >= 2)) || die "--server-name requires a value"
      server_name="$2"
      shift 2
      ;;
    --assets-dir)
      (($# >= 2)) || die "--assets-dir requires a value"
      assets_dir="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || die "run this script as root"
[[ "$runtime_root" =~ ^/opt/[A-Za-z0-9._-]+$ ]] ||
  die "--runtime-root must be one direct child of /opt"
[[ "$server_name" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] ||
  die "--server-name must be a DNS hostname"

for asset in \
  docker-compose.prod.yml mmgo.env.example nginx-mmgo.conf.template \
  nginx-mmgo-preview.conf.template; do
  [[ -f "${assets_dir}/${asset}" ]] || die "missing bootstrap asset: ${assets_dir}/${asset}"
done

[[ -r /etc/os-release ]] || die "/etc/os-release is missing"
# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == "debian" ]] || die "only Debian hosts are supported"
[[ "${VERSION_ID%%.*}" == "13" ]] ||
  die "this bootstrap is pinned to Debian 13 (found ${VERSION_ID:-unknown})"
[[ -n "${VERSION_CODENAME:-}" ]] || die "Debian VERSION_CODENAME is missing"

install_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    printf 'Docker Engine and Compose are already installed; leaving packages unchanged.\n'
    systemctl enable --now docker
    return
  fi

  if command -v docker >/dev/null 2>&1; then
    die "a partial Docker installation exists; install Compose v2 manually before retrying"
  fi

  local conflicts=()
  local package
  for package in \
    docker.io docker-compose docker-compose-v2 docker-doc docker-buildx \
    podman-docker containerd runc docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras; do
    if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -Fq 'install ok installed'; then
      conflicts+=("$package")
    fi
  done

  ((${#conflicts[@]} == 0)) ||
    die "conflicting container packages are installed; review manually: ${conflicts[*]}"

  for docker_repo_path in \
    /etc/apt/keyrings/docker.asc /etc/apt/sources.list.d/docker.sources; do
    [[ ! -e "$docker_repo_path" ]] ||
      die "partial Docker repository configuration exists; review manually: $docker_repo_path"
  done

  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates curl
  install -d -m 0755 /etc/apt/keyrings

  local docker_key
  local docker_source
  docker_key="$(mktemp)"
  docker_source="$(mktemp)"
  trap 'rm -f -- "$docker_key" "$docker_source"' RETURN

  curl --fail --silent --show-error --location \
    https://download.docker.com/linux/debian/gpg \
    --output "$docker_key"
  install -m 0644 "$docker_key" /etc/apt/keyrings/docker.asc

  printf '%s\n' \
    'Types: deb' \
    'URIs: https://download.docker.com/linux/debian' \
    "Suites: ${VERSION_CODENAME}" \
    'Components: stable' \
    "Architectures: $(dpkg --print-architecture)" \
    'Signed-By: /etc/apt/keyrings/docker.asc' > "$docker_source"
  install -m 0644 "$docker_source" /etc/apt/sources.list.d/docker.sources

  apt-get update
  apt-get install -y --no-install-recommends \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  docker info >/dev/null
  docker compose version >/dev/null
  trap - RETURN
  rm -f -- "$docker_key" "$docker_source"
}

install_without_overwrite() {
  local source="$1"
  local destination="$2"
  local mode="$3"

  if [[ -e "$destination" ]]; then
    cmp --silent "$source" "$destination" ||
      die "refusing to overwrite existing file: $destination"
    chmod "$mode" "$destination"
    printf 'Kept existing %s (content matches).\n' "$destination"
  else
    install -m "$mode" "$source" "$destination"
    printf 'Installed %s.\n' "$destination"
  fi
}

install_nginx_site() {
  command -v nginx >/dev/null 2>&1 ||
    die "nginx is required but was not found"
  [[ -d /etc/nginx/sites-available && -d /etc/nginx/sites-enabled ]] ||
    die "nginx does not use Debian sites-available/sites-enabled directories"

  local existing_site
  local server_name_pattern
  server_name_pattern="${server_name//./\\.}"
  existing_site="$(
    grep -R -l -E -- \
      "server_name[[:space:]]+([^;]*[[:space:]])?${server_name_pattern}([[:space:];])" \
      /etc/nginx/sites-enabled 2>/dev/null |
      head -n 1 || true
  )"

  if [[ -n "$existing_site" ]]; then
    printf 'nginx already manages %s in %s; leaving it unchanged.\n' \
      "$server_name" "$existing_site"
    return
  fi

  local rendered_site
  local available_site=/etc/nginx/sites-available/mmgo.conf
  local enabled_site=/etc/nginx/sites-enabled/mmgo.conf
  local installed_available=false
  local installed_enabled=false
  rendered_site="$(mktemp)"
  sed "s/__MMGO_SERVER_NAME__/${server_name}/g" \
    "${assets_dir}/nginx-mmgo.conf.template" > "$rendered_site"

  if [[ -e "$available_site" ]]; then
    cmp --silent "$rendered_site" "$available_site" || {
      rm -f -- "$rendered_site"
      die "refusing to overwrite existing nginx site: $available_site"
    }
  else
    install -m 0644 "$rendered_site" "$available_site"
    installed_available=true
  fi
  rm -f -- "$rendered_site"

  if [[ -e "$enabled_site" || -L "$enabled_site" ]]; then
    [[ "$(readlink -f -- "$enabled_site")" == "$available_site" ]] ||
      die "refusing to replace existing nginx link: $enabled_site"
  else
    ln -s "$available_site" "$enabled_site"
    installed_enabled=true
  fi

  if ! nginx -t; then
    [[ "$installed_enabled" == true ]] && rm -f -- "$enabled_site"
    [[ "$installed_available" == true ]] && rm -f -- "$available_site"
    die "nginx rejected the MMGO site; newly installed files were rolled back"
  fi

  if ! systemctl reload nginx; then
    [[ "$installed_enabled" == true ]] && rm -f -- "$enabled_site"
    [[ "$installed_available" == true ]] && rm -f -- "$available_site"
    nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
    die "nginx could not reload the MMGO site; newly installed files were rolled back"
  fi
  printf 'Enabled the independent nginx site %s for %s.\n' "$available_site" "$server_name"
}

install_nginx_preview() {
  command -v nginx >/dev/null 2>&1 ||
    die "nginx is required but was not found"
  [[ -d /etc/nginx/sites-available && -d /etc/nginx/sites-enabled ]] ||
    die "nginx does not use Debian sites-available/sites-enabled directories"

  local rendered_site
  local available_site=/etc/nginx/sites-available/mmgo-preview.conf
  local enabled_site=/etc/nginx/sites-enabled/mmgo-preview.conf
  local installed_available=false
  local installed_enabled=false
  rendered_site="$(mktemp)"
  sed "s/__MMGO_SERVER_NAME__/${server_name}/g" \
    "${assets_dir}/nginx-mmgo-preview.conf.template" > "$rendered_site"

  if [[ -e "$available_site" ]]; then
    cmp --silent "$rendered_site" "$available_site" || {
      rm -f -- "$rendered_site"
      die "refusing to overwrite existing nginx preview site: $available_site"
    }
  else
    install -m 0644 "$rendered_site" "$available_site"
    installed_available=true
  fi
  rm -f -- "$rendered_site"

  if [[ -e "$enabled_site" || -L "$enabled_site" ]]; then
    [[ "$(readlink -f -- "$enabled_site")" == "$available_site" ]] ||
      die "refusing to replace existing nginx preview link: $enabled_site"
  else
    ln -s "$available_site" "$enabled_site"
    installed_enabled=true
  fi

  if ! nginx -t; then
    [[ "$installed_enabled" == true ]] && rm -f -- "$enabled_site"
    [[ "$installed_available" == true ]] && rm -f -- "$available_site"
    die "nginx rejected the MMGO preview; newly installed files were rolled back"
  fi

  if ! systemctl reload nginx; then
    [[ "$installed_enabled" == true ]] && rm -f -- "$enabled_site"
    [[ "$installed_available" == true ]] && rm -f -- "$available_site"
    nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
    die "nginx could not reload the MMGO preview; newly installed files were rolled back"
  fi
  printf 'Enabled the loopback-only MMGO preview at 127.0.0.1:4080.\n'
}

install_docker

install -d -m 0755 "$runtime_root" "${runtime_root}/releases"
install -d -m 0700 "${runtime_root}/backups"
install_without_overwrite \
  "${assets_dir}/docker-compose.prod.yml" \
  "${runtime_root}/docker-compose.prod.yml" \
  0600
install_without_overwrite \
  "${assets_dir}/mmgo.env.example" \
  "${runtime_root}/mmgo.env.example" \
  0600
install_nginx_preview
install_nginx_site

printf '\nBootstrap complete. No secret file or application container was created.\n'
printf 'Next: copy %s/mmgo.env.example to %s/mmgo.env, replace placeholders, and run prod-init.\n' \
  "$runtime_root" "$runtime_root"
