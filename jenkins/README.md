# Jenkins Agent Installer

[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-blue)]()
[![Jenkins](https://img.shields.io/badge/jenkins-agent-blue)]()
[![Java](https://img.shields.io/badge/java-11%2B-orange)]()

Cross-platform installer for setting up a Jenkins agent (node/runner) on **Linux**, **macOS**, and **Windows**.

## ✨ Features

- 🖥️ **Cross-platform** – Works on Linux, macOS, and Windows
- 🧙 **Interactive setup** – Guided prompts for all configuration
- ☕ **Auto-detects Java** – Finds your Java installation automatically
- 🔧 **CLI management** – Simple `jenkins-agent` command for all operations
- 🔄 **Service integration** – Optional auto-start via systemd/launchd/Windows service
- 📝 **Logging** – Built-in log management and monitoring
- 🔐 **Secure** – Stores secrets with restricted file permissions

## 📋 Table of Contents

- [Quick Start](#-quick-start)
- [Usage](#-usage)
- [Configuration](#-configuration)
- [What Gets Installed](#-what-gets-installed)
- [Platform-Specific Notes](#-platform-specific-notes)
- [Troubleshooting](#-troubleshooting)
- [Uninstalling](#-uninstalling)
- [Development](#-development)

## 🚀 Quick Start

### Prerequisites

Before installing, ensure you have:

1. **Java 11 or higher** installed
   ```bash
   java -version
   ```

2. **Jenkins node credentials**
   - Go to your Jenkins instance
   - Navigate to: `Manage Jenkins` → `Nodes` → `New Node` (or select existing)
   - Configure the node and note the **Agent name** and **Secret**

3. **Internet access** to download `agent.jar` from your Jenkins instance

### Installation

#### Linux / macOS

```bash
chmod +x install.sh
./install.sh
```

The installer will:
- Detect your OS and architecture
- Find or ask for Java path
- Prompt for Jenkins URL, agent name, and secret
- Download the agent JAR
- Install the `jenkins-agent` CLI
- Optionally set up a system service

#### Windows (PowerShell)

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\install.ps1
```

Follow the interactive prompts to complete the installation.

## 📖 Usage

After installation, use the `jenkins-agent` command:

### Basic Commands

```bash
# Start in foreground (see output directly)
jenkins-agent run

# Start in detached/background mode
jenkins-agent run -d

# Stop the agent
jenkins-agent stop

# Check status
jenkins-agent status
```

### All Available Commands

| Command | Description |
|---------|-------------|
| `jenkins-agent run` | Start the agent in the **foreground** |
| `jenkins-agent run -d` | Start the agent in **detached** (background) mode |
| `jenkins-agent stop` | Stop the agent and all services |
| `jenkins-agent status` | Check if the agent is running |
| `jenkins-agent log` | Tail the agent log file |
| `jenkins-agent configure` | Re-run the configuration wizard |
| `jenkins-agent update` | Download the latest agent.jar from Jenkins |
| `jenkins-agent uninstall` | Remove the agent and all its files |
| `jenkins-agent help` | Show help message |

### Examples

**Start agent and watch output:**
```bash
jenkins-agent run
# Press Ctrl+C to stop
```

**Start as background daemon:**
```bash
jenkins-agent run -d
# Agent runs in background, check status with:
jenkins-agent status
```

**View logs in real-time:**
```bash
jenkins-agent log
# Press Ctrl+C to exit
```

**Check if running:**
```bash
jenkins-agent status
# Shows: [OK] Jenkins agent is running (PID 12345)
# Or: [WARN] Jenkins agent is not running.
```

## ⚙️ Configuration

### Interactive Setup

The installer prompts for:

| Setting | Description | Example |
|---------|-------------|---------|
| **Jenkins URL** | Your Jenkins instance URL | `http://jenkins.example.com:8080` |
| **Agent Name** | Node name in Jenkins | `build-agent-01` |
| **Agent Secret** | Secret from Jenkins node config | `abc123def456...` |
| **Work Directory** | Where agent stores workspace | `~/.jenkins-agent/work` |
| **Java Path** | Path to Java executable | `/usr/bin/java` |
| **Install as service** | Auto-start on boot | `y/n` |

### Configuration File

Settings are stored in `agent.conf`:

**Linux/macOS:** `~/.jenkins-agent/agent.conf`  
**Windows:** `%USERPROFILE%\.jenkins-agent\agent.conf`

```bash
# Example agent.conf
JENKINS_URL=http://jenkins.example.com:8080
AGENT_NAME=build-agent-01
AGENT_SECRET=abc123def456ghi789
WORK_DIR=/home/user/.jenkins-agent/work
JAVA_PATH=/usr/bin/java
AGENT_JAR=/home/user/.jenkins-agent/agent.jar
LOG_DIR=/home/user/.jenkins-agent/logs
LOG_FILE=/home/user/.jenkins-agent/logs/agent.log
PID_FILE=/home/user/.jenkins-agent/agent.pid
INSTALL_DIR=/home/user/.jenkins-agent
SERVICE_INSTALLED=y
```

⚠️ **Security Note:** The config file contains your agent secret. It's created with restricted permissions (600 on Unix).

### Reconfigure

To change settings after installation:

```bash
jenkins-agent configure
```

This re-runs the installer and updates the configuration.

## 📂 What Gets Installed

| Component | Linux | macOS | Windows |
|-----------|-------|-------|---------|
| **Agent JAR** | `~/.jenkins-agent/agent.jar` | `~/.jenkins-agent/agent.jar` | `%USERPROFILE%\.jenkins-agent\agent.jar` |
| **Config** | `~/.jenkins-agent/agent.conf` | `~/.jenkins-agent/agent.conf` | `%USERPROFILE%\.jenkins-agent\agent.conf` |
| **PID file** | `~/.jenkins-agent/agent.pid` | `~/.jenkins-agent/agent.pid` | `%USERPROFILE%\.jenkins-agent\agent.pid` |
| **Logs** | `~/.jenkins-agent/logs/` | `~/.jenkins-agent/logs/` | `%USERPROFILE%\.jenkins-agent\logs\` |
| **CLI** | `/usr/local/bin/jenkins-agent` | `/usr/local/bin/jenkins-agent` | `%USERPROFILE%\.jenkins-agent\jenkins-agent.ps1` |
| **Service** | systemd unit | launchd plist | Windows service |

### Directory Structure

```
~/.jenkins-agent/
├── agent.jar              # Jenkins agent JAR file
├── agent.conf             # Configuration (contains secrets!)
├── agent.pid              # Process ID when running
├── jenkins-agent.ps1      # Windows CLI wrapper
├── jenkins-agent.bat      # Windows batch launcher
├── work/                  # Workspace and build data
│   └── (Jenkins workspaces)
└── logs/
    └── agent.log          # Agent logs
```

## 💻 Platform-Specific Notes

### Linux

**Service Management (systemd):**

```bash
# Check service status
sudo systemctl status jenkins-agent

# Start/stop/restart service
sudo systemctl start jenkins-agent
sudo systemctl stop jenkins-agent
sudo systemctl restart jenkins-agent

# Enable/disable auto-start
sudo systemctl enable jenkins-agent
sudo systemctl disable jenkins-agent

# View service logs
sudo journalctl -u jenkins-agent -f
```

**Permissions:**
- Requires `sudo` for CLI installation to `/usr/local/bin/`
- Requires `sudo` for systemd service installation

### macOS

**Service Management (launchd):**

```bash
# Load service (enable auto-start)
launchctl load ~/Library/LaunchAgents/com.jenkins.agent.plist

# Unload service
launchctl unload ~/Library/LaunchAgents/com.jenkins.agent.plist

# Check if loaded
launchctl list | grep com.jenkins.agent
```

**Permissions:**
- Requires `sudo` for CLI installation to `/usr/local/bin/`
- No `sudo` needed for launchd service (user-level)

### Windows

**Service Management:**

```powershell
# Start/stop service (requires Administrator)
net start jenkins-agent
net stop jenkins-agent

# Check service status
Get-Service jenkins-agent

# Or use Services GUI
services.msc
```

**PATH:**
- The installer adds `%USERPROFILE%\.jenkins-agent` to your user PATH
- Restart your terminal after installation to use `jenkins-agent` command

**Alternative Usage:**
```powershell
# If not in PATH, use full path
& "$env:USERPROFILE\.jenkins-agent\jenkins-agent.ps1" run

# Or use the batch launcher
& "$env:USERPROFILE\.jenkins-agent\jenkins-agent.bat" run
```

## 🔧 Troubleshooting

### Agent won't start

**Check logs:**
```bash
jenkins-agent log
```

**Common issues:**

1. **Java not found**
   ```bash
   # Verify Java installation
   java -version
   
   # Reconfigure with correct path
   jenkins-agent configure
   ```

2. **Connection refused**
   - Verify Jenkins URL is accessible
   - Check firewall settings
   - Ensure agent name and secret are correct

3. **Port already in use**
   - Check if another agent is running: `jenkins-agent status`
   - Stop existing agent: `jenkins-agent stop`

### Agent disconnects frequently

**Check network stability:**
```bash
# Ping Jenkins server
ping jenkins.example.com

# Check logs for connection errors
jenkins-agent log
```

**Increase JVM heap (if memory issues):**
Edit the CLI script to add JVM options:
```bash
# In the CLI script, modify the java command:
java -Xmx512m -jar agent.jar ...
```

### Permission denied (Linux/macOS)

```bash
# Fix CLI permissions
sudo chmod +x /usr/local/bin/jenkins-agent

# Fix config file permissions
chmod 600 ~/.jenkins-agent/agent.conf
```

### Windows execution policy

```powershell
# Allow script execution for current user
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned

# Or run with bypass (temporary)
powershell -ExecutionPolicy Bypass -File jenkins-agent.ps1 run
```

### Agent shows offline in Jenkins

1. Check if agent process is running: `jenkins-agent status`
2. Verify Jenkins URL and credentials: `jenkins-agent configure`
3. Check Jenkins logs on the master
4. Verify network connectivity between agent and master

### Logs location

**Linux/macOS:**
```bash
~/.jenkins-agent/logs/agent.log
```

**Windows:**
```powershell
%USERPROFILE%\.jenkins-agent\logs\agent.log
```

## 🗑️ Uninstalling

### Using CLI

```bash
jenkins-agent uninstall
```

This will:
- Stop the agent if running
- Remove system service (if installed)
- Delete all files in `~/.jenkins-agent/`
- Remove CLI from `/usr/local/bin/` (Unix)

### Manual Uninstall

**Linux/macOS:**
```bash
# Stop agent
jenkins-agent stop

# Remove service (if installed)
sudo systemctl disable jenkins-agent
sudo rm /etc/systemd/system/jenkins-agent.service
sudo systemctl daemon-reload

# Remove CLI
sudo rm /usr/local/bin/jenkins-agent

# Remove all files
rm -rf ~/.jenkins-agent
```

**Windows:**
```powershell
# Stop agent
jenkins-agent stop

# Remove service (if installed, requires Administrator)
sc.exe delete jenkins-agent

# Remove all files
Remove-Item -Recurse -Force "$env:USERPROFILE\.jenkins-agent"

# Remove from PATH (optional)
# Edit System Environment Variables
```

## 🔒 Security Considerations

1. **Agent Secret**: The configuration file contains your agent secret. It's created with restricted permissions (600 on Unix), but treat it like a password.

2. **Network**: The agent connects to Jenkins over HTTP/HTTPS. Use HTTPS in production environments.

3. **Work Directory**: The work directory contains Jenkins workspaces and build artifacts. Ensure appropriate filesystem permissions.

4. **Service Account**: On production systems, consider running the agent service under a dedicated service account rather than your user account.

## 🛠️ Development

### Project Structure

```
jenkins/
├── README.md              # This file
├── install.sh             # Linux/macOS installer (717 lines)
└── install.ps1            # Windows installer (555 lines)
```

### Testing Locally

1. **Set up a local Jenkins instance** (Docker):
   ```bash
   docker run -p 8080:8080 -p 50000:50000 jenkins/jenkins:lts
   ```

2. **Create a test node** in Jenkins UI

3. **Run the installer**:
   ```bash
   ./install.sh
   # Use http://localhost:8080 as Jenkins URL
   ```

4. **Test all commands**:
   ```bash
   jenkins-agent run
   jenkins-agent run -d
   jenkins-agent status
   jenkins-agent stop
   jenkins-agent log
   ```

## 📝 License

This installer script is provided as-is for setting up Jenkins agents.

## 🤝 Contributing

Contributions are welcome! Areas for improvement:
- Additional OS support (FreeBSD, etc.)
- Better error handling and validation
- Support for SSH-based agents (not just JNLP)
- Configuration file encryption
- Multiple agent support on same machine

## 📞 Support

For issues related to:
- **This installer**: Check the [Troubleshooting](#-troubleshooting) section
- **Jenkins itself**: Visit [jenkins.io](https://www.jenkins.io/)
- **Java issues**: Check your JRE/JDK installation

---

**Made with ❤️ for Jenkins users everywhere**
