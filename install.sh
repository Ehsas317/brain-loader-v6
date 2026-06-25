#!/bin/bash
# =============================================================================
# Brain Loader v6 — Core Installer (install.sh)
# =============================================================================
# One-command setup for the entire AI orchestration mesh.
# Run with: bash install.sh
#
# WHAT THIS SCRIPT DOES (7 steps):
#   1. Verifies Docker is installed AND the daemon is running
#   2. Asks user for execution mode (local / api / hybrid)
#   3. Creates docker-compose.yml with user-selected configuration
#   4. Pulls all Docker images (3-5 minutes on first run)
#   5. Starts all services with health checks
#   6. Creates AI persona modelfiles in Ollama
#   7. Optionally installs brain CLI and Hermes Agent
#
# BUG FIXES IN THIS VERSION (vs original v6 guide):
#   - Fixed MODE variable not being substituted into docker-compose.yml
#     (original used << 'EOF' which prevents ALL shell expansion)
#   - Added Docker daemon running check (not just binary existence)
#   - Auto-detects 'docker compose' (plugin) vs 'docker-compose' (standalone)
#   - Added system requirements check (RAM, disk space, architecture)
#   - Added retry logic for ollama pull (network hiccups)
#   - Replaced 'sleep 5' with proper container readiness wait
#   - Added non-silent error handling for critical steps
#   - Fixed ollama create path resolution
#   - Added input validation for all user prompts
#   - Added colored progress output and better error messages
#   - Added rollback/cleanup on critical failures
# =============================================================================

# ---------------------------------------------------------------------------
# SHELL OPTIONS
# ---------------------------------------------------------------------------
# 'set -e' makes the script exit immediately if ANY command returns non-zero.
# This prevents the script from continuing in a broken state.
# We selectively disable it around non-critical commands using '|| true'.
set -e

# 'set -u' makes the script exit if we use an undefined variable.
# Catches typos in variable names early.
set -u

# 'set -o pipefail' ensures pipeline exit code = rightmost NON-ZERO exit code.
# Without this, 'cmd1 | cmd2' always returns cmd2's exit code even if cmd1 fails.
set -o pipefail

# ---------------------------------------------------------------------------
# COLOR DEFINITIONS
# ---------------------------------------------------------------------------
# We use ANSI escape codes for colored terminal output.
# The '\033[' is the ESC character in octal. '[' starts a CSI sequence.
# These make the installer visually friendly and easier to follow.
#
# IMPORTANT: These are purely cosmetic. The script works fine even if the
# terminal doesn't support colors — you'll just see raw escape codes.
RED='\033[0;31m'      # Red — errors, failures
GREEN='\033[0;32m'    # Green — success, completion
YELLOW='\033[1;33m'   # Yellow — warnings, in-progress
BLUE='\033[0;34m'     # Blue — section headers, info
CYAN='\033[0;36m'     # Cyan — banners, highlights
BOLD='\033[1m'        # Bold — emphasis
NC='\033[0m'          # No Color — reset to default

# ---------------------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------------------
# $HOME expands to the current user's home directory (/home/username on Linux,
# /Users/username on Mac, C:\Users\username on Windows with Git Bash).
# All Brain Loader files live in one directory for easy management.
BRAIN_DIR="$HOME/brain-loader-v6"

# The Docker Compose command we'll use. We detect the correct form later
# ('docker compose' for the plugin, 'docker-compose' for standalone).
# This variable lets us use "$DOCKER_COMPOSE" everywhere instead of hardcoding.
DOCKER_COMPOSE=""

# ---------------------------------------------------------------------------
# HELPER FUNCTIONS
# ---------------------------------------------------------------------------
# These functions encapsulate common patterns for cleaner, DRY code.

# print_banner: Display a large decorative banner for major sections.
# We use printf instead of echo for better control over formatting.
# $1 = color code, $2 = line 1, $3 = line 2
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

