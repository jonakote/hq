#Requires -Version 5.1
# ==============================================================================
# Jenkins Agent Installer — Windows
# ==============================================================================
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# ── Constants ────────────────────────────────────────────────────────────────
$InstallDir  = Join-Path $env:USERPROFILE ".jenkins-agent"
$WorkDir     = Join-Path $InstallDir "work"
$LogDir      = Join-Path $InstallDir "logs"
$ConfFile    = Join-Path $InstallDir "agent.conf"
$PidFile     = Join-Path $InstallDir "agent.pid"
$LogFile     = Join-Path $LogDir "agent.log"
$AgentJar    = Join-Path $InstallDir "agent.jar"
$CliScript   = Join-Path $InstallDir "jenkins-agent.ps1"

# ── Helpers ──────────────────────────────────────────────────────────────────
function Write-Info    { param($Msg) Write-Host "[INFO]  " -ForegroundColor Blue    -NoNewline; Write-Host " $Msg" }
function Write-Ok      { param($Msg) Write-Host "[OK]    " -ForegroundColor Green   -NoNewline; Write-Host " $Msg" }
function Write-Warn    { param($Msg) Write-Host "[WARN]  " -ForegroundColor Yellow  -NoNewline; Write-Host " $Msg" }
function Write-Err     { param($Msg) Write-Host "[ERROR] " -ForegroundColor Red     -NoNewline; Write-Host " $Msg" }
function Write-Header  { param($Msg) Write-Host "`n━━━ $Msg ━━━`n" -ForegroundColor Cyan }

function Get-Input {
    param(
        [string]$Prompt,
        [string]$Default = "",
        [switch]$Secret
    )
    if ($Default) {
        Write-Host "$Prompt " -NoNewline
        Write-Host "[$Default]" -ForegroundColor Green -NoNewline
        Write-Host ": " -NoNewline
    } else {
        Write-Host "$Prompt: " -NoNewline
    }

    if ($Secret) {
        $input = Read-Host -AsSecureString
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($input)
        $value = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    } else {
        $value = Read-Host
    }

    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value.Trim()
}

function Confirm-Action {
    param([string]$Prompt, [string]$Default = "N")

    $options = "[y/N]"
    if ($Default -eq "Y") { $options = "[Y/n]" }

    Write-Host "$Prompt " -NoNewline
    Write-Host "$options " -ForegroundColor Yellow -NoNewline
    Write-Host ": " -NoNewline

    $answer = Read-Host
    if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $Default }
    return $answer -match '^[Yy]'
}

function Find-Java {
    # 1. JAVA_HOME
    if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME "bin\java.exe"))) {
        return Join-Path $env:JAVA_HOME "bin\java.exe"
    }

    # 2. PATH
    $javaCmd = Get-Command "java" -ErrorAction SilentlyContinue
    if ($javaCmd) {
        try {
            & $javaCmd.Path -version 2>&1 | Out-Null
            return $javaCmd.Path
        } catch {}
    }

    # 3. Common locations
    $paths = @(
        "C:\Program Files\Java\*\bin\java.exe",
        "C:\Program Files (x86)\Java\*\bin\java.exe",
        "C:\Program Files\Eclipse Adoptium\*\bin\java.exe",
        "C:\Program Files\Microsoft\jdk-*\bin\java.exe",
        "C:\Program Files\AdoptOpenJDK\*\bin\java.exe",
        "C:\Program Files\Zulu\*\bin\java.exe"
    )
    foreach ($pattern in $paths) {
        $found = Get-Item $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return $found.FullName }
    }

    return $null
}

function Get-JavaVersion {
    param([string]$JavaPath)
    try {
        $output = & $JavaPath -version 2>&1 | Select-Object -First 1
        return $output
    } catch {
        return "unknown"
    }
}

