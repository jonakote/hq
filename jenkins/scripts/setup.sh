#!/usr/bin/env bash
# ==============================================================================
# Jenkins Setup - Quick Start Script
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}"
cat << "EOF"
     _              _             _             
    | | ___   __ __| | ___ _ __  |_ __   ___ _   
    | |/ _ \ / / _` |/ _ \ '__| | '_ \ / _ \ |  
    | | (_) / / (_| |  __/ |    | | | |  __/ |  
    |_|\___/_/ \__,_|\___|_|    |_| |_|\___|_|  
                                                  
EOF
echo -e "${NC}"
echo -e "${BOLD}Complete Jenkins CI/CD Setup${NC}"
echo ""

# ── Detect OS ────────────────────────────────────────────────────────────────
OS_TYPE="$(uname -s)"
echo -e "${BLUE}[INFO]${NC} Detected OS: $OS_TYPE"

# ── Check Prerequisites ──────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Checking prerequisites...${NC}"

check_command() {
    if command -v "$1" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $1 is installed"
        return 0
    else
        echo -e "  ${YELLOW}✗${NC} $1 is NOT installed"
        return 1
    fi
}

MISSING=0
check_command "docker" || MISSING=1
check_command "docker-compose" || check_command "docker compose" 2>/dev/null || MISSING=1
check_command "java" || echo -e "  ${YELLOW}!${NC} Java is optional (needed for agents)"

echo ""

if [[ $MISSING -eq 1 ]]; then
    echo -e "${YELLOW}[WARN]${NC} Some prerequisites are missing."
    echo ""
    echo "Please install:"
    echo "  - Docker: https://docs.docker.com/get-docker/"
    echo "  - Docker Compose: https://docs.docker.com/compose/install/"
    echo ""
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# ── Menu ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}What would you like to set up?${NC}"
echo ""
echo "  1) Jenkins Master (server)"
echo "  2) Jenkins Agent (this machine as a runner)"
echo "  3) Both Master and Agent"
echo "  4) View documentation"
echo "  5) Exit"
echo ""
read -p "Choose option [1-5]: " choice

case $choice in
    1)
        echo ""
        echo -e "${BLUE}[INFO]${NC} Setting up Jenkins Master..."
        cd master
        echo ""
        echo "Choose Jenkins configuration:"
        echo "  1) Basic setup (recommended)"
        echo "  2) With Docker-in-Docker (for building Docker images)"
        echo ""
        read -p "Choose [1-2]: " master_choice
        
        if [[ ! -f .env ]]; then
            cp .env.example .env
            echo -e "${GREEN}[OK]${NC} Created .env file from template"
            echo -e "${YELLOW}[INFO]${NC} Edit .env to customize settings"
        fi
        
        if [[ "$master_choice" == "2" ]]; then
            docker compose -f docker-compose.dind.yml up -d
        else
            docker compose up -d
        fi
        
        echo ""
        echo -e "${GREEN}${BOLD}✓ Jenkins Master started!${NC}"
        echo ""
        echo "Access Jenkins at: ${BLUE}http://localhost:8080${NC}"
        echo ""
        echo "Get initial admin password:"
        echo "  docker exec jenkins-master cat /var/jenkins_home/secrets/initialAdminPassword"
        echo ""
        echo "View logs:"
        echo "  docker logs -f jenkins-master"
        echo ""
        echo "Stop Jenkins:"
        echo "  docker compose down"
        echo ""
        ;;
    
    2)
        echo ""
        echo -e "${BLUE}[INFO]${NC} Setting up Jenkins Agent..."
        
        if [[ "$OS_TYPE" == "Darwin" ]] || [[ "$OS_TYPE" == "Linux" ]]; then
            chmod +x install.sh
            ./install.sh
        else
            echo -e "${YELLOW}[WARN]${NC} Windows detected. Please run:"
            echo "  powershell -ExecutionPolicy Bypass -File install.ps1"
        fi
        ;;
    
    3)
        echo ""
        echo -e "${BLUE}[INFO]${NC} Setting up Jenkins Master and Agent..."
        echo ""
        echo "Step 1: Starting Jenkins Master..."
        cd master
        
        if [[ ! -f .env ]]; then
            cp .env.example .env
            echo -e "${GREEN}[OK]${NC} Created .env file from template"
        fi
        
        docker compose up -d
        echo ""
        echo -e "${GREEN}[OK]${NC} Jenkins Master started!"
        echo ""
        echo "Wait ~30 seconds for Jenkins to fully start, then:"
        echo "  1. Open http://localhost:8080"
        echo "  2. Complete the setup wizard"
        echo "  3. Create a new node in Jenkins UI"
        echo "  4. Come back and run: ./install.sh"
        echo ""
        cd ..
        ;;
    
    4)
        echo ""
        echo -e "${BLUE}[INFO]${NC} Opening documentation..."
        echo ""
        echo "Main README: $(pwd)/README.md"
        echo "Master docs: $(pwd)/master/README.md"
        echo ""
        echo "Quick commands:"
        echo "  cat README.md | less"
        echo "  cat master/README.md | less"
        echo ""
        ;;
    
    5)
        echo ""
        echo "Goodbye!"
        exit 0
        ;;
    
    *)
        echo ""
        echo -e "${YELLOW}[WARN]${NC} Invalid option"
        exit 1
        ;;
esac

echo ""
echo -e "${BOLD}Useful Links:${NC}"
echo "  Jenkins:     https://www.jenkins.io/doc/"
echo "  Pipelines:   https://www.jenkins.io/doc/book/pipeline/"
echo "  Plugins:     https://plugins.jenkins.io/"
echo ""
