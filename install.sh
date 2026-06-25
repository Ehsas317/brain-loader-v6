#!/bin/bash
#
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  MESH   — FILE: install.sh                                              ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
#
# PROJECT:    Mesh (formerly Brain Loader v6)
# REPO:       https://github.com/Ehsas317/mesh
# WHAT:       A network of nodes, not a single engine. Dockerized multi-node
#             orchestration with Docker Compose mesh.
#
# THIS FILE:
#   One-command setup for the entire AI orchestration mesh.
#   Run with: bash install.sh
#
# HOW TO USE MESH:
#   1. Install Docker Desktop
#   2. Run: bash install.sh
#   3. Open http://localhost:3000 for Dify
#
# ═══════════════════════════════════════════════════════════════════════════

# =============================================================================
# Mesh — Core Installer (install.sh)
# =============================================================================
# One-command setup for the entire AI orchestration mesh.
#
# WHAT THIS SCRIPT DOES (7 steps):
#   1. Verifies Docker is installed AND the daemon is running
#   2. Asks user for execution mode (local / api / hybrid)
#   3. Creates docker-compose.yml with user-selected configuration
#   4. Pulls all Docker images (3-5 minutes on first run)
#   5. Starts all services with health checks
#   6. Creates AI persona modelfiles in Ollama
#   7. Optionally installs mesh CLI and Hermes Agent
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

MESH_DIR="$HOME/mesh"
DOCKER_COMPOSE=""

print_banner() {
    local color="$1"
    local line1="$2"
    local line2="$3"
    echo ""
    echo -e "${color}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${color}║     ${line1}${NC}"
    echo -e "${color}║     ${line2}${NC}"
    echo -e "${color}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() { echo -e "${BLUE}🔍 Step $1/$2: $3${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; exit 1; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }

command_exists() { command -v "$1" &> /dev/null; }
docker_daemon_running() { docker info &> /dev/null; }

wait_for_container() {
    local container="$1"
    local max_wait="${2:-60}"
    local waited=0
    echo -n "Waiting for ${container} to be ready..."
    while [ $waited -lt $max_wait ]; do
        local status
        status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "missing")
        if [ "$status" = "running" ]; then
            local health
            health=$(docker inspect -f '{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
            if [ "$health" = "healthy" ] || [ "$health" = "none" ]; then
                echo ""
                return 0
            fi
        fi
        sleep 2
        waited=$((waited + 2))
        echo -n "."
    done
    echo ""
    return 1
}

get_ram_gb() {
    if [ -f /proc/meminfo ]; then
        awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo
    elif command_exists sysctl; then
        sysctl -n hw.memsize | awk '{printf "%d", $1/1024/1024/1024}'
    else
        echo "0"
    fi
}

get_free_disk_gb() {
    df -BG "$HOME" 2>/dev/null | awk 'NR==2 {gsub(/G/,""); print $4}' || echo "0"
}

retry() {
    local max_retries="$1"
    local delay="$2"
    shift 2
    local attempt=1
    while [ $attempt -le $max_retries ]; do
        if "$@"; then
            return 0
        fi
        if [ $attempt -lt $max_retries ]; then
            print_warning "Attempt $attempt failed. Retrying in ${delay}s..."
            sleep "$delay"
        fi
        attempt=$((attempt + 1))
    done
    return 1
}

# =============================================================================
# STEP 0: INITIALIZATION
# =============================================================================
mkdir -p "$MESH_DIR"
cd "$MESH_DIR"

print_banner "$CYAN" "🧠 MESH — The Visual Mesh" "No-Code AI Orchestration with FOSS"

# =============================================================================
# STEP 1/7: DOCKER VALIDATION
# =============================================================================
print_step 1 7 "Checking Docker..."

if ! command_exists docker; then
    print_error "Docker not found. Please install Docker Desktop first:
   https://www.docker.com/products/docker-desktop
   After installing, RESTART your computer, then run this script again."
fi

if ! docker_daemon_running; then
    print_error "Docker is installed but the daemon is not running.
   • Mac/Windows: Open Docker Desktop and wait for it to start
   • Linux:       sudo systemctl start docker
   • WSL2:        wsl.exe -d docker-desktop"
fi

if docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
    print_success "Docker is ready (using: docker compose plugin)"
elif docker-compose --version &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
    print_success "Docker is ready (using: docker-compose standalone)"
else
    print_error "Docker Compose not found. Please update Docker Desktop."
fi

# =============================================================================
# STEP 2/7: EXECUTION MODE SELECTION
# =============================================================================
print_step 2 7 "Configuring execution mode..."
echo ""
echo -e "${YELLOW}🎮 Choose your execution mode:${NC}"
echo "   1) 🏠 LOCAL ONLY  — Free forever. Uses your computer's CPU/GPU."
echo "   2) ☁️  CLOUD API  — Fast. Costs ~\$0.50-2/project."
echo "   3) 🔄 HYBRID      — Brain runs local, heavy tasks use cloud. RECOMMENDED."
echo ""
read -p "Enter 1, 2, or 3 [default: 3]: " MODE_CHOICE
MODE_CHOICE=${MODE_CHOICE:-3}

case "$MODE_CHOICE" in
    1) MODE="local" ;;
    2) MODE="api" ;;
    3) MODE="hybrid" ;;
    *) MODE="hybrid"; print_warning "Invalid input. Using HYBRID mode." ;;
