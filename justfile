set dotenv-load := false
set shell := ["bash", "-euo", "pipefail", "-c"]

app := "mmgo"
version := `sed -nE 's/^[[:space:]]*version: "([^"]+)".*/\1/p' mix.exs | head -1`
jump_host := env_var_or_default("MMGO_JUMP_HOST", "klara")
app_host := env_var_or_default("MMGO_APP_HOST", "nova")
remote_root := env_var_or_default("MMGO_REMOTE_ROOT", "/opt/mmgo")
public_url := env_var_or_default("MMGO_PUBLIC_URL", "https://mmgo.mrtimeman.ru")
private_health_url := env_var_or_default("MMGO_PRIVATE_HEALTH_URL", "http://127.0.0.1:4000")
docker_builder := env_var_or_default("MMGO_DOCKER_BUILDER", "default")

# Show the available project operations.
default:
    @just --list

# Run the repository's complete release gate.
release-check:
    mix precommit

# Print the resolved deployment target without reading or displaying secrets.
deploy-plan:
    @printf 'version:  %s\n' '{{version}}'
    @printf 'source:   %s\n' "$(git rev-parse --short=12 HEAD)"
    @if [[ -n '{{jump_host}}' ]]; then \
      printf 'target:   %s (via %s)\n' '{{app_host}}' '{{jump_host}}'; \
    else \
      printf 'target:   %s (direct)\n' '{{app_host}}'; \
    fi
    @printf 'runtime:  %s\n' '{{remote_root}}'
    @printf 'public:   %s\n' '{{public_url}}'
    @printf 'health:   %s\n' '{{private_health_url}}'
    @printf 'build:    remote host only\n'
    @printf 'builder:  %s\n' '{{docker_builder}}'