# ── Main Installer ───────────────────────────────────────────────────────────
function Install-JenkinsAgent {
    Write-Header "Jenkins Agent Installer (Windows)"
    Write-Host "  OS:           " -NoNewline; Write-Host "Windows ($([System.Environment]::OSVersion.Version))"
    Write-Host "  Architecture: " -NoNewline; Write-Host "$([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)"
    Write-Host "  Install dir:  " -NoNewline; Write-Host "$InstallDir"
    Write-Host ""

    # ── Step 1: Java ─────────────────────────────────────────────────────
    Write-Header "Step 1/5: Java Runtime"

    $detectedJava = Find-Java
    if ($detectedJava) {
        $javaVer = Get-JavaVersion $detectedJava
        Write-Ok "Found Java: $detectedJava"
        Write-Info "Version: $javaVer"
    } else {
        Write-Warn "No Java runtime found on this system."
        if (-not (Confirm-Action "Do you have Java installed at a custom path?" "N")) {
            Write-Err "Java is required. Please install a JRE/JDK 11+ and try again."
            Write-Host "  Download: https://adoptium.net/"
            exit 1
        }
    }

    $javaPath = Get-Input "Java executable path" $detectedJava

    if (-not (Test-Path $javaPath)) {
        Write-Warn "Java path '$javaPath' does not appear valid."
        if (-not (Confirm-Action "Continue anyway?" "N")) { exit 1 }
    }

    # ── Step 2: Jenkins Connection ───────────────────────────────────────
    Write-Header "Step 2/5: Jenkins Connection"
    Write-Host "These details are found on the Jenkins node configuration page." -ForegroundColor Yellow
    Write-Host "Go to: Manage Jenkins -> Nodes -> <Your Node> -> Configure"     -ForegroundColor Yellow
    Write-Host ""

    $jenkinsUrl = Get-Input "Jenkins URL (e.g. http://jenkins.example.com:8080)"
    while ([string]::IsNullOrWhiteSpace($jenkinsUrl)) {
        Write-Warn "Jenkins URL is required."
        $jenkinsUrl = Get-Input "Jenkins URL"
    }
    $jenkinsUrl = $jenkinsUrl.TrimEnd('/')

    $defaultName = "$env:COMPUTERNAME-agent"
    $agentName = Get-Input "Agent name (node name in Jenkins)" $defaultName

    $agentSecret = Get-Input "Agent secret" -Secret
    while ([string]::IsNullOrWhiteSpace($agentSecret)) {
        Write-Warn "Agent secret is required."
        $agentSecret = Get-Input "Agent secret" -Secret
    }

    # ── Step 3: Work Directory ───────────────────────────────────────────
    Write-Header "Step 3/5: Work Directory"
    $workDir = Get-Input "Agent work directory" $WorkDir

    # ── Step 4: Service ──────────────────────────────────────────────────
    Write-Header "Step 4/5: System Service"
    $installService = Confirm-Action "Install as a Windows service (auto-start on boot)?" "Y"

    # ── Step 5: Confirmation ─────────────────────────────────────────────
    Write-Header "Step 5/5: Confirmation"

    Write-Host "  Java:           $javaPath"
    Write-Host "  Jenkins URL:    $jenkinsUrl"
    Write-Host "  Agent Name:     $agentName"
    Write-Host "  Agent Secret:   $($agentSecret.Substring(0, [Math]::Min(4, $agentSecret.Length))))****$($agentSecret.Substring([Math]::Max(0, $agentSecret.Length - 4)))"
    Write-Host "  Work Dir:       $workDir"
    Write-Host "  Install Dir:    $InstallDir"
    Write-Host "  System Service: $installService"
    Write-Host ""

    if (-not (Confirm-Action "Proceed with installation?" "Y")) {
        Write-Info "Installation cancelled."
        exit 0
    }

    # ── Install ──────────────────────────────────────────────────────────
    Write-Header "Installing"

    # Create directories
    Write-Info "Creating directories..."
    @($InstallDir, $WorkDir, $LogDir) | ForEach-Object {
        if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
    }

    # Download agent.jar
    $jnlpUrl = "$jenkinsUrl/jnlpJars/agent.jar"
    Write-Info "Downloading agent.jar from $jnlpUrl..."
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $jnlpUrl -OutFile $AgentJar -UseBasicParsing
    } catch {
        Write-Err "Failed to download agent.jar: $_"
        exit 1
    }
    Write-Ok "Downloaded agent.jar"

    # Write configuration
    Write-Info "Writing configuration..."
    $confContent = @"
# Jenkins Agent Configuration
# Generated on $(Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")

