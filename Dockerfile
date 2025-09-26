FROM debian:bookworm-slim

ARG RINGO_VER=v0.9.4
ARG RINGO_TGZ_URL=https://terras.gsi.go.jp/software/ringo/dist/${RINGO_VER}/ringo-${RINGO_VER}-linux64.tgz

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gzip bzip2 xz-utils tar python3 coreutils procps \
 && rm -rf /var/lib/apt/lists/*

# Installer ringo
RUN mkdir -p /opt/ringo \
 && curl -fsSL "$RINGO_TGZ_URL" -o /tmp/ringo.tgz \
 && tar -xzf /tmp/ringo.tgz -C /opt/ringo && rm /tmp/ringo.tgz \
 && BIN="$(find /opt/ringo -type f -name ringo -print -quit)"; \
    cp "$BIN" /usr/local/bin/ringo && chmod +x /usr/local/bin/ringo \
 && /usr/local/bin/ringo help >/dev/null

WORKDIR /work
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

