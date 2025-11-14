FROM truemanlive/puppy-stardew-server:latest

ARG TARGETOS=linux
ARG TARGETARCH=amd64
ARG TARGETVARIANT=
ARG FRP_VERSION=
ARG FB_ADMIN_USER=admin
ARG FB_ADMIN_PASS=adminadminadmin
ARG GOTTY_VERSION=1.6.0

USER root

# Install supervisor, envsubst, python3, git, rsync, jq; create dirs and relax permissions
RUN set -eux; \
    if command -v apt-get >/dev/null 2>&1; then \
      apt-get update && apt-get install -y --no-install-recommends supervisor gettext-base ca-certificates curl jq git gnupg lsb-release python3 python3-pip python3-venv rsync && \
      rm -rf /var/lib/apt/lists/*; \
    elif command -v microdnf >/dev/null 2>&1; then \
      microdnf install -y supervisor gettext ca-certificates curl jq python3 python3-pip git rsync && microdnf clean all; \
    else \
      echo "Unsupported base for package install"; exit 1; \
    fi; \
    mkdir -p /home/user/supervisor /home/user/run /home/user/frp /home/user/logs /home/user/nginx /home/user/sync /home/user/scripts /data /tmp /home/steam/.sdv-backup; \
    chmod -R 777 /home/user /tmp /home/steam/.sdv-backup || true

# Ensure Python >=3.10 (install Miniforge on older bases)
RUN set -eux; \
    PYV=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || echo "0.0"); \
    MAJOR=${PYV%%.*}; MINOR=${PYV##*.}; \
    if [ "${MAJOR}" -lt 3 ] || [ "${MINOR}" -lt 10 ]; then \
      echo "Installing Miniforge (Python >=3.10) to /opt/conda..."; \
      ARCH=$(uname -m); \
      case "$ARCH" in \
        x86_64) MF=Miniforge3-Linux-x86_64.sh ;; \
        aarch64) MF=Miniforge3-Linux-aarch64.sh ;; \
        ppc64le) MF=Miniforge3-Linux-ppc64le.sh ;; \
        *) MF=Miniforge3-Linux-x86_64.sh ;; \
      esac; \
      curl -fsSL "https://github.com/conda-forge/miniforge/releases/latest/download/${MF}" -o /tmp/miniforge.sh; \
      bash /tmp/miniforge.sh -b -p /opt/conda; \
      rm -f /tmp/miniforge.sh; \
      ln -sf /opt/conda/bin/python /usr/local/bin/python3; \
      ln -sf /opt/conda/bin/pip /usr/local/bin/pip3; \
      /usr/local/bin/python3 -V; \
    fi

# Python 3.6 compatibility: install dataclasses backport if needed
RUN python3 - <<'PY'
import sys, subprocess
if sys.version_info < (3,7):
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', '--no-cache-dir', 'dataclasses<0.9'])
PY

# Install OpenResty (nginx with ngx_lua) for dynamic routing
RUN set -eux; \
    if command -v apt-get >/dev/null 2>&1; then \
      . /etc/os-release; \
      curl -fsSL https://openresty.org/package/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/openresty.gpg; \
      if [ "${ID:-ubuntu}" = "ubuntu" ]; then DIST=ubuntu; else DIST=debian; fi; \
      echo "deb [signed-by=/usr/share/keyrings/openresty.gpg] http://openresty.org/package/${DIST} $(lsb_release -sc) main" > /etc/apt/sources.list.d/openresty.list; \
      apt-get update && apt-get install -y --no-install-recommends openresty && rm -rf /var/lib/apt/lists/*; \
      mkdir -p /etc/nginx && ln -sf /usr/local/openresty/nginx/conf/mime.types /etc/nginx/mime.types; \
    elif command -v microdnf >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then \
      . /etc/os-release; \
      if [ "${ID}" = "fedora" ]; then OS_PATH=fedora; else OS_PATH=centos; fi; \
      printf '%s\n' \
        '[openresty]' \
        'name=Official OpenResty Open Source Repository' \
        "baseurl=https://openresty.org/package/${OS_PATH}/"'$releasever/$basearch' \
        'gpgcheck=1' \
        'enabled=1' \
        'gpgkey=https://openresty.org/package/pubkey.gpg' \
        > /etc/yum.repos.d/openresty.repo; \
      if command -v microdnf >/dev/null 2>&1; then \
        microdnf install -y openresty && microdnf clean all; \
      elif command -v dnf >/dev/null 2>&1; then \
        dnf install -y openresty && dnf clean all; \
      else \
        yum install -y openresty && yum clean all; \
      fi; \
      mkdir -p /etc/nginx && ln -sf /usr/local/openresty/nginx/conf/mime.types /etc/nginx/mime.types; \
    else \
      echo "OpenResty install not implemented for this base image" >&2; exit 1; \
    fi

# Download and install latest frp into /usr/local/bin
RUN set -eux; \
    case "${TARGETARCH}${TARGETVARIANT}" in \
      amd64)   FRP_ARCH=amd64 ;; \
      arm64*)  FRP_ARCH=arm64 ;; \
      armv7)   FRP_ARCH=arm ;; \
      arm)     FRP_ARCH=arm ;; \
      386)     FRP_ARCH=386 ;; \
      *)       FRP_ARCH=amd64 ;; \
    esac; \
    LATEST_URL=$(curl -sL https://api.github.com/repos/fatedier/frp/releases/latest | jq -r --arg os "${TARGETOS}" --arg arch "${FRP_ARCH}" '.assets[] | select(.name | endswith("_\($os)_\($arch).tar.gz")) | .browser_download_url' | head -1); \
    [ -n "$LATEST_URL" ] || { echo "Failed to determine latest frp asset for ${TARGETOS}/${FRP_ARCH}" >&2; exit 1; }; \
    curl -fsSL "$LATEST_URL" -o /tmp/frp.tgz; \
    FRP_DIR=$(tar -tzf /tmp/frp.tgz | head -1 | cut -d/ -f1); \
    tar -xzf /tmp/frp.tgz -C /tmp; \
    install -m 0755 "/tmp/${FRP_DIR}/frpc" /usr/local/bin/frpc || true; \
    install -m 0755 "/tmp/${FRP_DIR}/frps" /usr/local/bin/frps || true; \
    rm -rf /tmp/frp.tgz "/tmp/${FRP_DIR}"

# Copy FRP config and entry script
COPY frpc.toml.template /home/user/frp/frpc.toml.template
COPY frp-entry.sh /home/user/frp/frp-entry.sh

# Supervisor and nginx config + logs
RUN mkdir -p /home/user/logs
COPY supervisor/supervisord.conf /home/user/supervisord.conf
RUN mkdir -p /home/user/nginx
COPY nginx/nginx.conf /home/user/nginx/nginx.conf
COPY nginx/default_admin_config.json /home/user/nginx/default_admin_config.json
COPY nginx/route-admin /home/user/nginx/route-admin
RUN mkdir -p \
      /home/user/nginx/tmp/body \
      /home/user/nginx/tmp/proxy \
      /home/user/nginx/tmp/fastcgi \
      /home/user/nginx/tmp/uwsgi \
      /home/user/nginx/tmp/scgi

# Sync service (daemon + web) and helper scripts
COPY sync /home/user/sync
RUN mkdir -p /home/user/scripts
COPY scripts/wait-sync-ready.sh /home/user/scripts/wait-sync-ready.sh

# Python dependencies
COPY requirements.txt /home/user/requirements.txt
RUN python3 -m pip install --upgrade pip && python3 -m pip install --no-cache-dir -r /home/user/requirements.txt

# Install filebrowser (latest) into /home/user，并初始化管理员
RUN set -eux; \
    case "${TARGETARCH}${TARGETVARIANT}" in \
      amd64)   FB_ARCH=amd64 ;; \
      arm64*)  FB_ARCH=arm64 ;; \
      armv7)   FB_ARCH=armv7 ;; \
      armv6)   FB_ARCH=armv6 ;; \
      arm)     FB_ARCH=armv7 ;; \
      386)     FB_ARCH=386 ;; \
      riscv64) FB_ARCH=riscv64 ;; \
      *)       FB_ARCH=amd64 ;; \
    esac; \
    LATEST_URL=$(curl -sL https://api.github.com/repos/filebrowser/filebrowser/releases/latest | jq -r --arg arch "${FB_ARCH}" '.assets[] | select(.name == "linux-\($arch)-filebrowser.tar.gz") | .browser_download_url' | head -1); \
    [ -n "$LATEST_URL" ] || { echo "Failed to determine latest filebrowser asset for arch: ${FB_ARCH}" >&2; exit 1; }; \
    curl -fsSL "$LATEST_URL" -o /tmp/fb.tgz; \
    tar -xzf /tmp/fb.tgz -C /tmp; \
    install -m 0755 /tmp/filebrowser /home/user/filebrowser || { cp /tmp/filebrowser /home/user/filebrowser && chmod 0755 /home/user/filebrowser; }; \
    rm -f /tmp/fb.tgz /tmp/filebrowser; \
    /home/user/filebrowser config init --address 0.0.0.0 --port 8000 --root / --database /home/user/filebrowser.db; \
    if [ "${#FB_ADMIN_PASS}" -lt 12 ]; then echo "ERROR: FB_ADMIN_PASS must be at least 12 characters" >&2; exit 1; fi; \
    /home/user/filebrowser users add "${FB_ADMIN_USER}" "${FB_ADMIN_PASS}" --perm.admin --database /home/user/filebrowser.db

# Install FastAPI + Uvicorn for sync Web UI (matching mc-hf)
RUN python3 -m pip install --no-cache-dir fastapi uvicorn[standard]

## Install GoTTY lightweight web terminal (same pattern as mc-hf)
RUN set -eux; \
    case "${TARGETARCH}${TARGETVARIANT}" in \
      amd64)   G_ARCH=linux_amd64 ;; \
      *)       echo "[gotty] Unsupported arch: ${TARGETARCH}${TARGETVARIANT}, skipping install" >&2; G_ARCH="" ;; \
    esac; \
    if [ -n "$G_ARCH" ]; then \
      curl -fsSL "https://github.com/sorenisanerd/gotty/releases/download/v${GOTTY_VERSION}/gotty_v${GOTTY_VERSION}_${G_ARCH}.tar.gz" -o /tmp/gotty.tgz && \
      tar -xzf /tmp/gotty.tgz -C /tmp && \
      install -m 0755 /tmp/gotty /home/user/gotty || { cp /tmp/gotty /home/user/gotty && chmod 0755 /home/user/gotty; } && \
      rm -f /tmp/gotty.tgz /tmp/gotty; \
    fi

# Permissions and executable bits
RUN mkdir -p /home/user/nginx/tmp/body /home/user/nginx/tmp/proxy /home/user/nginx/tmp/fastcgi /home/user/nginx/tmp/uwsgi /home/user/nginx/tmp/scgi && \
    chmod -R 777 /home/user/nginx && \
    chmod -R 777 /home/user && chmod +x /home/user/frp/frp-entry.sh /home/user/filebrowser /home/user/scripts/wait-sync-ready.sh /home/user/gotty

# Default sync configuration: only sync Stardew saves
ENV BASE="/" \
    HIST_DIR="/home/steam/.sdv-backup" \
    SYNC_TARGETS="home/steam/.config/StardewValley/Saves/"

# Run supervisord using our config (do not read /etc)
ENTRYPOINT ["supervisord","-n","-c","/home/user/supervisord.conf"]

# Prefer Miniforge Python (if installed) and keep OpenResty in PATH
ENV PATH=/opt/conda/bin:/usr/local/openresty/bin:$PATH

# Expose Stardew UDP + VNC TCP + Web router + sync
EXPOSE 24642/udp 5900/tcp 7860 5321