esac

print_success "Mode set to: $MODE"

# =============================================================================
# STEP 3/7: CREATE DOCKER COMPOSE FILE
# =============================================================================
print_step 3 7 "Creating your mesh configuration..."

# Phase 1: Write docker-compose.yml with placeholder.
cat > docker-compose.yml << 'COMPOSE_EOF'
version: "3.8"

services:
  ollama:
    image: ollama/ollama:latest
    container_name: mesh-ollama
    ports:
      - "11434:11434"
    volumes:
      - ollama-data:/root/.ollama
      - ./ollama-personas:/root/.ollama/personas:ro
    networks:
      - mesh-net
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "ollama", "ps"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  dify-api:
    image: langgenius/dify-api:latest
    container_name: mesh-dify-api
    ports:
      - "5001:5001"
    environment:
      - MODE=__EXEC_MODE__
      - CONSOLE_API_URL=http://localhost:5001
      - APP_API_URL=http://localhost:5001
      - SECRET_KEY=mesh-secret-key-change-me
      - DB_USERNAME=mesh
      - DB_PASSWORD=mesh-secure
      - DB_HOST=mesh-postgres
      - DB_PORT=5432
      - DB_DATABASE=meshdb
      - REDIS_HOST=mesh-redis
      - REDIS_PORT=6379
      - REDIS_DB=0
      - WEAVIATE_ENDPOINT=http://mesh-weaviate:8080
    volumes:
      - dify-data:/app/api/storage
    networks:
      - mesh-net
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      weaviate:
        condition: service_healthy
    restart: unless-stopped

  dify-web:
    image: langgenius/dify-web:latest
    container_name: mesh-dify-web
    ports:
      - "3000:3000"
    environment:
      - CONSOLE_API_URL=http://localhost:5001
      - APP_API_URL=http://localhost:5001
    networks:
      - mesh-net
    depends_on:
      - dify-api
    restart: unless-stopped

  flowise:
    image: flowiseai/flowise:latest
    container_name: mesh-flowise
    ports:
      - "3001:3000"
    environment:
      - FLOWISE_USERNAME=mesh
      - FLOWISE_PASSWORD=mesh-pass
      - DATABASE_PATH=/root/.flowise
      - APIKEY_PATH=/root/.flowise
      - SECRETKEY_PATH=/root/.flowise
      - LOG_PATH=/root/.flowise/logs
    volumes:
      - flowise-data:/root/.flowise
    networks:
      - mesh-net
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    container_name: mesh-redis
    volumes:
      - redis-data:/data
    networks:
      - mesh-net
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 15s

  postgres:
    image: postgres:15-alpine
    container_name: mesh-postgres
    environment:
      - POSTGRES_USER=mesh
      - POSTGRES_PASSWORD=mesh-secure
      - POSTGRES_DB=meshdb
    volumes:
      - postgres-data:/var/lib/postgresql/data
    networks:
      - mesh-net
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U mesh -d meshdb || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  weaviate:
    image: semitechnologies/weaviate:1.24.0
    container_name: mesh-weaviate
    ports:
      - "8080:8080"
    environment:
      - QUERY_DEFAULTS_LIMIT=25
      - AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED=true
      - PERSISTENCE_DATA_PATH=/var/lib/weaviate
      - DEFAULT_VECTORIZER_MODULE=none
    volumes:
      - weaviate-data:/var/lib/weaviate
    networks:
      - mesh-net
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/v1/.well-known/ready"]
      interval: 15s
      timeout: 10s
      retries: 5
      start_period: 45s