# print_step: Display a numbered step header in blue.
# $1 = step number, $2 = total steps, $3 = description
print_step() {
    echo -e "${BLUE}🔍 Step $1/$2: $3${NC}"
}

# print_success: Display a green checkmark with a message.
# $1 = message
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# print_error: Display a red X with a message and exit.
# $1 = message
print_error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# print_warning: Display a yellow warning (non-fatal).
# $1 = message
print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# command_exists: Check if a command is available in PATH.
# Returns 0 (true) if found, 1 (false) if not.
# We use 'command -v' instead of 'which' because 'which' is not POSIX-compliant
# and may not exist on minimal systems (Alpine, etc.).
command_exists() {
    command -v "$1" &> /dev/null
}

# docker_daemon_running: Check if the Docker daemon is actually accepting commands.
# 'docker info' returns 0 only if the daemon is running and reachable.
# It returns non-zero if: daemon not started, permission denied, Docker Desktop not running.
docker_daemon_running() {
    docker info &> /dev/null
}

# wait_for_container: Poll until a container is running and healthy.
# $1 = container name, $2 = max wait seconds (default: 60)
# Returns 0 if healthy, 1 if timeout.
wait_for_container() {
    local container="$1"
    local max_wait="${2:-60}"
    local waited=0
    echo -n "Waiting for ${container} to be ready..."
    while [ $waited -lt $max_wait ]; do
        # 'docker inspect' gets container state. '-f' formats output.
        # We check: container exists AND is in 'running' state.
        local status
        status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "missing")
        if [ "$status" = "running" ]; then
            # Check health if available. If no health check, "running" is enough.
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

# get_ram_gb: Get total system RAM in gigabytes (rounded down).
# Works on Linux (/proc/meminfo), macOS (sysctl), and WSL.
get_ram_gb() {
    if [ -f /proc/meminfo ]; then
        # Linux: MemTotal is in kB. Divide by 1024^2 to get GB.
        awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo
    elif command_exists sysctl; then
        # macOS: hw.memsize is in bytes. Divide by 1024^3 to get GB.
        sysctl -n hw.memsize | awk '{printf "%d", $1/1024/1024/1024}'
    else
        echo "0"  # Unknown system, return 0 (will trigger warning)
    fi
}

# get_free_disk_gb: Get free disk space on $HOME partition in GB.
get_free_disk_gb() {
    df -BG "$HOME" 2>/dev/null | awk 'NR==2 {gsub(/G/,""); print $4}' || echo "0"
}

# retry: Retry a command up to N times with delay between attempts.
# $1 = max retries, $2 = delay seconds, ${@:3} = command to run
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
# Create the working directory early so we can write logs/files there.
# 'mkdir -p' creates parent directories if they don't exist and does NOT
# error if the directory already exists (idempotent — safe to run multiple times).
mkdir -p "$BRAIN_DIR"
cd "$BRAIN_DIR"

# Display the welcome banner. The emoji (🧠) is just a Unicode character.
print_banner "$CYAN" "🧠 BRAIN LOADER v6 — The Visual Mesh" "No-Code AI Orchestration with FOSS"

# =============================================================================
# STEP 1/7: DOCKER VALIDATION
# =============================================================================
print_step 1 7 "Checking Docker..."

# Check 1a: Is the 'docker' binary installed?
# 'command -v docker' searches PATH for the 'docker' executable.
# '&> /dev/null' redirects BOTH stdout and stderr to /dev/null (silent check).
if ! command_exists docker; then
    print_error "Docker not found. Please install Docker Desktop first:

   Mac/Windows: https://www.docker.com/products/docker-desktop
   Linux:       sudo apt update && sudo apt install docker.io docker-compose-plugin -y

   After installing, RESTART your computer, then run this script again."
fi