JENKINS_URL=$jenkinsUrl
AGENT_NAME=$agentName
AGENT_SECRET=$agentSecret
WORK_DIR=$workDir
JAVA_PATH=$javaPath
AGENT_JAR=$AgentJar
LOG_DIR=$LogDir
LOG_FILE=$LogFile
PID_FILE=$PidFile
INSTALL_DIR=$InstallDir
SERVICE_INSTALLED=$($installService.ToString().ToLower())
"@
    Set-Content -Path $ConfFile -Value $confContent -Encoding UTF8
    Write-Ok "Configuration saved to $ConfFile"

    # Install CLI wrapper
    Write-Info "Installing jenkins-agent CLI..."
    Install-CLIWrapper

    # Install Windows service
    if ($installService) {
        Write-Info "Installing Windows service..."
        Install-WindowsService $javaPath
    }

    # ── Done ─────────────────────────────────────────────────────────────
    Write-Header "Installation Complete!"
    Write-Host "Jenkins agent has been installed successfully." -ForegroundColor Green
    Write-Host ""
    Write-Host "  Start the agent:" -ForegroundColor White
    Write-Host "    jenkins-agent run          # foreground" -ForegroundColor Cyan
    Write-Host "    jenkins-agent run -d       # detached / background" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Other commands:" -ForegroundColor White
    Write-Host "    jenkins-agent stop         # stop the agent" -ForegroundColor Cyan
    Write-Host "    jenkins-agent status       # check if running" -ForegroundColor Cyan
    Write-Host "    jenkins-agent log          # tail the log file" -ForegroundColor Cyan
    Write-Host "    jenkins-agent configure    # re-run configuration" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  NOTE: You may need to add $InstallDir to your PATH" -ForegroundColor Yellow
    Write-Host "    or create an alias: jenkins-agent -> $CliScript" -ForegroundColor Yellow
}

function Install-CLIWrapper {
    # Generate the PowerShell CLI wrapper
    $cliContent = @'
#Requires -Version 5.1
# ==============================================================================
# jenkins-agent — Jenkins Agent CLI (Windows)
# ==============================================================================
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command = "help",

    [Parameter(Position = 1)]
    [string]$Arg1 = "",

    [switch]$d
)

$ErrorActionPreference = "Stop"

$InstallDir = Join-Path $env:USERPROFILE ".jenkins-agent"
$ConfFile   = Join-Path $InstallDir "agent.conf"

function Write-Info  { param($Msg) Write-Host "[INFO]  " -ForegroundColor Blue    -NoNewline; Write-Host " $Msg" }
function Write-Ok    { param($Msg) Write-Host "[OK]    " -ForegroundColor Green   -NoNewline; Write-Host " $Msg" }
function Write-Warn  { param($Msg) Write-Host "[WARN]  " -ForegroundColor Yellow  -NoNewline; Write-Host " $Msg" }
function Write-Err   { param($Msg) Write-Host "[ERROR] " -ForegroundColor Red     -NoNewline; Write-Host " $Msg" }

function Show-Usage {
    Write-Host "jenkins-agent — Jenkins Agent Manager" -ForegroundColor White
    Write-Host ""
    Write-Host "USAGE" -ForegroundColor White
    Write-Host "    jenkins-agent <command> [options]"
    Write-Host ""
    Write-Host "COMMANDS" -ForegroundColor White
    Write-Host "    run              Start the agent in the foreground"
    Write-Host "    run -d           Start the agent in detached (background) mode"
    Write-Host "    stop             Stop the agent"
    Write-Host "    status           Check if the agent is running"
    Write-Host "    update           Download the latest agent.jar from Jenkins"
    Write-Host "    log              Tail the agent log file"
    Write-Host "    configure        Re-run the configuration wizard"
    Write-Host "    uninstall        Remove the agent and all its files"
    Write-Host "    help             Show this help message"
}

function Load-Config {
    if (-not (Test-Path $ConfFile)) {
        Write-Err "Configuration not found at $ConfFile"
        Write-Host "Run 'jenkins-agent configure' to set up the agent."
        exit 1
    }
    $config = @{}
    Get-Content $ConfFile | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
            $config[$matches[1].Trim()] = $matches[2].Trim()
        }
    }
    return $config
}

function Test-Running {
    param($PidFile)
    if (Test-Path $PidFile) {
        $pid = Get-Content $PidFile
        try {
            $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
            if ($proc) { return $true }
        } catch {}
        Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
    }
    return $false
}

