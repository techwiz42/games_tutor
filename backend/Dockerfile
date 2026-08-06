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

# KataGo (real MIT-licensed Go engine) is not packaged for Debian/Ubuntu,
# so it's fetched directly from its official GitHub release in its own
# build stage (keeps curl/unzip out of the final runtime image). Generic
# Eigen (CPU) build, not AVX2, for the same host-CPU-portability reason
# Stockfish uses Debian's generic package rather than an AVX2-specific
# binary -- see docs/KATAGO_ATTRIBUTION.md.
#
# This release build ships as a self-mounting AppImage, which needs FUSE
# (unavailable in Docker -- confirmed the hard way: `katago version` fails
# with "No suitable fusermount binary found"/"Cannot mount AppImage").
# `--appimage-extract` unpacks its payload directly (no FUSE needed for
# that), giving a real ELF binary plus its few bundled .so libs.
FROM debian:${DEBIAN_VERSION} AS katago-fetch
RUN apt-get update -y && apt-get install -y curl unzip ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
WORKDIR /katago
RUN curl -sL -o katago.zip \
      https://github.com/lightvector/KataGo/releases/download/v1.17.1/katago-v1.17.1-eigen-linux-x64.zip \
    && unzip -o katago.zip -d . && rm katago.zip \
    && chmod +x katago && ./katago --appimage-extract >/dev/null \
    && curl -sL -o model.bin.gz \
      https://katagoarchive.org/g170/neuralnets/g170-b6c96-s175395328-d26788732.bin.gz

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

COPY --from=katago-fetch /katago/squashfs-root/usr/bin/katago /usr/local/bin/katago
COPY --from=katago-fetch /katago/squashfs-root/usr/lib/ /opt/katago/lib/
COPY --from=katago-fetch /katago/model.bin.gz /opt/katago/model.bin.gz
RUN chmod +x /usr/local/bin/katago
ENV LD_LIBRARY_PATH=/opt/katago/lib

USER app

COPY --from=build --chown=app:app /app/_build/prod/rel/games_tutor ./
COPY --chown=app:app priv/katago/analysis.cfg /opt/katago/analysis.cfg

EXPOSE 8000

CMD ["sh", "-c", "/app/bin/migrate && /app/bin/server"]
