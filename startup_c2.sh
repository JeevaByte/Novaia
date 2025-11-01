#!/bin/bash
set -euo pipefail

# C2-optimized startup script for Ubuntu 22.04
# - Installs Python 3.11, venv, pip
# - Installs Docker (optional)
# - Clones repo and creates venv
# - Installs requirements.txt if present
# - Creates a systemd service that runs STARTUP_CMD (or default entrypoint)

# ======= CONFIGURATION (edit before use) =======
REPO_URL="https://github.com/urbainze/novaia.git"    # <-- replace with your repo URL if private use gcloud metadata or SSH
APP_DIR="/opt/novaia"
GIT_BRANCH="master"
PYTHON_BIN="/usr/bin/python3.11"
VENV_DIR="$APP_DIR/venv"
SERVICE_NAME="novaia-c2"
# Command the systemd service will run. If you want to run a different file, set STARTUP_CMD in instance metadata or edit below.
DEFAULT_STARTUP_CMD="$VENV_DIR/bin/python $APP_DIR/services/speech_processing/src/test_server.py"
STARTUP_CMD="${STARTUP_CMD:-$DEFAULT_STARTUP_CMD}"
LOGFILE="/var/log/${SERVICE_NAME}.log"

# ======= HELPER LOGGING =======
log() { echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') [startup] $*" | tee -a "$LOGFILE"; }

log "Starting startup script on $(hostname)"

# --- update & essential packages ---
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y --no-install-recommends \
    build-essential git curl wget ca-certificates software-properties-common apt-transport-https lsb-release gnupg

# --- install newer Python (3.11) ---
# Use deadsnakes PPA for Ubuntu LTS
if ! command -v $PYTHON_BIN >/dev/null 2>&1; then
  add-apt-repository -y ppa:deadsnakes/ppa
  apt-get update -y
  apt-get install -y python3.11 python3.11-venv python3.11-dev python3-distutils
  # ensure pip for python3.11
  curl -sS https://bootstrap.pypa.io/get-pip.py | $PYTHON_BIN -
fi

# --- optional: tune CPU governor for max performance on C2 ---
if [ -d /sys/devices/system/cpu ]; then
  if command -v cpufreq-info >/dev/null 2>&1; then
    log "Setting CPU governor to performance"
    for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
      GOV_FILE="$cpu/cpufreq/scaling_governor"
      if [ -f "$GOV_FILE" ]; then
        echo performance > "$GOV_FILE" || true
      fi
    done
  fi
fi

# --- install Docker (optional) ---
if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker"
  curl -fsSL https://get.docker.com | sh
  # allow 'ubuntu' user if exists to use docker
  if id ubuntu >/dev/null 2>&1; then
    usermod -aG docker ubuntu || true
  fi
fi

# --- clone repo ---
log "Cloning repository to $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
if git ls-remote --exit-code "$REPO_URL" >/dev/null 2>&1; then
  git clone --depth 1 --branch "$GIT_BRANCH" "$REPO_URL" "$APP_DIR"
else
  log "WARNING: cannot reach $REPO_URL. Please check REPO_URL or supply repository via other means."
fi

# --- create venv and install requirements ---
log "Creating virtualenv and installing Python requirements"
$PYTHON_BIN -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install --upgrade pip setuptools wheel
if [ -f "$APP_DIR/requirements.txt" ]; then
  pip install -r "$APP_DIR/requirements.txt"
else
  log "No requirements.txt found in $APP_DIR"
fi

# --- create systemd service ---
log "Creating systemd service $SERVICE_NAME (ExecStart: $STARTUP_CMD)"
cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=Novaia (C2) service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR
Environment=PATH=$VENV_DIR/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/bin/bash -lc 'exec $STARTUP_CMD'
Restart=on-failure
RestartSec=5
StandardOutput=syslog
StandardError=syslog

[Install]
WantedBy=multi-user.target
EOF

# --- enable & start the service ---
systemctl daemon-reload
systemctl enable ${SERVICE_NAME}.service
systemctl start ${SERVICE_NAME}.service || {
  log "Service failed to start; check journalctl -u ${SERVICE_NAME}.service"
}

log "Startup script finished (service ${SERVICE_NAME})."

# End of startup_c2.sh