volumes:
  ollama-data:
  dify-data:
  flowise-data:
  redis-data:
  postgres-data:
  weaviate-data:

networks:
  mesh-net:
    driver: bridge
    name: mesh-net
COMPOSE_EOF

# Phase 2: Replace the placeholder with the actual mode.
sed -i "s/__EXEC_MODE__/${MODE}/g" docker-compose.yml

if grep -q "__EXEC_MODE__" docker-compose.yml; then
    print_error "Failed to substitute MODE value into docker-compose.yml"
fi

print_success "Docker Compose configuration created (mode: $MODE)"

# =============================================================================
# STEP 4/7: DOWNLOAD DOCKER IMAGES
# =============================================================================
print_step 4 7 "Downloading AI tools (3-5 minutes on first run)..."

if retry 3 10 $DOCKER_COMPOSE pull; then
    print_success "All images downloaded"
else
    print_error "Failed to download Docker images after 3 attempts."
fi

# =============================================================================
# STEP 5/7: START ALL SERVICES
# =============================================================================
print_step 5 7 "Starting your AI mesh..."

$DOCKER_COMPOSE up -d
print_success "All services started"

echo ""
echo -e "${BLUE}⏳ Waiting for infrastructure to be ready...${NC}"

for service in mesh-postgres mesh-redis mesh-weaviate; do
    if wait_for_container "$service" 90; then
        print_success "${service} is ready"
    else
        print_error "${service} failed to start within 90 seconds."
    fi
done

if wait_for_container mesh-ollama 120; then
    print_success "mesh-ollama is ready"
else
    print_error "mesh-ollama failed to start within 120 seconds."
fi

# =============================================================================
# STEP 6/7: CREATE AI PERSONAS
# =============================================================================
print_step 6 7 "Creating AI personas..."

mkdir -p "$MESH_DIR/ollama-personas"

cat > "$MESH_DIR/ollama-personas/mesh-planner.modelfile" << 'PERSONA_EOF'
FROM llama3.2
PARAMETER temperature 0.6
PARAMETER num_ctx 8192
SYSTEM """
You are the strategic planner in the Mesh system.
Your job: decompose the user's goal into a wave of parallel specialist tasks.

OUTPUT FORMAT: Valid JSON only. No prose. No markdown code fences.

Rules:
- parallel_safe: true means task can run alongside others
- Aim for 2-5 tasks per wave
- Available roles: researcher, coder, writer, math, critic
- One role per task. Prompts must be self-contained.
"""
PERSONA_EOF

cat > "$MESH_DIR/ollama-personas/coder.modelfile" << 'PERSONA_EOF'
FROM llama3.2
PARAMETER temperature 0.2
PARAMETER num_ctx 8192
SYSTEM """
You are a senior software engineer. Write clean, working code.
Always include complete examples. Prefer standard libraries.
"""
PERSONA_EOF

cat > "$MESH_DIR/ollama-personas/researcher.modelfile" << 'PERSONA_EOF'
FROM llama3.2
PARAMETER temperature 0.5
PARAMETER num_ctx 16384
SYSTEM """
You are a research analyst. Find facts, compare options, cite sources.
Be thorough but concise. Always verify claims.
"""
PERSONA_EOF

cat > "$MESH_DIR/ollama-personas/critic.modelfile" << 'PERSONA_EOF'
FROM llama3.2
PARAMETER temperature 0.3
PARAMETER num_ctx 4096
SYSTEM """
You are a code reviewer and security analyst. Find bugs, vulnerabilities,
and inefficiencies. Be specific about what to fix and why.
"""
PERSONA_EOF

