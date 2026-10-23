#!/usr/bin/env bash
# ==============================================================================
# Jenkins Agent Installer — Linux & macOS
# ==============================================================================
set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────────────
INSTALL_DIR="${HOME}/.jenkins-agent"
WORK_DIR="${INSTALL_DIR}/work"
LOG_DIR="${INSTALL_DIR}/logs"
CONF_FILE="${INSTALL_DIR}/agent.conf"
PID_FILE="${INSTALL_DIR}/agent.pid"
LOG_FILE="${LOG_DIR}/agent.log"
AGENT_JAR="${INSTALL_DIR}/agent.jar"
CLI_PATH="/usr/local/bin/jenkins-agent"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Helpers ──────────────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
header()  { echo -e "\n${BOLD}${CYAN}━━━ $* ━━━${NC}\n"; }

detect_os() {
    case "$(uname -s)" in
        Linux*)  echo "linux"  ;;
        Darwin*) echo "macos"  ;;
        *)       echo "unknown"; exit 1 ;;
    esac
}

detect_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64)   echo "x86_64"  ;;
        aarch64|arm64)   echo "aarch64" ;;
        armv7l)          echo "armv7"   ;;
        *)               echo "$arch"   ;;
    esac
}

prompt_default() {
    local prompt="$1"
    local default="$2"
    local result

    if [ -n "$default" ]; then
        echo -en "${BOLD}${prompt}${NC} [${GREEN}${default}${NC}]: " >&2
    else
        echo -en "${BOLD}${prompt}${NC}: " >&2
    fi

    read -r result
    echo "${result:-$default}"
}

expand_home_path() {
    local path="$1"
    case "$path" in
        "~")      path="$HOME" ;;
        "~/"*)    path="$HOME/${path:2}" ;;
    esac
    printf '%s\n' "$path"
}

prompt_secret() {
    local prompt="$1"
    local result

    echo -en "${BOLD}${prompt}${NC}: " >&2
    if [[ -t 0 ]]; then
        read -rs result
        echo "" >&2
    else
        read -r result
    fi
    echo "$result"
}

prompt_confirm() {
    local prompt="$1"
    local default="${2:-n}"

    local options="[y/N]"
    if [[ "$default" == "y" ]]; then
        options="[Y/n]"
    fi

    echo -en "${BOLD}${prompt}${NC} ${options}: "
    read -r result

    local answer="${result:-$default}"
    [[ "$answer" =~ ^[Yy]$ ]]
}