# Bootstrap a fresh Debian 13 host without reading secrets or replacing an
# existing nginx virtual host. The checked-in templates are the entire payload.
bootstrap-host:
    #!/usr/bin/env bash
    set -Eeuo pipefail

    jump_host='{{jump_host}}'
    app_host='{{app_host}}'
    remote_root='{{remote_root}}'
    public_url='{{public_url}}'

    for command in git gzip mktemp scp shasum ssh; do
      command -v "$command" >/dev/null || {
        printf 'Missing required command: %s\n' "$command" >&2
        exit 1
      }
    done

    [[ "$public_url" =~ ^https://([0-9A-Za-z]([0-9A-Za-z.-]*[0-9A-Za-z])?)(:[0-9]+)?$ ]] || {
      printf 'MMGO_PUBLIC_URL must be an HTTPS origin with a DNS hostname and no path.\n' >&2
      exit 1
    }
    server_name="${BASH_REMATCH[1]}"

    [[ "$remote_root" =~ ^/opt/[0-9A-Za-z._-]+$ ]] || {
      printf 'MMGO_REMOTE_ROOT must be one direct child of /opt.\n' >&2
      exit 1
    }

    if [[ -n "$(git status --porcelain)" ]]; then
      printf 'Bootstrap refused: commit or stash every local change first.\n' >&2
      git status --short >&2
      exit 1
    fi

    short_sha="$(git rev-parse --short=12 HEAD)"
    archive="$(mktemp "${TMPDIR:-/tmp}/mmgo-bootstrap-${short_sha}.XXXXXX.tgz")"
    remote_archive="/tmp/mmgo-bootstrap-${short_sha}.tgz"
    trap 'rm -f -- "$archive"' EXIT

    # Archive only paths tracked by this commit. An ignored local secret placed
    # beside the templates can therefore never enter the bootstrap payload.
    git archive --format=tar HEAD deploy/production | gzip -9 > "$archive"
    checksum="$(shasum -a 256 "$archive" | awk '{print $1}')"

    scp_options=(-q -o BatchMode=yes)
    ssh_options=(-o BatchMode=yes)
    if [[ -n "$jump_host" ]]; then
      scp_options+=(-J "$jump_host")
      ssh_options+=(-J "$jump_host")
    fi

    printf 'Uploading the non-secret bootstrap bundle to %s…\n' "$app_host"
    scp "${scp_options[@]}" "$archive" "${app_host}:${remote_archive}"

    ssh "${ssh_options[@]}" "$app_host" bash -s -- \
      "$remote_archive" "$checksum" "$remote_root" "$server_name" <<'REMOTE'
    set -Eeuo pipefail

    archive="$1"
    expected_checksum="$2"
    runtime_root="$3"
    server_name="$4"
    work_dir="$(mktemp -d /tmp/mmgo-bootstrap.XXXXXX)"

    cleanup() {
      rm -f -- "$archive"
      rm -rf -- "$work_dir"
    }
    trap cleanup EXIT

    actual_checksum="$(sha256sum "$archive" | awk '{print $1}')"
    [[ "$actual_checksum" == "$expected_checksum" ]] || {
      printf 'Bootstrap archive checksum mismatch.\n' >&2
      exit 1
    }

    tar -xzf "$archive" -C "$work_dir"
    bash "$work_dir/deploy/production/bootstrap-debian.sh" \
      --assets-dir "$work_dir/deploy/production" \
      --runtime-root "$runtime_root" \
      --server-name "$server_name"
    REMOTE

# Validate the protected production env and start only PostgreSQL. This leaves
# the application slot untouched so the normal deploy smoke gate remains first.
prod-init:
    #!/usr/bin/env bash
    set -Eeuo pipefail

    jump_host='{{jump_host}}'
    ssh_options=(-o BatchMode=yes)
    if [[ -n "$jump_host" ]]; then
      ssh_options+=(-J "$jump_host")
    fi

    ssh "${ssh_options[@]}" '{{app_host}}' bash -s -- '{{remote_root}}' <<'REMOTE'
    set -Eeuo pipefail

    runtime_root="$1"
    compose_file="${runtime_root}/docker-compose.prod.yml"
    env_file="${runtime_root}/mmgo.env"

    [[ -f "$compose_file" ]] || {
      printf 'Missing Compose file: %s\n' "$compose_file" >&2
      exit 1
    }
    [[ -f "$env_file" ]] || {
      printf 'Missing protected env file: %s\n' "$env_file" >&2
      exit 1
    }
    [[ "$(stat -c '%u' "$env_file")" == 0 ]] || {
      printf '%s must be owned by root.\n' "$env_file" >&2
      exit 1
    }

    env_mode="$(stat -c '%a' "$env_file")"
    [[ "$env_mode" == 600 || "$env_mode" == 400 ]] || {
      printf '%s must have mode 0600 or 0400 (found %s).\n' "$env_file" "$env_mode" >&2
      exit 1
    }

    required_keys=(
      POSTGRES_USER
      POSTGRES_PASSWORD
      POSTGRES_DB
      DATABASE_URL
      ECTO_SSL
      SECRET_KEY_BASE
      PHX_HOST
      TELEGRAM_BOT_TOKEN
      TELEGRAM_WEBHOOK_SECRET
      TELEGRAM_MINI_APP_URL
      FEDERATION_PUBLIC_BASE_URL
      FEDERATION_IMPORT_TOKEN
      DEEPSEEK_API_KEY
    )
    missing_keys=()
    for key in "${required_keys[@]}"; do
      grep -Eq "^${key}=[^[:space:]].*$" "$env_file" || missing_keys+=("$key")
    done
    ((${#missing_keys[@]} == 0)) || {
      printf 'Missing or blank production values: %s\n' "${missing_keys[*]}" >&2
      exit 1
    }

    if grep -Ev '^[[:space:]]*(#|$)' "$env_file" |
      grep -Eq 'CHANGE_ME|mmgo\.example\.com'; then
      printf 'Production env still contains example placeholders.\n' >&2
      exit 1
    fi

    env_value() {
      sed -n "s/^${1}=//p" "$env_file" | tail -n 1
    }

    [[ "$(env_value ECTO_SSL)" == false ]] || {
      printf 'ECTO_SSL must be false for the private Compose PostgreSQL service.\n' >&2
      exit 1
    }

    database_url="$(env_value DATABASE_URL)"
    [[ "$database_url" =~ ^ecto://.+@postgres(:[0-9]+)?/.+$ ]] || {
      printf 'DATABASE_URL must target the private Compose host named postgres.\n' >&2
      exit 1
    }

    docker compose --env-file "$env_file" -f "$compose_file" config --quiet
    docker compose --env-file "$env_file" -f "$compose_file" up -d postgres

    postgres_ready=false
    for _attempt in $(seq 1 30); do
      if [[ "$(docker inspect mmgo-postgres --format '{{{{.State.Health.Status}}' 2>/dev/null || true)" == healthy ]]; then
        postgres_ready=true
        break
      fi
      sleep 2
    done

    [[ "$postgres_ready" == true ]] || {
      docker logs --tail 120 mmgo-postgres >&2 || true
      printf 'PostgreSQL never became healthy.\n' >&2
      exit 1
    }

    docker compose --env-file "$env_file" -f "$compose_file" ps postgres
    printf 'Production PostgreSQL is ready; run just deploy next.\n'
    REMOTE

# Build, smoke-test, migrate, and deploy the current committed release.
# The recipe refuses dirty worktrees so production always maps to a Git commit.
deploy: release-check
    #!/usr/bin/env bash
    set -Eeuo pipefail

    app='{{app}}'
    version='{{version}}'
    jump_host='{{jump_host}}'
    app_host='{{app_host}}'
    remote_root='{{remote_root}}'
    public_url='{{public_url}}'
    private_health_url='{{private_health_url}}'
    docker_builder='{{docker_builder}}'

    for command in base64 git gzip mktemp scp shasum ssh; do
      command -v "$command" >/dev/null || {
        printf 'Missing required command: %s\n' "$command" >&2
        exit 1
      }
    done

    [[ "$version" =~ ^[0-9A-Za-z._-]+$ ]] || {
      printf 'Unsafe release version: %s\n' "$version" >&2
      exit 1
    }

    [[ "$docker_builder" =~ ^[0-9A-Za-z._-]+$ ]] || {
      printf 'Unsafe Docker builder name: %s\n' "$docker_builder" >&2
      exit 1
    }

    [[ "$public_url" =~ ^https://[0-9A-Za-z.-]+(:[0-9]+)?$ ]] || {
      printf 'MMGO_PUBLIC_URL must be an HTTPS origin without a path.\n' >&2
      exit 1
    }

    if [[ -n "$(git status --porcelain)" ]]; then
      printf 'Deployment refused: commit or stash every local change first.\n' >&2
      git status --short >&2
      exit 1
    fi

    source_sha="$(git rev-parse HEAD)"
    short_sha="${source_sha:0:12}"
    release_notes="${MMGO_RELEASE_NOTES:-Небольшие исправления и улучшения закрытой альфы.}"
    release_notes_base64="$(printf '%s' "$release_notes" | base64 | tr -d '\n')"
    image="${app}:${version}"
    archive="$(mktemp "${TMPDIR:-/tmp}/${app}-${version}-${short_sha}.XXXXXX.tgz")"
    remote_archive="/tmp/${app}-${version}-${short_sha}.tgz"

    cleanup_local() {
      rm -f -- "$archive"
    }
    trap cleanup_local EXIT

    git archive --format=tar --prefix="${app}-${version}/" HEAD | gzip -9 > "$archive"
    checksum="$(shasum -a 256 "$archive" | awk '{print $1}')"

    scp_options=(-q -o BatchMode=yes)
    ssh_options=(-o BatchMode=yes)
    if [[ -n "$jump_host" ]]; then
      scp_options+=(-J "$jump_host")
      ssh_options+=(-J "$jump_host")
    fi

    printf 'Uploading %s (%s)…\n' "$image" "$short_sha"
    scp "${scp_options[@]}" "$archive" "${app_host}:${remote_archive}"

    ssh "${ssh_options[@]}" "$app_host" bash -s -- \
      "$app" \
      "$version" \
      "$source_sha" \
      "$remote_root" \
      "$remote_archive" \
      "$checksum" \
      "$public_url" \
      "$private_health_url" \
      "$release_notes_base64" \
      "$docker_builder" <<'REMOTE'
    set -Eeuo pipefail

    app="$1"
    version="$2"
    source_sha="$3"
    remote_root="$4"
    remote_archive="$5"
    expected_checksum="$6"
    public_url="$7"
    private_health_url="$8"
    release_notes_base64="$9"
    docker_builder="${10}"

    image="${app}:${version}"
    short_sha="${source_sha:0:12}"
    release_dir="${remote_root}/releases/${version}-${short_sha}"
    compose_file="${remote_root}/docker-compose.prod.yml"
    env_file="${remote_root}/mmgo.env"
    backup_dir="${remote_root}/backups"
    smoke_name="${app}-deploy-smoke"
    smoke_url="http://127.0.0.1:4100"

    cleanup_remote() {
      docker stop --timeout 15 "$smoke_name" >/dev/null 2>&1 || true
      rm -f -- "$remote_archive"
    }
    trap cleanup_remote EXIT

    for required_path in "$compose_file" "$env_file" "$backup_dir"; do
      [[ -e "$required_path" ]] || {
        printf 'Required production path is missing: %s\n' "$required_path" >&2
        exit 1
      }
    done

    actual_checksum="$(sha256sum "$remote_archive" | awk '{print $1}')"
    [[ "$actual_checksum" == "$expected_checksum" ]] || {
      printf 'Uploaded archive checksum mismatch.\n' >&2
      exit 1
    }

    if [[ -d "$release_dir" ]]; then
      [[ -f "$release_dir/.source-sha" ]] &&
        [[ "$(cat "$release_dir/.source-sha")" == "$source_sha" ]] || {
          printf 'Release directory exists without the expected source marker: %s\n' "$release_dir" >&2
          exit 1
        }
    else
      install -d -m 0755 "$release_dir"
      tar -xzf "$remote_archive" --strip-components=1 -C "$release_dir"
      printf '%s\n' "$source_sha" > "$release_dir/.source-sha"
    fi

    printf 'Building %s…\n' "$image"
    if [[ "$docker_builder" == "default" ]]; then
      docker build --tag "$image" "$release_dir"
    else
      docker build --builder "$docker_builder" --load --tag "$image" "$release_dir"
    fi

    timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
    database_backup="${backup_dir}/${app}-pre-${version}-${timestamp}.dump"
    docker exec mmgo-postgres sh -c \
      'pg_dump --format=custom --username="$POSTGRES_USER" "$POSTGRES_DB"' \
      > "$database_backup"
    chmod 600 "$database_backup"
    [[ -s "$database_backup" ]] || {
      printf 'Database backup is empty: %s\n' "$database_backup" >&2
      exit 1
    }

    docker run --rm \
      --network mmgo_default \
      --env-file "$env_file" \
      "$image" /app/bin/migrate

    docker run --rm \
      --network mmgo_default \
      --env-file "$env_file" \
      "$image" /app/bin/seed

    if docker inspect "$smoke_name" >/dev/null 2>&1; then
      printf 'Smoke container already exists: %s\n' "$smoke_name" >&2
      exit 1
    fi

    docker run -d --rm \
      --name "$smoke_name" \
      --network mmgo_default \
      --env-file "$env_file" \
      -p 127.0.0.1:4100:4000 \
      "$image" >/dev/null

    smoke_ready=false
    for _attempt in $(seq 1 30); do
      if curl -fsS --max-time 5 "${smoke_url}/healthz" >/dev/null; then
        smoke_ready=true
        break
      fi
      sleep 2
    done

    [[ "$smoke_ready" == true ]] || {
      docker logs --tail 160 "$smoke_name" >&2
      printf 'Smoke container never became ready.\n' >&2
      exit 1
    }

    smoke_home_html="$(curl -fsS --max-time 5 "${smoke_url}/")"
    smoke_play_html="$(curl -fsS --max-time 5 "${smoke_url}/play")"
    grep -Fq 'Министерство' <<<"$smoke_home_html"
    grep -Fq 'Предъявить приглашение' <<<"$smoke_play_html"

    ai_runtime="$(
      docker exec "$smoke_name" /app/bin/mmgo rpc '
        config = Application.fetch_env!(:mmgo, MMGO.AI)
        provider = config[:default_provider]
        model = get_in(config, [:models, :spell_compile])
        IO.puts("ai_provider=#{inspect(provider)}")
        IO.puts("ai_spell_model=#{inspect(model)}")

        if provider == MMGO.AI.Providers.DeepSeek and is_binary(model) and
             String.trim(model) != "" do
          IO.puts("ai_runtime=ok")
        else
          IO.puts("ai_runtime=invalid")
        end
      '
    )"
    printf '%s\n' "$ai_runtime"
    grep -Fqx 'ai_provider=MMGO.AI.Providers.DeepSeek' <<<"$ai_runtime"
    grep -Fqx 'ai_runtime=ok' <<<"$ai_runtime"

    deepseek_probe="$(
      docker exec "$smoke_name" /app/bin/mmgo rpc '
        config = Application.fetch_env!(:mmgo, MMGO.AI)
        model = get_in(config, [:models, :spell_compile])
        prompt = %{
          system_prompt: "You are a deployment health probe. Return only the requested JSON.",
          user_prompt: ~s|Return exactly {"status":"ok"} and nothing else.|
        }
        schema = %{
          type: "object",
          properties: %{status: %{type: "string", enum: ["ok"]}},
          required: ["status"]
        }

        result =
          try do
            case MMGO.AI.Providers.DeepSeek.structured_completion(
                   prompt,
                   schema,
                   model: model
                 ) do
              {:ok, %{"status" => "ok"}} -> :ok
              {:ok, _other} -> :invalid_response
              {:error, {:deepseek_api, status, _details}} -> {:api, status}
              {:error, %Req.TransportError{}} -> :network
              {:error, :missing_api_key} -> :configuration
              {:error, _reason} -> :provider_error
            end
          rescue
            _exception -> :probe_exception
          catch
            _kind, _reason -> :probe_exception
          end

        case result do
          :ok -> IO.puts("ai_deepseek_probe=ok")
          {:api, status} -> IO.puts("ai_deepseek_probe=api_#{status}")
          reason -> IO.puts("ai_deepseek_probe=#{reason}")
        end
      '
    )"
    printf '%s\n' "$deepseek_probe"
    grep -Fqx 'ai_deepseek_probe=ok' <<<"$deepseek_probe"
    docker stop --timeout 15 "$smoke_name" >/dev/null

    compose_backup="${backup_dir}/docker-compose.prod.yml.pre-${version}-${timestamp}"
    cp --preserve=mode,ownership,timestamps "$compose_file" "$compose_backup"

    sed -E -i \
      "s|^([[:space:]]*image:[[:space:]]*)${app}:[^[:space:]]+|\\1${image}|" \
      "$compose_file"
    chmod 600 "$compose_file"
    docker compose --env-file "$env_file" -f "$compose_file" config --quiet
    grep -Fq "image: ${image}" "$compose_file"

    docker compose --env-file "$env_file" -f "$compose_file" \
      up -d --no-deps --force-recreate app

    production_ready=false
    for _attempt in $(seq 1 30); do
      if private_health="$(curl -fsS --max-time 5 "${private_health_url}/healthz")" &&
        grep -Fq "\"version\":\"${version}\"" <<<"$private_health"; then
        production_ready=true
        break
      fi
      sleep 2
    done

    [[ "$production_ready" == true ]] || {
      docker logs --tail 200 mmgo-app >&2
      printf 'Production container never became ready.\n' >&2
      exit 1
    }

    public_authority="${public_url#https://}"
    public_host="${public_authority%%:*}"
    if [[ "$public_authority" == *:* ]]; then
      public_port="${public_authority##*:}"
    else
      public_port=443
    fi

    public_health="$(
      curl -fsS --max-time 15 \
        --resolve "${public_host}:${public_port}:127.0.0.1" \
        "${public_url}/healthz"
    )"
    grep -Fq "\"version\":\"${version}\"" <<<"$public_health"
    printf 'public_health=%s\n' "$public_health"

    docker exec mmgo-app /app/bin/mmgo rpc \
      "case MMGO.Telegram.configure_bot(\"${public_url}\") do {:ok, _} -> IO.puts(\"telegram_config=ok\"); other -> IO.inspect(other, label: \"telegram_config\") end"

    docker exec mmgo-app /app/bin/mmgo rpc \
      "release_notes = Base.decode64!(\"${release_notes_base64}\"); case MMGO.Telegram.ReleaseAnnouncements.announce_release(\"${version}\", release_notes) do {:ok, :not_configured} -> IO.puts(\"release_announcement=not_configured\"); {:ok, _} -> IO.puts(\"release_announcement=sent\"); other -> IO.inspect(other, label: \"release_announcement\") end"

    docker inspect mmgo-app \
      --format 'image={{{{.Config.Image}} status={{{{.State.Status}} health={{{{.State.Health.Status}}'
    printf 'database_backup=%s\n' "$database_backup"
    printf 'source_sha=%s\n' "$source_sha"
    REMOTE

    printf 'Deployed %s from %s to %s\n' "$image" "$short_sha" "$public_url"

# Verify the live container, private listener, and public HTTPS path.
prod-status:
    #!/usr/bin/env bash
    set -Eeuo pipefail
    jump_host='{{jump_host}}'
    ssh_options=(-o BatchMode=yes)
    if [[ -n "$jump_host" ]]; then
      ssh_options+=(-J "$jump_host")
    fi
    ssh "${ssh_options[@]}" '{{app_host}}' bash -s -- \
      '{{private_health_url}}' '{{public_url}}' <<'REMOTE'
    set -Eeuo pipefail
    private_health_url="$1"
    public_url="$2"
    public_authority="${public_url#https://}"
    public_host="${public_authority%%:*}"
    if [[ "$public_authority" == *:* ]]; then
      public_port="${public_authority##*:}"
    else
      public_port=443
    fi

    docker inspect mmgo-app \
      --format 'image={{{{.Config.Image}} status={{{{.State.Status}} health={{{{.State.Health.Status}}'
    docker port mmgo-app
    curl -fsS --max-time 8 "${private_health_url}/healthz"
    printf '\n'
    curl -fsS --max-time 15 \
      --resolve "${public_host}:${public_port}:127.0.0.1" \
      "${public_url}/healthz"
    printf '\n'
    REMOTE

# Open an encrypted local preview at http://127.0.0.1:<port>. This bypasses
# DNS filtering without publishing Phoenix or an unauthenticated preview port.
prod-tunnel port="4400":
    #!/usr/bin/env bash
    set -Eeuo pipefail
    [[ '{{port}}' =~ ^[1-9][0-9]{1,4}$ ]] && ((10#{{port}} <= 65535)) || {
      printf 'port must be an integer from 10 to 65535\n' >&2
      exit 1
    }
    jump_host='{{jump_host}}'
    ssh_options=(-N -T -o ExitOnForwardFailure=yes)
    if [[ -n "$jump_host" ]]; then
      ssh_options+=(-J "$jump_host")
    fi
    printf 'MMGO preview: http://127.0.0.1:{{port}} (press Ctrl-C to close)\n'
    exec ssh "${ssh_options[@]}" \
      -L '127.0.0.1:{{port}}:127.0.0.1:4080' \
      '{{app_host}}'

# Tail production application logs without reading the protected env file.
prod-logs lines="200":
    #!/usr/bin/env bash
    set -Eeuo pipefail
    [[ '{{lines}}' =~ ^[1-9][0-9]{0,3}$ ]] || {
      printf 'lines must be an integer from 1 to 9999\n' >&2
      exit 1
    }
    jump_host='{{jump_host}}'
    ssh_options=(-o BatchMode=yes)
    if [[ -n "$jump_host" ]]; then
      ssh_options+=(-J "$jump_host")
    fi
    ssh "${ssh_options[@]}" '{{app_host}}' \
      "docker logs --tail '{{lines}}' mmgo-app"
