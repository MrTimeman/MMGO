# Multi-stage build for MMGO Phoenix app
# Build stage
FROM hexpm/elixir:1.19.5-erlang-28.0.1-ubuntu-resolute-20260413 AS builder

WORKDIR /app

# Install build deps + Node.js for assets
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git curl ca-certificates gnupg \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

ENV MIX_ENV=prod

# Install hex + rebar
RUN mix local.hex --force && mix local.rebar --force

# Cache deps
COPY mix.exs mix.lock ./
COPY config/ config/
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy source
COPY lib/ lib/
COPY priv/ priv/
COPY assets/ assets/

# Build assets
RUN mix assets.setup
RUN npm install --prefix assets
RUN mix compile
RUN mix assets.deploy

# Build release
RUN mix release

# Runtime stage
FROM ubuntu:resolute

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates openssl libncurses6 libstdc++6 libtinfo6 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/_build/prod/rel/mmgo ./

ENV PHX_SERVER=true
ENV MIX_ENV=prod
ENV HOME=/app

EXPOSE 4000

CMD ["/app/bin/mmgo", "start"]