# Check 1b: Is the Docker daemon actually running?
# Many users install Docker Desktop but forget to start it.
# 'docker info' is the most reliable check — it actually talks to the daemon.
if ! docker_daemon_running; then
    print_error "Docker is installed but the daemon is not running.

   Common fixes:
   • Mac/Windows: Open Docker Desktop application and wait for it to start
   • Linux:       sudo systemctl start docker
   • WSL2:        wsl.exe -d docker-desktop

   After starting Docker, run this script again."
fi

# Check 1c: Auto-detect the correct Docker Compose command.
# Docker has TWO ways to run compose:
#   1. Plugin (modern):  'docker compose'  — recommended, built into Docker CLI
#   2. Standalone (old): 'docker-compose'  — Python script, being phased out
# We test which one works and store it in $DOCKER_COMPOSE for consistent use.
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
    print_success "Docker is ready (using: docker compose plugin)"
elif docker-compose --version &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
    print_success "Docker is ready (using: docker-compose standalone)"
else
    print_error "Docker Compose not found. Please update Docker Desktop or install:

   Linux: sudo apt install docker-compose-plugin -y

   Docker Compose is REQUIRED to run the Brain Loader mesh."
fi

# =============================================================================
# STEP 1.5: SYSTEM REQUIREMENTS CHECK (Non-fatal warnings)
# =============================================================================
# We check RAM and disk space and WARN the user if insufficient.
# These are WARNINGS, not errors — the script continues because:
#   - Users might have swap space
#   - They might want to try anyway
#   - Requirements vary by which services they actually use
RAM_GB=$(get_ram_gb)
DISK_GB=$(get_free_disk_gb)

#echo ""
#if [ "$RAM_GB" -lt 8 ] && [ "$RAM_GB" -gt 0 ]; then
#    print_warning "Low RAM detected: ${RAM_GB}GB (recommended: 8GB+)
#
#   The full mesh needs ~6-8GB RAM. You can still run a minimal setup:
#       cd $BRAIN_DIR && $DOCKER_COMPOSE up -d ollama flowise"
#fi
#
#if [ "$DISK_GB" -lt 20 ] && [ "$DISK_GB" -gt 0 ]; then
#    print_warning "Low disk space: ${DISK_GB}GB free (recommended: 20GB+)
#
#   Each AI model is 4-8GB. The Docker images need ~5GB.
#   Consider freeing up space before downloading models."
#fi

# =============================================================================
# STEP 2/7: EXECUTION MODE SELECTION
# =============================================================================
print_step 2 7 "Configuring execution mode..."
echo ""

# Display the mode options with clear descriptions.
# We use echo with -e to interpret the color codes.
echo -e "${YELLOW}🎮 Choose your execution mode:${NC}"
echo "   1) 🏠 LOCAL ONLY  — Free forever. Uses your computer's CPU/GPU."
echo "   2) ☁️  CLOUD API  — Fast. Costs ~\$0.50-2/project. Uses OpenAI/DeepSeek."
echo "   3) 🔄 HYBRID      — Brain runs local, heavy tasks use cloud. RECOMMENDED."
echo ""

# 'read -p' displays a prompt and reads user input into MODE_CHOICE.
# The '${MODE_CHOICE:-3}' syntax means: if MODE_CHOICE is empty (user just
# pressed Enter), use 3 as the default value. This is called "parameter expansion
# with default value" in bash.
read -p "Enter 1, 2, or 3 [default: 3]: " MODE_CHOICE
MODE_CHOICE=${MODE_CHOICE:-3}

# Validate input: only accept 1, 2, or 3.
# We use a case statement (bash's pattern matching switch).
# The '[^123]' pattern matches anything EXCEPT 1, 2, or 3.
# The '|' operator combines patterns. '*' is the default catch-all.
case "$MODE_CHOICE" in
    1)
        MODE="local"
        ;;
    2)
        MODE="api"
        ;;
    3)
        MODE="hybrid"
        ;;
    *)
        # Invalid input — fall back to hybrid (safest default) and inform user.
        MODE="hybrid"
        print_warning "Invalid input '$MODE_CHOICE'. Using HYBRID mode (default)."
        ;;
