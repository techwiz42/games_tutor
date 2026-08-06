# Multi-stage build producing a minimal Elixir release, matching this
# project's actual toolchain (Elixir 1.18.1 / OTP 27).

ARG ELIXIR_VERSION=1.18.1
ARG OTP_VERSION=27.3.4.3
ARG DEBIAN_VERSION=bookworm-20250929-slim

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION} AS build

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib

RUN mix compile
COPY config/runtime.exs config/
COPY rel rel
RUN mix release

FROM debian:${DEBIAN_VERSION} AS runtime

# stockfish -- real GPLv3 chess engine, run server-side as a UCI subprocess
# only (never distributed to end-user devices); see docs/STOCKFISH_ATTRIBUTION.md.
RUN apt-get update -y && apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates stockfish \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app
RUN useradd --create-home app
USER app

COPY --from=build --chown=app:app /app/_build/prod/rel/games_tutor ./

EXPOSE 8000

CMD ["sh", "-c", "/app/bin/migrate && /app/bin/server"]