find_java() {
    local java_path

    # 1. JAVA_HOME
    if [[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/java" ]]; then
        echo "${JAVA_HOME}/bin/java"
        return 0
    fi

    # 2. PATH
    if command -v java &>/dev/null; then
        java_path="$(command -v java)"
        if "$java_path" -version &>/dev/null; then
            echo "$java_path"
            return 0
        fi
    fi

    # 3. Common macOS locations
    if [[ "$OS_TYPE" == "macos" ]]; then
        for candidate in \
            /Library/Java/JavaVirtualMachines/*/Contents/Home/bin/java \
            /usr/local/opt/openjdk*/bin/java \
            /opt/homebrew/opt/openjdk*/bin/java; do
            if [[ -x "$candidate" ]]; then
                echo "$candidate"
                return 0
            fi
        done
    fi

    # 4. Common Linux locations
    if [[ "$OS_TYPE" == "linux" ]]; then
        for candidate in \
            /usr/lib/jvm/*/bin/java \
            /usr/java/*/bin/java; do
            if [[ -x "$candidate" ]]; then
                echo "$candidate"
                return 0
            fi
        done
    fi

    return 1
}

ensure_work_dir_owner() {
    local work_dir="$1"
    local agent_user="${SUDO_USER:-$(id -un)}"
    local current_owner

    current_owner="$(stat -f '%Su' "$work_dir" 2>/dev/null || stat -c '%U' "$work_dir" 2>/dev/null || true)"
    if [[ -z "$current_owner" ]]; then
        error "Could not determine the owner of the agent work directory: $work_dir"
        return 1
    fi

    if [[ "$current_owner" != "$agent_user" ]]; then
        info "Changing ownership of the agent work directory to '$agent_user'..."
        if [[ "$EUID" -eq 0 ]]; then
            chown -R "$agent_user" "$work_dir"
        elif command -v sudo &>/dev/null; then
            sudo chown -R "$agent_user" "$work_dir"
        else
            error "Ownership change requires root privileges (sudo)."
            return 1
        fi
    fi

    if [[ ! -r "$work_dir" || ! -w "$work_dir" || ! -x "$work_dir" ]]; then
        error "Agent user '$agent_user' still cannot fully access: $work_dir"
        return 1
    fi

    success "Agent work directory is owned by '$agent_user' and is accessible"
}

# ── Main Installer ───────────────────────────────────────────────────────────
main() {
    OS_TYPE="$(detect_os)"
    ARCH="$(detect_arch)"

    header "Jenkins Agent Installer"
    echo -e "  OS:           ${BOLD}${OS_TYPE}${NC}"
    echo -e "  Architecture: ${BOLD}${ARCH}${NC}"
    echo -e "  Install dir:  ${BOLD}${INSTALL_DIR}${NC}"
    echo ""

    # ── Check for Java ───────────────────────────────────────────────────
    header "Step 1/5: Java Runtime"

    local detected_java
    detected_java="$(find_java 2>/dev/null || echo "")"

    if [[ -n "$detected_java" ]]; then
        local java_version
        java_version="$("$detected_java" -version 2>&1 | head -1)"
        success "Found Java: ${detected_java}"
        info "Version: ${java_version}"
    else
        warn "No Java runtime found on this system."
        if ! prompt_confirm "Do you have Java installed at a custom path?" "n"; then
            error "Java is required. Please install a JRE/JDK 11+ and try again."
            exit 1
        fi
    fi

    local java_path
    java_path="$(prompt_default "Java executable path" "$detected_java")"

    if [[ ! -x "$java_path" ]] && ! command -v "$java_path" &>/dev/null; then
        warn "Java path '${java_path}' does not appear to be valid."
        if ! prompt_confirm "Continue anyway?" "n"; then
            exit 1
        fi
    fi

    # ── Jenkins Connection ───────────────────────────────────────────────
    header "Step 2/5: Jenkins Connection"

    echo -e "${YELLOW}These details are found on the Jenkins node configuration page.${NC}"
    echo -e "${YELLOW}Go to: Manage Jenkins → Nodes → <Your Node> → Configure${NC}"
    echo ""

    local jenkins_url
    jenkins_url="$(prompt_default "Jenkins URL (e.g. http://jenkins.example.com:8080)" "")"
    while [[ -z "$jenkins_url" ]]; do
        warn "Jenkins URL is required."
        jenkins_url="$(prompt_default "Jenkins URL" "")"
    done
    # Remove trailing slash
    jenkins_url="${jenkins_url%/}"

    local agent_name
    agent_name="$(prompt_default "Agent name (node name in Jenkins)" "$(hostname)-agent")"

    local agent_secret
    agent_secret="$(prompt_secret "Agent secret")"
    while [[ -z "$agent_secret" ]]; do
        warn "Agent secret is required."
        agent_secret="$(prompt_secret "Agent secret")"
    done

    # ── Work Directory ───────────────────────────────────────────────────
    header "Step 3/5: Work Directory"

    local work_dir
    work_dir="$(prompt_default "Agent work directory" "$WORK_DIR")"
    work_dir="$(expand_home_path "$work_dir")"

    # ── Service Installation ─────────────────────────────────────────────
    header "Step 4/5: System Service"

    local install_service="n"
    if prompt_confirm "Install as a system service (auto-start on boot)?" "y"; then
        install_service="y"
    fi

    # ── Confirmation ─────────────────────────────────────────────────────
    header "Step 5/5: Confirmation"

    echo -e "  ${BOLD}OS:${NC}             ${OS_TYPE} (${ARCH})"
    echo -e "  ${BOLD}Java:${NC}           ${java_path}"
    echo -e "  ${BOLD}Jenkins URL:${NC}    ${jenkins_url}"
    echo -e "  ${BOLD}Agent Name:${NC}     ${agent_name}"
    echo -e "  ${BOLD}Agent Secret:${NC}   ${agent_secret:0:4}****${agent_secret: -4}"
    echo -e "  ${BOLD}Work Dir:${NC}       ${work_dir}"
    echo -e "  ${BOLD}Install Dir:${NC}    ${INSTALL_DIR}"
    echo -e "  ${BOLD}System Service:${NC} ${install_service}"
    echo ""

    if ! prompt_confirm "Proceed with installation?" "y"; then
        info "Installation cancelled."
        exit 0
    fi

    # ── Install ──────────────────────────────────────────────────────────
    header "Installing"

    # Create directories
    info "Creating directories..."
    mkdir -p "$INSTALL_DIR" "$work_dir" "$LOG_DIR"
    ensure_work_dir_owner "$work_dir" || exit 1

    # Download agent.jar
    local jnlp_url="${jenkins_url}/jnlpJars/agent.jar"
    info "Downloading agent.jar from ${jnlp_url}..."
    if command -v curl &>/dev/null; then
        curl -fsSL -o "$AGENT_JAR" "$jnlp_url"
    elif command -v wget &>/dev/null; then
        wget -q -O "$AGENT_JAR" "$jnlp_url"
    else
        error "Neither curl nor wget found. Cannot download agent.jar."
        exit 1
    fi
    success "Downloaded agent.jar"

    # Write configuration
    info "Writing configuration..."
    cat > "$CONF_FILE" <<EOF
# Jenkins Agent Configuration
# Generated on $(date -u +"%Y-%m-%dT%H:%M:%SZ")

JENKINS_URL="${jenkins_url}"
AGENT_NAME="${agent_name}"
AGENT_SECRET="${agent_secret}"
WORK_DIR="${work_dir}"
JAVA_PATH="${java_path}"
AGENT_JAR="${AGENT_JAR}"
LOG_DIR="${LOG_DIR}"
LOG_FILE="${LOG_FILE}"
PID_FILE="${PID_FILE}"
INSTALL_DIR="${INSTALL_DIR}"
SERVICE_INSTALLED="${install_service}"
EOF
    chmod 600 "$CONF_FILE"
    success "Configuration saved to ${CONF_FILE}"

    # Install CLI
    info "Installing jenkins-agent CLI..."
    install_cli "$OS_TYPE"

    # Install system service
    if [[ "$install_service" == "y" ]]; then
        info "Installing system service..."
        install_service "$OS_TYPE" "$agent_name" "$java_path" "$work_dir"
    fi

    # ── Done ─────────────────────────────────────────────────────────────
    header "Installation Complete!"

    echo -e "${GREEN}${BOLD}Jenkins agent has been installed successfully.${NC}"
    echo ""
    echo -e "  ${BOLD}Start the agent:${NC}"
    echo -e "    jenkins-agent run          ${CYAN}# foreground${NC}"
    echo -e "    jenkins-agent run -d       ${CYAN}# detached / background${NC}"
    echo ""
    echo -e "  ${BOLD}Other commands:${NC}"
    echo -e "    jenkins-agent stop         ${CYAN}# stop the agent${NC}"
    echo -e "    jenkins-agent status       ${CYAN}# check if running${NC}"
    echo -e "    jenkins-agent log          ${CYAN}# tail the log file${NC}"
    echo -e "    jenkins-agent configure    ${CYAN}# re-run configuration${NC}"
    echo ""
}

install_cli() {
    local os="$1"

    cat > /tmp/jenkins-agent-cli <<'CLIEOF'
#!/usr/bin/env bash
# ==============================================================================
# jenkins-agent — CLI wrapper for Jenkins agent
# ==============================================================================
set -euo pipefail

CONF_FILE="${HOME}/.jenkins-agent/agent.conf"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

usage() {
    cat <<EOF
${BOLD}jenkins-agent${NC} — Jenkins Agent Manager

${BOLD}USAGE${NC}
    jenkins-agent <command> [options]

${BOLD}COMMANDS${NC}
    run              Start the agent in the foreground
    run -d           Start the agent in detached (background) mode
    stop             Stop the agent
    status           Check if the agent is running
    update           Download the latest agent.jar from Jenkins
    log              Tail the agent log file
    configure        Re-run the configuration wizard
    uninstall        Remove the agent and all its files
    help             Show this help message

${BOLD}EXAMPLES${NC}
    jenkins-agent run           Start in foreground
    jenkins-agent run -d        Start as background daemon
    jenkins-agent stop          Stop all services
    jenkins-agent status        Check status
    jenkins-agent log           View logs
EOF
}

load_config() {
    if [[ ! -f "$CONF_FILE" ]]; then
        echo -e "${RED}[ERROR]${NC} Configuration not found at ${CONF_FILE}"
        echo -e "Run ${CYAN}jenkins-agent configure${NC} to set up the agent."
        exit 1
    fi
    source "$CONF_FILE"
}

cmd_run() {
    load_config
    check_work_dir_access || exit 1
    local detached=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--detached) detached=true; shift ;;
            *) shift ;;
        esac
    done

    if [[ "$detached" == "true" ]]; then
        cmd_run_detached
    else
        cmd_run_foreground
    fi
}

cmd_run_foreground() {
    # Check if already running
    if is_running; then
        echo -e "${YELLOW}[WARN]${NC}  Agent is already running (PID $(cat "$PID_FILE"))."
        echo -e "Use ${CYAN}jenkins-agent stop${NC} first, or ${CYAN}jenkins-agent run -d${NC} for detached mode."
        exit 1
    fi

    echo -e "${BLUE}[INFO]${NC}  Starting Jenkins agent '${AGENT_NAME}'..."
    echo -e "${BLUE}[INFO]${NC}  Connecting to ${JENKINS_URL}"
    echo -e "${BLUE}[INFO]${NC}  Press d or q to stop gracefully, or Ctrl+C to interrupt"
    echo ""

    local -a agent_args=(
        -jar "$AGENT_JAR"
        -url "$JENKINS_URL"
        -name "$AGENT_NAME"
        -secret "$AGENT_SECRET"
        -workDir "$WORK_DIR"
        -jar-cache "$WORK_DIR/remoting/jarCache"
        -webSocket
    )

    # Without a terminal, leave Java in the foreground as usual.
    if [[ ! -t 0 || ! -t 1 ]]; then
        "$JAVA_PATH" "${agent_args[@]}"
        return $?
    fi

    local old_stty agent_pid key
    old_stty="$(stty -g)"
    stty -echo -icanon

    "$JAVA_PATH" "${agent_args[@]}" </dev/null &
    agent_pid=$!

    # Restore terminal state and shut down Java cleanly if interrupted.
    trap 'stty "$old_stty" 2>/dev/null || true; kill -TERM "$agent_pid" 2>/dev/null || true; wait "$agent_pid" 2>/dev/null || true; exit 130' INT
    trap 'stty "$old_stty" 2>/dev/null || true; kill -TERM "$agent_pid" 2>/dev/null || true; wait "$agent_pid" 2>/dev/null || true; exit 143' TERM

    while kill -0 "$agent_pid" 2>/dev/null; do
        key=""
        if IFS= read -r -s -n 1 -t 0.2 key; then
            case "$key" in
                d|D|q|Q)
                    echo ""
                    info "Gracefully stopping Jenkins agent..."
                    kill -TERM "$agent_pid" 2>/dev/null || true
                    break
                    ;;
            esac
        fi
    done

    stty "$old_stty" 2>/dev/null || true
    trap - INT TERM
    wait "$agent_pid"
}

cmd_run_detached() {
    if is_running; then
        echo -e "${YELLOW}[WARN]${NC}  Agent is already running (PID $(cat "$PID_FILE"))."
        exit 0
    fi

    echo -e "${BLUE}[INFO]${NC}  Starting Jenkins agent '${AGENT_NAME}' in detached mode..."

    nohup "$JAVA_PATH" -jar "$AGENT_JAR" \
        -url "$JENKINS_URL" \
        -name "$AGENT_NAME" \
        -secret "$AGENT_SECRET" \
        -workDir "$WORK_DIR" \
        -jar-cache "$WORK_DIR/remoting/jarCache" \
        -webSocket \
        >> "$LOG_FILE" 2>&1 &

    local pid=$!
    echo "$pid" > "$PID_FILE"

    # Verify it started
    sleep 1
    if kill -0 "$pid" 2>/dev/null; then
        echo -e "${GREEN}[OK]${NC}    Agent started (PID ${pid})"
        echo -e "${BLUE}[INFO]${NC}  Logs: ${LOG_FILE}"
        echo -e "${BLUE}[INFO]${NC}  Stop: jenkins-agent stop"
    else
        echo -e "${RED}[ERROR]${NC} Agent failed to start. Check logs: jenkins-agent log"
        rm -f "$PID_FILE"
        exit 1
    fi
}

cmd_stop() {
    load_config

    local stopped=false

    # Stop service if installed
    if [[ "${SERVICE_INSTALLED:-n}" == "y" ]]; then
        if [[ "$(uname -s)" == "Linux" ]] && command -v systemctl &>/dev/null; then
            if systemctl is-active --quiet jenkins-agent 2>/dev/null; then
                echo -e "${BLUE}[INFO]${NC}  Stopping systemd service..."
                sudo systemctl stop jenkins-agent
                stopped=true
            fi
        elif [[ "$(uname -s)" == "Darwin" ]]; then
            if launchctl list | grep -q "com.jenkins.agent" 2>/dev/null; then
                echo -e "${BLUE}[INFO]${NC}  Stopping launchd service..."
                launchctl unload "${HOME}/Library/LaunchAgents/com.jenkins.agent.plist" 2>/dev/null || true
                stopped=true
            fi
        fi
    fi

    # Stop by PID
    if is_running; then
        local pid
        pid="$(cat "$PID_FILE")"
        echo -e "${BLUE}[INFO]${NC}  Stopping agent (PID ${pid})..."
        kill "$pid" 2>/dev/null || true

        # Wait for graceful shutdown
        local waited=0
        while kill -0 "$pid" 2>/dev/null && [[ $waited -lt 10 ]]; do
            sleep 1
            ((waited++))
        done

        # Force kill if still running
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${YELLOW}[WARN]${NC}  Graceful shutdown timed out, force killing..."
            kill -9 "$pid" 2>/dev/null || true
        fi

        rm -f "$PID_FILE"
        stopped=true
    fi

    # Kill any remaining agent.jar processes for this work dir
    pkill -f "agent.jar.*${AGENT_NAME:-}" 2>/dev/null || true

    if [[ "$stopped" == "true" ]]; then
        echo -e "${GREEN}[OK]${NC}    Jenkins agent stopped."
    else
        echo -e "${YELLOW}[WARN]${NC}  No running agent found."
    fi
}

cmd_status() {
    load_config

    if is_running; then
        local pid
        pid="$(cat "$PID_FILE")"
        echo -e "${GREEN}[OK]${NC}    Jenkins agent is running (PID ${pid})"
        echo -e "  Name:    ${AGENT_NAME}"
        echo -e "  URL:     ${JENKINS_URL}"
        echo -e "  Work:    ${WORK_DIR}"
    else
        echo -e "${YELLOW}[WARN]${NC}  Jenkins agent is not running."
    fi
}

cmd_log() {
    load_config
    if [[ -f "$LOG_FILE" ]]; then
        echo -e "${BLUE}[INFO]${NC}  Tailing ${LOG_FILE} (Ctrl+C to exit)..."
        tail -f "$LOG_FILE"
    else
        echo -e "${YELLOW}[WARN]${NC}  No log file found at ${LOG_FILE}"
    fi
}

cmd_update() {
    load_config

    echo -e "${BLUE}[INFO]${NC}  Downloading latest agent.jar from ${JENKINS_URL}..."

    local jnlp_url="${JENKINS_URL}/jnlpJars/agent.jar"
    local backup_jar="${AGENT_JAR}.bak"
    local was_running=false

    # Check if agent is running
    if is_running; then
        was_running=true
        echo -e "${YELLOW}[WARN]${NC}  Agent is running. Stopping temporarily..."
        cmd_stop
    fi

    # Backup current agent.jar
    if [[ -f "$AGENT_JAR" ]]; then
        cp "$AGENT_JAR" "$backup_jar"
    fi

    # Download new version
    if command -v curl &>/dev/null; then
        if curl -fsSL -o "${AGENT_JAR}.new" "$jnlp_url"; then
            mv "${AGENT_JAR}.new" "$AGENT_JAR"
            rm -f "$backup_jar"
            echo -e "${GREEN}[OK]${NC}    Updated agent.jar successfully"

            # Restart if was running
            if [[ "$was_running" == "true" ]]; then
                echo -e "${BLUE}[INFO]${NC}  Restarting agent..."
                cmd_run_detached
            fi
        else
            echo -e "${RED}[ERROR]${NC} Failed to download agent.jar"
            rm -f "${AGENT_JAR}.new"
            if [[ -f "$backup_jar" ]]; then
                mv "$backup_jar" "$AGENT_JAR"
            fi
            if [[ "$was_running" == "true" ]]; then
                cmd_run_detached
            fi
            exit 1
        fi
    elif command -v wget &>/dev/null; then
        if wget -q -O "${AGENT_JAR}.new" "$jnlp_url"; then
            mv "${AGENT_JAR}.new" "$AGENT_JAR"
            rm -f "$backup_jar"
            echo -e "${GREEN}[OK]${NC}    Updated agent.jar successfully"

            if [[ "$was_running" == "true" ]]; then
                echo -e "${BLUE}[INFO]${NC}  Restarting agent..."
                cmd_run_detached
            fi
        else
            echo -e "${RED}[ERROR]${NC} Failed to download agent.jar"
            rm -f "${AGENT_JAR}.new"
            if [[ -f "$backup_jar" ]]; then
                mv "$backup_jar" "$AGENT_JAR"
            fi
            if [[ "$was_running" == "true" ]]; then
                cmd_run_detached
            fi
            exit 1
        fi
    else
        echo -e "${RED}[ERROR]${NC} Neither curl nor wget found."
        exit 1
    fi
}

cmd_configure() {
    echo -e "${BLUE}[INFO]${NC}  Re-running installer configuration..."
    local installer="${INSTALL_DIR}/.installer/install.sh"
    if [[ -f "$installer" ]]; then
        bash "$installer"
    else
        echo -e "${RED}[ERROR]${NC} Installer script not found. Please re-download and run install.sh"
        exit 1
    fi
}

cmd_uninstall() {
    load_config
    echo -e "${YELLOW}[WARN]${NC}  This will remove the Jenkins agent and all its files."
    echo -en "${BOLD}Are you sure? [y/N]:${NC} "
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi

    # Stop first
    cmd_stop 2>/dev/null || true

    # Remove service
    if [[ "${SERVICE_INSTALLED:-n}" == "y" ]]; then
        if [[ "$(uname -s)" == "Linux" ]] && command -v systemctl &>/dev/null; then
            sudo systemctl disable jenkins-agent 2>/dev/null || true
            sudo rm -f /etc/systemd/system/jenkins-agent.service
            sudo systemctl daemon-reload
        elif [[ "$(uname -s)" == "Darwin" ]]; then
            rm -f "${HOME}/Library/LaunchAgents/com.jenkins.agent.plist"
        fi
    fi

    # Remove CLI
    sudo rm -f /usr/local/bin/jenkins-agent

    # Remove install directory
    rm -rf "$INSTALL_DIR"

    echo -e "${GREEN}[OK]${NC}    Jenkins agent has been uninstalled."
}

is_running() {
    [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

check_work_dir_access() {
    if [[ ! -d "$WORK_DIR" || ! -r "$WORK_DIR" || ! -w "$WORK_DIR" || ! -x "$WORK_DIR" ]]; then
        error "Agent work directory is not fully accessible: $WORK_DIR"
        info "The agent user needs read, write, and execute permissions on this directory."
        local owner
        owner="$(stat -f '%Su' "$WORK_DIR" 2>/dev/null || stat -c '%U' "$WORK_DIR" 2>/dev/null || true)"
        if [[ "$owner" == "root" ]]; then
            info "If this is the agent's dedicated directory, fix ownership with: sudo chown -R \"$(id -un)\" \"$WORK_DIR\""
        fi
        return 1
    fi
}

# ── Entry Point ──────────────────────────────────────────────────────────────
case "${1:-help}" in
    run)        shift; cmd_run "$@" ;;
    stop)       cmd_stop ;;
    status)     cmd_status ;;
    update)     cmd_update ;;
    log)        cmd_log ;;
    configure)  cmd_configure ;;
    uninstall)  cmd_uninstall ;;
    help|--help|-h) usage ;;
    *)
        echo -e "${RED}[ERROR]${NC} Unknown command: ${1:-}"
        usage
        exit 1
        ;;