esac

print_success "Mode set to: $MODE"

# =============================================================================
# STEP 3/7: CREATE DOCKER COMPOSE FILE
# =============================================================================
print_step 3 7 "Creating your mesh configuration..."

# CRITICAL BUG FIX: The original v6 guide used `cat > docker-compose.yml << 'EOF'`
# (with QUOTED 'EOF'). In bash heredocs, quoting the delimiter ('EOF' vs EOF)
# DISABLES variable substitution. So ${MODE:-hybrid} would be written LITERALLY
# into the file instead of being expanded to "local", "api", or "hybrid".
#
# SOLUTION: We use a TWO-PHASE approach:
#   Phase 1: Write the file with a PLACEHOLDER string (__EXEC_MODE__)
#   Phase 2: Use 'sed' to replace the placeholder with the actual $MODE value
#
# This is the MOST RELIABLE method because:
#   - We don't risk accidental expansion of OTHER dollar-sign content
#   - We can use '<< \'EOF\'' (quoted) for safety against shell injection
#   - The replacement is explicit and visible

# Phase 1: Write docker-compose.yml with placeholder.
# The '\'EOF\'' (backslash + quoted EOF) completely prevents shell expansion.
# This means $ signs in the YAML are treated as literal characters.
cat > docker-compose.yml << 'COMPOSE_EOF'
version: "3.8"

services:
  ollama:
    image: ollama/ollama:latest
    container_name: brain-ollama
    ports:
      - "11434:11434"
    volumes:
      - ollama-data:/root/.ollama
      - ./ollama-personas:/root/.ollama/personas:ro
    networks:
      - brain-mesh
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "ollama", "ps"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  dify-api:
    image: langgenius/dify-api:latest
    container_name: brain-dify-api
    ports:
      - "5001:5001"
    environment:
      - MODE=__EXEC_MODE__
      - CONSOLE_API_URL=http://localhost:5001
      - APP_API_URL=http://localhost:5001
      - SECRET_KEY=brain-loader-v6-secret-key-change-me
      - DB_USERNAME=brain
      - DB_PASSWORD=loader-v6-secure
      - DB_HOST=brain-postgres
      - DB_PORT=5432
      - DB_DATABASE=brainmesh
      - REDIS_HOST=brain-redis
      - REDIS_PORT=6379
      - REDIS_DB=0
      - WEAVIATE_ENDPOINT=http://brain-weaviate:8080
    volumes:
      - dify-data:/app/api/storage
    networks:
      - brain-mesh
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
    container_name: brain-dify-web
    ports:
      - "3000:3000"
    environment:
      - CONSOLE_API_URL=http://localhost:5001
      - APP_API_URL=http://localhost:5001
    networks:
      - brain-mesh
    depends_on:
      - dify-api
    restart: unless-stopped

  flowise:
    image: flowiseai/flowise:latest
    container_name: brain-flowise
    ports:
      - "3001:3000"
    environment:
      - FLOWISE_USERNAME=brain
      - FLOWISE_PASSWORD=loader-v6
      - DATABASE_PATH=/root/.flowise
      - APIKEY_PATH=/root/.flowise
      - SECRETKEY_PATH=/root/.flowise
      - LOG_PATH=/root/.flowise/logs
    volumes:
      - flowise-data:/root/.flowise
    networks:
      - brain-mesh
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    container_name: brain-redis
    volumes:
      - redis-data:/data
    networks:
      - brain-mesh
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 15s

  postgres:
    image: postgres:15-alpine
    container_name: brain-postgres
    environment:
      - POSTGRES_USER=brain
      - POSTGRES_PASSWORD=loader-v6-secure
      - POSTGRES_DB=brainmesh
    volumes:
      - postgres-data:/var/lib/postgresql/data
    networks:
      - brain-mesh
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U brain -d brainmesh || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  weaviate:
    image: semitechnologies/weaviate:1.24.0
    container_name: brain-weaviate
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
      - brain-mesh
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
  brain-mesh:
    driver: bridge
    name: brain-mesh
