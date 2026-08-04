# syntax=docker/dockerfile:1

# lyarrics only ever shells out to `ffprobe -show_format -show_streams` to read
# audio tags (see LibraryScanner.swift) — it never encodes, transcodes, or touches
# video/GPU/subtitle rendering. Ubuntu's `ffmpeg` package Depends: (not just
# Recommends:) on a much bigger stack for those unused features — Mesa/LLVM for
# GPU-accelerated filters, librsvg for SVG subtitle rendering, flite for
# text-to-speech, liblapack, etc. That alone is >200MB of unused weight.
#
# This stage installs the full package just to extract `ffprobe` and its actual
# runtime shared-library dependencies (resolved via `ldd`, which reports the full
# transitive closure), so the final image only carries what ffprobe really needs.
FROM ubuntu:24.04 AS ffprobe-builder

RUN apt-get update && \
    apt-get install -y --no-install-recommends ffmpeg && \
    rm -rf /var/lib/apt/lists/*

RUN set -eu; \
    mkdir -p /out/usr/bin; \
    cp /usr/bin/ffprobe /out/usr/bin/ffprobe; \
    # Copy a path and, if it's a symlink, every hop in its resolution chain — each
    # preserved as its own symlink/file, at the *physical* (symlink-resolved)
    # directory but the file's own name. Two things this has to get right:
    #  - Fully resolving with `realpath` instead (i.e. only copying the final target)
    #    breaks libraries that go through Debian's "alternatives" indirection, like
    #    BLAS/LAPACK: the dynamic linker looks up the exact SONAME `libblas.so.3`,
    #    itself a symlink (-> /etc/alternatives/... -> the real implementation file)
    #    — flattening that chain away leaves no file with the name it asked for.
    #  - Resolving the *directory* physically (not just leaving it as `/lib/...`)
    #    avoids ever writing a real directory on top of where Ubuntu's usrmerge
    #    layout (/lib -> usr/lib) has a symlink at the destination — COPY refuses
    #    to merge a plain directory onto a symlink.
    copy_chain() { \
        src="$1"; \
        while true; do \
            dir=$(cd "$(dirname "$src")" && pwd -P); \
            base=$(basename "$src"); \
            mkdir -p "/out$dir"; \
            if [ -L "$src" ]; then \
                cp -P "$src" "/out$dir/$base"; \
                target=$(readlink "$src"); \
                case "$target" in \
                    /*) src="$target" ;; \
                    *) src="$dir/$target" ;; \
                esac; \
            else \
                cp "$src" "/out$dir/$base"; \
                break; \
            fi; \
        done; \
    }; \
    for lib in $(ldd /usr/bin/ffprobe | awk '{print $3}' | grep '^/'); do \
        copy_chain "$lib"; \
    done; \
    # ldd reports the dynamic linker itself on its own line with no "=>" separator
    # (e.g. `/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1 (0x...)`) — grab that too.
    linker=$(ldd /usr/bin/ffprobe | grep 'ld-linux' | awk '{print $1}'); \
    copy_chain "$linker"

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
    libsqlite3-0 && \
  echo "**** cleanup ****" && \
  rm -rf /var/lib/apt/lists/*

COPY --from=ffprobe-builder /out/ /
# Refresh the dynamic linker cache so ffprobe's shared libraries resolve
# from their standard paths without relying on cache entries baked into
# the builder stage (which this final image doesn't inherit).
RUN ldconfig && chmod +x /usr/bin/ffprobe

COPY lyarrics-${TARGETARCH} /usr/local/bin/lyarrics-bin
COPY docker/entrypoint.sh /entrypoint.sh
COPY docker/lyarrics.sh /usr/local/bin/lyarrics
RUN chmod +x /entrypoint.sh /usr/local/bin/lyarrics

ENV LYARRICS_DB_PATH="/data/library.db"

VOLUME ["/data"]
EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
