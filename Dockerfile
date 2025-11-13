FROM truemanlive/puppy-stardew-server:latest
ARG TARGETOS=linux
ARG TARGETARCH=amd64
ARG TARGETVARIANT=
ARG FRP_VERSION=v0.65.0

USER root

# Install supervisor, envsubst, python3, git (and rsync + jq); create dirs and relax permissions
RUN set -eux; \
    if command -v apt-get >/dev/null 2>&1; then \
      apt-get update && apt-get install -y --no-install-recommends supervisor gettext-base ca-certificates curl python3 python3-pip git rsync jq && \
      rm -rf /var/lib/apt/lists/*; \
    elif command -v microdnf >/dev/null 2>&1; then \
      microdnf install -y supervisor gettext ca-certificates curl python3 python3-pip git rsync jq && microdnf clean all; \
    else \
      echo "Unsupported base for package install"; exit 1; \
    fi; \
    mkdir -p /home/user/supervisor /home/user/run /home/user/frp /home/user/logs /home/user/web /home/user/sync /data /tmp /home/steam/.sdv-backup; \
    chmod -R 777 /home/user /tmp /home/steam/.sdv-backup || true

# Download frp binaries into /usr/local/bin
RUN set -eux; \
    case "${TARGETARCH}${TARGETVARIANT}" in \
      amd64)   FRP_ARCH=amd64 ;; \
      arm64*)  FRP_ARCH=arm64 ;; \
      armv7)   FRP_ARCH=arm ;; \
      arm)     FRP_ARCH=arm ;; \
      *)       FRP_ARCH=amd64 ;; \
    esac; \
    FRP_BALL="frp_${FRP_VERSION#v}_${TARGETOS}_${FRP_ARCH}.tar.gz"; \
    curl -fsSL "https://github.com/fatedier/frp/releases/download/${FRP_VERSION}/${FRP_BALL}" -o /tmp/frp.tgz; \
    tar -xzf /tmp/frp.tgz -C /tmp; \
    FRP_DIR="/tmp/frp_${FRP_VERSION#v}_${TARGETOS}_${FRP_ARCH}"; \
    install -m 0755 "${FRP_DIR}/frpc" /usr/local/bin/frpc || true; \
    install -m 0755 "${FRP_DIR}/frps" /usr/local/bin/frps || true; \
    rm -rf /tmp/frp.tgz "${FRP_DIR}"

# Copy configs and web
COPY supervisord.conf /home/user/supervisor/supervisord.conf
COPY frpc.toml.template /home/user/frp/frpc.toml.template
COPY frp-entry.sh /home/user/frp/frp-entry.sh
COPY requirements.txt /home/user/requirements.txt
COPY web/ /home/user/web/
COPY sync/ /home/user/sync/
COPY sync_to_github.py /home/user/sync_to_github.py
COPY scripts/wait-sync-ready.sh /home/user/scripts/wait-sync-ready.sh

# Install Python deps
RUN python3 -m pip install --upgrade pip && python3 -m pip install --no-cache-dir -r /home/user/requirements.txt

# Permissions and executable bits
RUN chmod -R 777 /home/user && chmod +x /home/user/frp/frp-entry.sh /home/user/sync_to_github.py /home/user/scripts/wait-sync-ready.sh

# Default sync configuration: only sync Stardew saves
ENV BASE="/" \
    HIST_DIR="/home/steam/.sdv-backup" \
    SYNC_TARGETS="home/steam/.config/StardewValley/Saves/"

# Run supervisor (as root) using our config
ENTRYPOINT ["supervisord","-n","-c","/home/user/supervisor/supervisord.conf"]

# Expose Stardew UDP + VNC TCP + Web monitor
EXPOSE 24642/udp 5900/tcp 7860 5321