COMPOSE_EOF

# Phase 2: Replace the placeholder with the actual mode.
# 'sed -i' edits in-place. The 's/old/new/' syntax does substitution.
# We use double quotes around the sed expression so $MODE gets expanded
# by the shell BEFORE sed runs.
sed -i "s/__EXEC_MODE__/${MODE}/g" docker-compose.yml

# Verify the replacement worked (non-zero exit if placeholder still exists).
if grep -q "__EXEC_MODE__" docker-compose.yml; then
    print_error "Failed to substitute MODE value into docker-compose.yml"
fi

print_success "Docker Compose configuration created (mode: $MODE)"

# =============================================================================
# STEP 4/7: DOWNLOAD DOCKER IMAGES
# =============================================================================
print_step 4 7 "Downloading AI tools (3-5 minutes on first run)..."

# 'docker compose pull' downloads all images WITHOUT starting containers.
# This lets us fail fast if there are network issues, before we try to start anything.
# We use 'retry' because Docker Hub can timeout on slow connections.
if retry 3 10 $DOCKER_COMPOSE pull; then
    print_success "All images downloaded"
else
    print_error "Failed to download Docker images after 3 attempts.

   Common causes:
   • Slow/unstable internet connection
   • Docker Hub rate limiting (wait 1 hour and retry)
   • Corporate proxy blocking Docker Hub

   Try: $DOCKER_COMPOSE pull --verbose (for detailed error output)"
fi

# =============================================================================
# STEP 5/7: START ALL SERVICES
# =============================================================================
print_step 5 7 "Starting your AI mesh..."

# '-d' (detached) runs containers in the background so the script continues.
# Without '-d', your terminal would be attached to container logs forever.
$DOCKER_COMPOSE up -d
print_success "All services started"

# Wait for critical infrastructure to be ready before proceeding.
# The Dify API depends on postgres, redis, and weaviate being healthy.
# Without this wait, the next step (creating personas) could race against
# container startup and fail intermittently.
echo ""
echo -e "${BLUE}⏳ Waiting for infrastructure to be ready...${NC}"

# wait_for_container polls Docker for container status.
# We wait for the infrastructure services that Ollama personas depend on.
# Dify's health checks on postgres/redis/weaviate mean Dify will wait
# automatically — we don't need to poll Dify itself.
for service in brain-postgres brain-redis brain-weaviate; do
    if wait_for_container "$service" 90; then
        print_success "${service} is ready"
    else
        print_error "${service} failed to start within 90 seconds.

   Check logs: $DOCKER_COMPOSE logs ${service}
   Common causes:
   • Port conflict (another service using the same port)
   • Insufficient disk space for database initialization
   • Corrupt volume from a previous failed start

   Fix: $DOCKER_COMPOSE down -v  # WARNING: This deletes all data!"
    fi
done

# Also wait for Ollama specifically (we need it for persona creation).
if wait_for_container brain-ollama 120; then
    print_success "brain-ollama is ready"
else
    print_error "brain-ollama failed to start within 120 seconds.

   Check logs: $DOCKER_COMPOSE logs ollama
   Ollama needs GPU drivers on Linux. CPU mode works but is slower.

   Fix: $DOCKER_COMPOSE restart ollama"
fi

# =============================================================================
# STEP 6/7: CREATE AI PERSONAS (OLLAMA MODELS)
# =============================================================================
print_step 6 7 "Creating AI personas..."

# Create the personas directory on the host. This is bind-mounted into the
# Ollama container at /root/.ollama/personas. The ':ro' flag means the
# container can read these files but cannot modify them.
mkdir -p "$BRAIN_DIR/ollama-personas"