esac
CLIEOF

    # Install the CLI
    if [[ "$os" == "macos" ]]; then
        if [[ -w "/usr/local/bin" ]]; then
            cp /tmp/jenkins-agent-cli "$CLI_PATH"
        else
            info "Requires sudo to install CLI to /usr/local/bin/"
            sudo cp /tmp/jenkins-agent-cli "$CLI_PATH"
        fi
    else
        if [[ -w "/usr/local/bin" ]]; then
            cp /tmp/jenkins-agent-cli "$CLI_PATH"
        else
            info "Requires sudo to install CLI to /usr/local/bin/"
            sudo cp /tmp/jenkins-agent-cli "$CLI_PATH"
        fi
    fi
    chmod +x "$CLI_PATH"
    rm -f /tmp/jenkins-agent-cli
    success "CLI installed to ${CLI_PATH}"
}

install_service() {
    local os="$1"
    local agent_name="$2"
    local java_path="$3"
    local work_dir="$4"

    if [[ "$os" == "linux" ]]; then
        install_systemd_service "$java_path" "$work_dir"
    elif [[ "$os" == "macos" ]]; then
        install_launchd_service "$java_path" "$work_dir"
    fi
}

install_systemd_service() {
    local java_path="$1"
    local work_dir="$2"
    local service_file="/etc/systemd/system/jenkins-agent.service"

    info "Installing systemd service..."

    local service_content
    service_content=$(cat <<EOF
[Unit]
Description=Jenkins Agent
After=network.target

[Service]
Type=simple
User=$(whoami)
Group=$(id -gn)
WorkingDirectory=${work_dir}
ExecStart=${java_path} -jar ${AGENT_JAR} -url \${JENKINS_URL} -name \${AGENT_NAME} -secret \${AGENT_SECRET} -workDir ${work_dir} -jar-cache ${work_dir}/remoting/jarCache -webSocket
Restart=on-failure
RestartSec=10
StandardOutput=append:${LOG_FILE}
StandardError=append:${LOG_FILE}
EnvironmentFile=${CONF_FILE}

[Install]
WantedBy=multi-user.target
EOF
)

    echo "$service_content" | sudo tee "$service_file" > /dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable jenkins-agent
    success "systemd service installed and enabled"
}