print_success "Persona modelfiles created"

# Pull base model
if ! docker exec mesh-ollama ollama list 2>/dev/null | grep -q "llama3.2"; then
    echo -e "${YELLOW}⬇️  Downloading Llama 3.2 (4GB, may take 5-10 minutes)...${NC}"
    if retry 3 15 docker exec mesh-ollama ollama pull llama3.2; then
        print_success "Llama 3.2 downloaded"
    else
        print_warning "Failed to download Llama 3.2. Retry later:
   docker exec mesh-ollama ollama pull llama3.2"
    fi
else
    print_success "Llama 3.2 already available"
fi

# Create custom personas
echo "Registering personas with Ollama..."
PERSONA_ERRORS=0
for persona in mesh-planner coder researcher critic; do
    if docker exec mesh-ollama ollama create "$persona" -f "/root/.ollama/personas/${persona}.modelfile" 2>/dev/null; then
        print_success "Persona '${persona}' registered"
    else
        print_warning "Failed to register persona '${persona}'"
        PERSONA_ERRORS=$((PERSONA_ERRORS + 1))
    fi
done

if [ $PERSONA_ERRORS -gt 0 ]; then
    print_warning "$PERSONA_ERRORS persona(s) failed to register."
fi

# =============================================================================
# STEP 7/7: OPTIONAL TOOLS
# =============================================================================
print_step 7 7 "Installing optional tools..."

echo "Checking mesh CLI..."
if command_exists meshmem; then
    meshmem onboard --agents all --yes 2>/dev/null || true
    print_success "mesh CLI configured"
elif command_exists brew; then
    if brew install codejunkie99/tap/meshmem 2>/dev/null; then
        meshmem onboard --agents all --yes 2>/dev/null || true
        print_success "mesh CLI installed and configured"
    else
        print_warning "mesh CLI install skipped."
    fi
else
    print_warning "mesh CLI requires Homebrew (Mac/Linux only)."
fi

echo "Checking Hermes Agent..."
if command_exists hermes; then
    print_success "Hermes already installed"
else
    if curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh 2>/dev/null | bash 2>/dev/null; then
        print_success "Hermes Agent installed"
    else
        print_warning "Hermes Agent install skipped."
    fi
fi

# =============================================================================
# FINAL SUMMARY
# =============================================================================
print_banner "$GREEN" "🎉 YOUR MESH IS READY!" "All systems operational"

echo -e "${BOLD}${GREEN}📍 Your Services:${NC}"
echo "   • Dify (Workflow Builder)    → http://localhost:3000"
echo "   • Flowise (Alt. Builder)     → http://localhost:3001"
echo "   • Ollama (Local Models)      → http://localhost:11434"
echo "   • Weaviate (Vector Memory)   → http://localhost:8080"
echo ""

echo -e "${BOLD}${GREEN}🤖 AI Personas (Ollama):${NC}"
echo "   • mesh-planner  → Strategic task planner"
echo "   • coder          → Code writer"
echo "   • researcher     → Research analyst"
echo "   • critic         → Code reviewer"
echo ""

echo -e "${BOLD}${GREEN}📝 Daily Commands:${NC}"
echo "   Start:     cd $MESH_DIR && $DOCKER_COMPOSE up -d"
echo "   Stop:      cd $MESH_DIR && $DOCKER_COMPOSE down"
echo "   Logs:      cd $MESH_DIR && $DOCKER_COMPOSE logs -f"
echo "   Reset:     cd $MESH_DIR && $DOCKER_COMPOSE down -v  (DELETES ALL DATA)"
echo ""

echo -e "${BOLD}${YELLOW}⚡ Next Steps:${NC}"
echo "   1. Open http://localhost:3000 in your browser"
echo "   2. Create an admin account (first-time setup)"
echo "   3. Go to Settings → Model Providers → Ollama → http://mesh-ollama:11434"
echo "   4. Create your first workflow"
echo "   5. To add chatbots: bash install-bots.sh"
echo ""

echo -e "${CYAN}Happy building! 🚀${NC}"