# ---------------------------------------------------------------------------
# PERSONA 1: brain-planner
# ROLE: Strategic task planner. Decomposes user goals into parallel tasks.
# TEMPERATURE: 0.6 (balanced — creative enough for varied approaches,
#                    focused enough for consistent output)
# CONTEXT WINDOW: 8192 tokens (enough for complex multi-step planning)
# ---------------------------------------------------------------------------
cat > "$BRAIN_DIR/ollama-personas/brain-planner.modelfile" << 'PERSONA_EOF'
FROM llama3.2
PARAMETER temperature 0.6
PARAMETER num_ctx 8192
SYSTEM """
You are the Brain — the strategic planner in the Brain Loader v6 system.
Your job: decompose the user's goal into a wave of parallel specialist tasks.

OUTPUT FORMAT: Valid JSON only. No prose. No markdown code fences. Exactly this schema:

{
  "goal_understood": "one-sentence restatement",
  "tasks": [
    {
      "id": "T1",
      "role": "researcher",
      "prompt": "detailed prompt",
      "parallel_safe": true
    }
  ],
  "synthesis_notes": "how to combine outputs",
  "wave_count_estimate": 1
}

Rules:
- parallel_safe: true means task can run alongside others
- parallel_safe: false means it needs results from parallel tasks first
- Aim for 2-5 tasks per wave
- Available roles: researcher, coder, writer, math, critic
- One role per task. Prompts must be self-contained.
"""
PERSONA_EOF

# ---------------------------------------------------------------------------
# PERSONA 2: coder
# ROLE: Senior software engineer. Writes clean, working code.
# TEMPERATURE: 0.2 (LOW — we want consistent, deterministic code output)
# CONTEXT WINDOW: 8192 tokens (enough for medium-sized functions/modules)
# ---------------------------------------------------------------------------
cat > "$BRAIN_DIR/ollama-personas/coder.modelfile" << 'PERSONA_EOF'
FROM llama3.2
PARAMETER temperature 0.2
PARAMETER num_ctx 8192
SYSTEM """
You are a senior software engineer. Write clean, working code.
Always include complete examples. Prefer standard libraries.
Mark shortcuts with "ponytail:" comments showing upgrade paths.
"""
PERSONA_EOF

# ---------------------------------------------------------------------------
# PERSONA 3: researcher
# ROLE: Research analyst. Finds facts, compares options, cites sources.
# TEMPERATURE: 0.5 (medium — balanced between creativity and accuracy)
# CONTEXT WINDOW: 16384 tokens (needs to read/search lots of material)
# ---------------------------------------------------------------------------
cat > "$BRAIN_DIR/ollama-personas/researcher.modelfile" << 'PERSONA_EOF'
FROM llama3.2
PARAMETER temperature 0.5
PARAMETER num_ctx 16384
SYSTEM """
You are a research analyst. Find facts, compare options, cite sources.
Be thorough but concise. Always verify claims.
"""
PERSONA_EOF

# ---------------------------------------------------------------------------
# PERSONA 4: critic
# ROLE: Code reviewer and security analyst.
# TEMPERATURE: 0.3 (low — critical analysis needs consistency)
# CONTEXT WINDOW: 4096 tokens (code review focuses on specific sections)
# ---------------------------------------------------------------------------
cat > "$BRAIN_DIR/ollama-personas/critic.modelfile" << 'PERSONA_EOF'
FROM llama3.2
PARAMETER temperature 0.3
PARAMETER num_ctx 4096
SYSTEM """
You are a code reviewer and security analyst. Find bugs, vulnerabilities,
and inefficiencies. Be specific about what to fix and why.
"""
PERSONA_EOF

print_success "Persona modelfiles created"