install_launchd_service() {
    local java_path="$1"
    local work_dir="$2"
    local plist_dir="${HOME}/Library/LaunchAgents"
    local plist_file="${plist_dir}/com.jenkins.agent.plist"

    info "Installing launchd service..."
    mkdir -p "$plist_dir"

    cat > "$plist_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.jenkins.agent</string>

    <key>ProgramArguments</key>
    <array>
        <string>${java_path}</string>
        <string>-jar</string>
        <string>${AGENT_JAR}</string>
        <string>-url</string>
        <string>__JENKINS_URL__</string>
        <string>-name</string>
        <string>__AGENT_NAME__</string>
        <string>-secret</string>
        <string>__AGENT_SECRET__</string>
        <string>-workDir</string>
        <string>${work_dir}</string>
        <string>-jar-cache</string>
        <string>${work_dir}/remoting/jarCache</string>
        <string>-webSocket</string>
    </array>

    <key>RunAtLoad</key>
    <false/>

    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>

    <key>StandardOutPath</key>
    <string>${LOG_FILE}</string>
    <key>StandardErrorPath</key>
    <string>${LOG_FILE}</string>

    <key>WorkingDirectory</key>
    <string>${work_dir}</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>JENKINS_URL</key>
        <string>__JENKINS_URL__</string>
        <key>AGENT_NAME</key>
        <string>__AGENT_NAME__</string>
        <key>AGENT_SECRET</key>
        <string>__AGENT_SECRET__</string>
    </dict>
</dict>
</plist>
EOF

    # Substitute actual values
    source "$CONF_FILE"
    sed -i '' "s|__JENKINS_URL__|${JENKINS_URL}|g" "$plist_file"
    sed -i '' "s|__AGENT_NAME__|${AGENT_NAME}|g" "$plist_file"
    sed -i '' "s|__AGENT_SECRET__|${AGENT_SECRET}|g" "$plist_file"

    success "launchd service installed to ${plist_file}"
    info "To enable auto-start: launchctl load ${plist_file}"
}

# ── Run ──────────────────────────────────────────────────────────────────────
main "$@"