function Invoke-Run {
    $config = Load-Config
    $detached = ($Command -eq "run") -and ($d -or $Arg1 -eq "-d" -or $Arg1 -eq "--detached")

    if ($detached) {
        if (Test-Running $config.PID_FILE) {
            Write-Warn "Agent is already running (PID $(Get-Content $config.PID_FILE))."
            return
        }

        Write-Info "Starting Jenkins agent '$($config.AGENT_NAME)' in detached mode..."

        $process = Start-Process -FilePath $config.JAVA_PATH `
            -ArgumentList "-jar `"$($config.AGENT_JAR)`" -jnlpUrl `"$($config.JENKINS_URL)/computer/$($config.AGENT_NAME)/jenkins-agent.jnlp`" -secret `"$($config.AGENT_SECRET)`" -workDir `"$($config.WORK_DIR)`" -webSocket" `
            -RedirectStandardOutput $config.LOG_FILE `
            -RedirectStandardError (Join-Path $config.LOG_DIR "agent-error.log") `
            -WindowStyle Hidden `
            -PassThru

        $process.Id | Set-Content $config.PID_FILE
        Start-Sleep -Seconds 2

        if (-not $process.HasExited) {
            Write-Ok "Agent started (PID $($process.Id))"
            Write-Info "Logs: $($config.LOG_FILE)"
            Write-Info "Stop: jenkins-agent stop"
        } else {
            Write-Err "Agent failed to start. Check logs: jenkins-agent log"
            Remove-Item $config.PID_FILE -Force -ErrorAction SilentlyContinue
        }
    } else {
        if (Test-Running $config.PID_FILE) {
            Write-Warn "Agent is already running (PID $(Get-Content $config.PID_FILE))."
            return
        }

        Write-Info "Starting Jenkins agent '$($config.AGENT_NAME)'..."
        Write-Info "Connecting to $($config.JENKINS_URL)"
        Write-Info "Press Ctrl+C to stop"
        Write-Host ""

        & $config.JAVA_PATH -jar $config.AGENT_JAR `
            -jnlpUrl "$($config.JENKINS_URL)/computer/$($config.AGENT_NAME)/jenkins-agent.jnlp" `
            -secret $config.AGENT_SECRET `
            -workDir $config.WORK_DIR `
            -webSocket
    }
}

function Invoke-Stop {
    $config = Load-Config
    $stopped = $false

    # Stop Windows service if installed
    if ($config.SERVICE_INSTALLED -eq "true") {
        $svc = Get-Service -Name "jenkins-agent" -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq "Running") {
            Write-Info "Stopping Windows service..."
            Stop-Service -Name "jenkins-agent" -Force
            $stopped = $true
        }
    }

    # Stop by PID
    if (Test-Running $config.PID_FILE) {
        $pid = Get-Content $config.PID_FILE
        Write-Info "Stopping agent (PID $pid)..."
        try {
            Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
            $stopped = $true
        } catch {}
        Remove-Item $config.PID_FILE -Force -ErrorAction SilentlyContinue
    }

    # Kill any remaining agent.jar processes
    Get-Process -Name "java" -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -like "*agent.jar*$($config.AGENT_NAME)*"
    } | Stop-Process -Force -ErrorAction SilentlyContinue

    if ($stopped) {
        Write-Ok "Jenkins agent stopped."
    } else {
        Write-Warn "No running agent found."
    }
}

function Invoke-Status {
    $config = Load-Config
    if (Test-Running $config.PID_FILE) {
        $pid = Get-Content $config.PID_FILE
        Write-Ok "Jenkins agent is running (PID $pid)"
        Write-Host "  Name:    $($config.AGENT_NAME)"
        Write-Host "  URL:     $($config.JENKINS_URL)"
        Write-Host "  Work:    $($config.WORK_DIR)"
    } else {
        Write-Warn "Jenkins agent is not running."
    }
}

function Invoke-Update {
    $config = Load-Config
    $jnlpUrl = "$($config.JENKINS_URL)/jnlpJars/agent.jar"
    
    Write-Info "Downloading latest agent.jar from $jnlpUrl..."
    
    $backupJar = "$($config.AGENT_JAR).bak"
    $wasRunning = $false
    
    # Check if agent is running
    if (Test-Running $config.PID_FILE) {
        $wasRunning = $true
        Write-Warn "Agent is running. Stopping temporarily..."
        Invoke-Stop
    }
    
    # Backup current agent.jar
    if (Test-Path $config.AGENT_JAR) {
        Copy-Item $config.AGENT_JAR $backupJar -Force
    }
    
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $jnlpUrl -OutFile "$($config.AGENT_JAR).new" -UseBasicParsing
        Move-Item "$($config.AGENT_JAR).new" $config.AGENT_JAR -Force
        Remove-Item $backupJar -Force -ErrorAction SilentlyContinue
        Write-Ok "Updated agent.jar successfully"
        
        # Restart if was running
        if ($wasRunning) {
            Write-Info "Restarting agent..."
            $Command = "run"
            $d = $true
            Invoke-Run
        }
    } catch {
        Write-Err "Failed to download agent.jar: $_"
        Remove-Item "$($config.AGENT_JAR).new" -Force -ErrorAction SilentlyContinue
        if (Test-Path $backupJar) {
            Move-Item $backupJar $config.AGENT_JAR -Force
        }
        if ($wasRunning) {
            $Command = "run"
            $d = $true
            Invoke-Run
        }
        exit 1
    }
}

function Invoke-Log {
    $config = Load-Config
    if (Test-Path $config.LOG_FILE) {
        Write-Info "Tailing $($config.LOG_FILE) (Ctrl+C to exit)..."
        Get-Content $config.LOG_FILE -Wait -Tail 50
    } else {
        Write-Warn "No log file found at $($config.LOG_FILE)"
    }
}

function Invoke-Configure {
    Write-Info "Re-running installer..."
    $installer = Join-Path $InstallDir ".installer\install.ps1"
    if (Test-Path $installer) {
        & $installer
    } else {
        Write-Err "Installer script not found. Please re-download and run install.ps1"
        exit 1
    }
}

function Invoke-Uninstall {
    $config = Load-Config
    Write-Warn "This will remove the Jenkins agent and all its files."
    if (-not (Confirm-Action "Are you sure?" "N")) { exit 0 }

    # Stop first
    try { Invoke-Stop } catch {}

    # Remove service
    if ($config.SERVICE_INSTALLED -eq "true") {
        $svc = Get-Service -Name "jenkins-agent" -ErrorAction SilentlyContinue
        if ($svc) {
            Stop-Service -Name "jenkins-agent" -Force -ErrorAction SilentlyContinue
            sc.exe delete "jenkins-agent" | Out-Null
        }
    }

    # Remove install directory
    Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue

    Write-Ok "Jenkins agent has been uninstalled."
}

# ── Entry Point ──────────────────────────────────────────────────────────────
switch ($Command.ToLower()) {
    "run"         { Invoke-Run }
    "stop"        { Invoke-Stop }
    "status"      { Invoke-Status }
    "update"      { Invoke-Update }
    "log"         { Invoke-Log }
    "configure"   { Invoke-Configure }
    "uninstall"   { Invoke-Uninstall }
    { $_ -in "help","--help","-h" } { Show-Usage }
    default {
        Write-Err "Unknown command: $Command"
        Show-Usage
        exit 1
    }
}
'@

    Set-Content -Path $CliScript -Value $cliContent -Encoding UTF8
    Write-Ok "CLI wrapper installed to $CliScript"

    # Create a batch launcher for easy use
    $batContent = @"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "$CliScript" %*
"@
    $batPath = Join-Path $InstallDir "jenkins-agent.bat"
    Set-Content -Path $batPath -Value $batContent -Encoding ASCII
    Write-Ok "Batch launcher installed to $batPath"

    # Try to add to PATH
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentPath -notlike "*$InstallDir*") {
        [Environment]::SetEnvironmentVariable("Path", "$currentPath;$InstallDir", "User")
        Write-Ok "Added $InstallDir to user PATH (restart terminal to use)"
        Write-Host "  After restarting, you can run: jenkins-agent <command>" -ForegroundColor Yellow
    }
}

function Install-WindowsService {
    param([string]$JavaPath)

    # Try using sc.exe to create a service that runs the agent
    $config = @{}
    Get-Content $ConfFile | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
            $config[$matches[1].Trim()] = $matches[2].Trim()
        }
    }

    $serviceName = "jenkins-agent"
    $displayName = "Jenkins Agent"
    $description = "Jenkins CI agent node"
    $binPath = "`"$JavaPath`" -jar `"$AgentJar`" -jnlpUrl `"$($config.JENKINS_URL)/computer/$($config.AGENT_NAME)/jenkins-agent.jnlp`" -secret `"$($config.AGENT_SECRET)`" -workDir `"$($config.WORK_DIR)`" -webSocket"

    try {
        # Create the service
        sc.exe create $serviceName binPath= $binPath DisplayName= $displayName start= auto | Out-Null
        sc.exe description $serviceName $description | Out-Null
        sc.exe failure $serviceName reset= 86400 actions= restart/10000 | Out-Null

        Write-Ok "Windows service '$serviceName' installed"
        Write-Info "To start: net start $serviceName"
    } catch {
        Write-Warn "Could not install Windows service (may require Administrator)."
        Write-Info "You can still use 'jenkins-agent run -d' for background mode."
    }
}

function Confirm-Action {
    param([string]$Prompt, [string]$Default = "N")
    $options = if ($Default -eq "Y") { "[Y/n]" } else { "[y/N]" }
    Write-Host "$Prompt $options: " -NoNewline
    $answer = Read-Host
    if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $Default }
    return $answer -match '^[Yy]'
}

# ── Run ──────────────────────────────────────────────────────────────────────
Install-JenkinsAgent