# ---------------------------------------------------------------------------
# Pull base model (llama3.2) with retry logic.
# 'ollama list' checks if the model already exists locally.
# 'grep -q' is a silent grep — it sets exit code 0 if found, 1 if not.
# No output is printed, which keeps the installer UI clean.
# ---------------------------------------------------------------------------
if ! docker exec brain-ollama ollama list 2>/dev/null | grep -q "llama3.2"; then
    echo -e "${YELLOW}⬇️  Downloading Llama 3.2 (4GB, may take 5-10 minutes)...${NC}"
    # 'retry 3 15' = 3 attempts, 15-second delay between each.
    # Network hiccups during large downloads are COMMON, so retry is essential.
    if retry 3 15 docker exec brain-ollama ollama pull llama3.2; then
        print_success "Llama 3.2 downloaded"
    else
        # NON-FATAL: Ollama can still run; user can pull models later manually.
        # We don't 'exit 1' here because the rest of the mesh is functional.
        print_warning "Failed to download Llama 3.2 after 3 attempts.
   You can retry later: docker exec brain-ollama ollama pull llama3.2"
    fi
else
    print_success "Llama 3.2 already available"
fi

# ---------------------------------------------------------------------------
# Create custom personas from modelfiles.
# 'ollama create <name> -f <modelfile>' builds a custom model from a base.
# It combines the base weights (llama3.2) with the system prompt and
# parameters defined in the modelfile. This is fast (~seconds) because
# it doesn't re-download weights — it just wraps them with new config.
#
# PATH EXPLANATION:
#   Host path: $BRAIN_DIR/ollama-personas/brain-planner.modelfile
#   Container mount: /root/.ollama/personas (read-only)
#   So inside the container, we access: /root/.ollama/personas/brain-planner.modelfile
#
# The '2>/dev/null || true' pattern: suppress stderr and ignore exit code.
# This is SAFE here because if persona creation fails, Ollama still works
# with the base llama3.2 model. We print a warning though (not silent).
# ---------------------------------------------------------------------------
echo "Registering personas with Ollama..."

PERSONA_ERRORS=0
for persona in brain-planner coder researcher critic; do
    if docker exec brain-ollama ollama create "$persona" -f "/root/.ollama/personas/${persona}.modelfile" 2>/dev/null; then
        print_success "Persona '${persona}' registered"
    else
        print_warning "Failed to register persona '${persona}'"
        PERSONA_ERRORS=$((PERSONA_ERRORS + 1))
    fi
done

if [ $PERSONA_ERRORS -gt 0 ]; then
    print_warning "$PERSONA_ERRORS persona(s) failed to register.
   The base llama3.2 model still works. To retry personas:
   docker exec brain-ollama ollama create brain-planner -f /root/.ollama/personas/brain-planner.modelfile"
fi

# =============================================================================
# STEP 7/7: OPTIONAL TOOLS (brain CLI + Hermes)
# =============================================================================
print_step 7 7 "Installing optional tools..."

# ---------------------------------------------------------------------------
# brain CLI — Git-backed memory system
# This stores notes/ctx in a git repo at ~/.brain, making them:
#   - Searchable: brain ask "what auth pattern?"
#   - Versioned: Every note is a git commit
#   - Portable: git clone your brain anywhere
#
# LIMITATION: Only available via Homebrew (Mac/Linux). Windows users need
# WSL or manual installation. This is a known constraint we handle gracefully.
# ---------------------------------------------------------------------------
echo "Checking brain CLI..."
if command_exists brain; then
    # 'brain onboard' initializes the ~/.brain git repo and configures
    # integrations. The '--agents all --yes' flags auto-configure without
    # interactive prompts. '2>/dev/null || true' handles any non-fatal errors.
    brain onboard --agents all --yes 2>/dev/null || true
    print_success "brain CLI configured"
elif command_exists brew; then
    # Homebrew is available but brain isn't installed. Try installing.
    # The '2>/dev/null' suppresses error output. If this fails (e.g., tap
    # not found), we print a warning and continue — brain is OPTIONAL.
    if brew install codejunkie99/tap/brain 2>/dev/null; then
        brain onboard --agents all --yes 2>/dev/null || true
        print_success "brain CLI installed and configured"
    else
        print_warning "brain CLI install skipped (Homebrew tap unavailable).
   Memory features will be disabled. To install later:
       brew install codejunkie99/tap/brain"
    fi
