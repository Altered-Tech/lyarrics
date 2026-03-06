# syntax=docker/dockerfile:1

FROM ubuntu:24.04

ARG TARGETARCH
ARG BUILD_DATE
ARG VERSION
LABEL build_version="lyarrics version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="alteredtech"

RUN \
  echo "**** install runtime packages ****" && \
  apt-get update && \
  apt-get install -y --no-install-recommends \
    ca-certificates \
    ffmpeg \
    libsqlite3-0 && \
  echo "**** cleanup ****" && \
  rm -rf /var/lib/apt/lists/*

COPY lyarrics-${TARGETARCH} /usr/local/bin/lyarrics-bin
COPY docker/entrypoint.sh /entrypoint.sh
COPY docker/lyarrics.sh /usr/local/bin/lyarrics
RUN chmod +x /entrypoint.sh /usr/local/bin/lyarrics

ENV LYARRICS_DB_PATH="/data/library.db"

VOLUME ["/data"]

ENTRYPOINT ["/entrypoint.sh"]