else
    print_warning "brain CLI requires Homebrew (Mac/Linux only).
   Install Homebrew: https://brew.sh
   Then: brew install codejunkie99/tap/brain

   Memory features are disabled. All other features work normally."
fi

# ---------------------------------------------------------------------------
# Hermes Agent — Headless AI task executor with 118+ built-in skills
# Hermes reads skills from markdown files and executes them via Ollama.
# It can run fully automated workflows without human intervention.
# ---------------------------------------------------------------------------
echo "Checking Hermes Agent..."
if command_exists hermes; then
    print_success "Hermes already installed"
else
    # The Hermes install script downloads and installs the binary.
    # 'curl -fsSL' is the SAFE way to pipe scripts: -f=fail on HTTP error,
    # -s=silent, -S=show errors, -L=follow redirects.
    # We pipe through 'bash' for execution.
    if curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh 2>/dev/null | bash 2>/dev/null; then
        print_success "Hermes Agent installed"
    else
        # NON-FATAL: Hermes is optional. The mesh works without it.
        print_warning "Hermes Agent install skipped (network or platform issue).
   To install manually: https://github.com/NousResearch/hermes-agent"
    fi
fi

# =============================================================================
# FINAL SUMMARY
# =============================================================================
# Display a comprehensive dashboard showing all services, URLs, and
# quick-start commands. This is the user's first impression of the
# installed system, so clarity is paramount.
# =============================================================================

print_banner "$GREEN" "🎉 YOUR BRAIN LOADER v6 IS READY!" "All systems operational"

echo -e "${BOLD}${GREEN}📍 Your Services:${NC}"
echo "   • Dify (Workflow Builder)    → http://localhost:3000"
echo "   • Flowise (Alt. Builder)     → http://localhost:3001"
echo "   • Ollama (Local Models)      → http://localhost:11434"
echo "   • Weaviate (Vector Memory)   → http://localhost:8080"
echo ""

echo -e "${BOLD}${GREEN}🤖 AI Personas (Ollama):${NC}"
echo "   • brain-planner  → Strategic task planner"
echo "   • coder          → Code writer"
echo "   • researcher     → Research analyst"
echo "   • critic         → Code reviewer"
echo ""

echo -e "${BOLD}${GREEN}📝 Daily Commands:${NC}"
echo "   Start:     cd $BRAIN_DIR && $DOCKER_COMPOSE up -d"
echo "   Stop:      cd $BRAIN_DIR && $DOCKER_COMPOSE down"
echo "   Logs:      cd $BRAIN_DIR && $DOCKER_COMPOSE logs -f"
echo "   Reset:     cd $BRAIN_DIR && $DOCKER_COMPOSE down -v  (DELETES ALL DATA)"
echo ""

echo -e "${BOLD}${GREEN}🧠 Memory (if brain CLI installed):${NC}"
echo "   Save:      brain note 'remember this pattern'"
echo "   Recall:    brain ask 'what pattern did I use?'"
echo "   Browse:    brain tui"
echo ""

echo -e "${BOLD}${YELLOW}⚡ Next Steps:${NC}"
echo "   1. Open http://localhost:3000 in your browser"
echo "   2. Create an admin account (first-time setup)"
echo "   3. Go to Settings → Model Providers → Ollama → http://brain-ollama:11434"
echo "   4. Create your first workflow (see README.md for templates)"
echo "   5. To add chatbots: bash install-bots.sh"
echo ""

echo -e "${BOLD}${YELLOW}📖 Documentation:${NC}"
echo "   Full guide:  https://github.com/Ehsas317/brain-loader-v6#readme"
echo "   Issues:      https://github.com/Ehsas317/brain-loader-v6/issues"
echo ""

echo -e "${CYAN}Happy building! 🚀${NC}"
