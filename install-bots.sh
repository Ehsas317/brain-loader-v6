#!/bin/bash
# =============================================================================
# Brain Loader v6 — Universal Bot Gateway Installer (install-bots.sh)
# =============================================================================
# This script adds multi-platform chatbot capabilities to your Brain Loader mesh.
# It installs LangBot (multi-platform adapter), n8n (visual automation), and/or
# WhatsApp Business gateway based on your selection.
#
# PREREQUISITE: You MUST run install.sh FIRST to create the core mesh and
# the 'brain-mesh' Docker network. This script depends on that infrastructure.
#
# PLATFORMS SUPPORTED:
#   • Telegram  — Easiest setup. Message @BotFather for a free bot token.
#   • Discord   — Great for communities. Needs Discord Developer Portal.
#   • Slack     — Best for work teams. Needs Slack API app.
#   • WhatsApp  — Uses WhatsApp Web. Scan QR code with your phone.
#   • n8n       — Visual workflow builder for ALL platforms.
#
# BUG FIXES IN THIS VERSION:
#   - Added validation that core mesh exists before proceeding
#   - Auto-detects 'docker compose' vs 'docker-compose' (same as install.sh)
#   - Validates that 'brain-mesh' network exists (created by core install)
#   - Added input validation for PLATFORM_CHOICES
#   - Fixed COMPOSE_FILES building (intentional unquoted word splitting)
#   - Added non-zero exit codes on actual errors (vs silent failures)
#   - Better error messages with actionable fixes
# =============================================================================

# ---------------------------------------------------------------------------
# SHELL OPTIONS
# ---------------------------------------------------------------------------
set -e  # Exit immediately on any error
set -u  # Error on undefined variables
set -o pipefail  # Catch errors in pipelines

# ---------------------------------------------------------------------------
# COLOR DEFINITIONS
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------------------
BRAIN_DIR="$HOME/brain-loader-v6"
DOCKER_COMPOSE=""

# ---------------------------------------------------------------------------
# HELPER FUNCTIONS
# ---------------------------------------------------------------------------
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

print_step() {
    echo -e "${BLUE}🔍 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

command_exists() {
    command -v "$1" &> /dev/null
}

# ---------------------------------------------------------------------------
# PREREQUISITE CHECKS
# ---------------------------------------------------------------------------
# CRITICAL VALIDATION: This script REQUIRES the core mesh to exist first.
# The core install.sh creates:
#   1. $BRAIN_DIR directory
#   2. docker-compose.yml file
#   3. 'brain-mesh' Docker network
# Without these, the bot compose files will fail to start.

# Check 1: Does the Brain Loader directory exist?
if [ ! -d "$BRAIN_DIR" ]; then
    print_error "brain-loader-v6 directory not found at $BRAIN_DIR.

   You must run the core installer FIRST:
       bash install.sh

   This creates the required infrastructure (network, volumes, base services)."
fi

# Change to the Brain Loader directory. All subsequent paths are relative.
cd "$BRAIN_DIR"

# Check 2: Does the core docker-compose.yml exist?
if [ ! -f "docker-compose.yml" ]; then
    print_error "Core docker-compose.yml not found in $BRAIN_DIR.

   Your installation may be incomplete. Please re-run:
       bash install.sh"
fi

# Check 3: Auto-detect Docker Compose command (same logic as install.sh).
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
elif docker-compose --version &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    print_error "Docker Compose not found. Please install Docker Desktop or:

   Linux: sudo apt install docker-compose-plugin -y"
fi

# Check 4: Is Docker daemon running?
if ! docker info &> /dev/null; then
    print_error "Docker daemon is not running.

   • Mac/Windows: Open Docker Desktop and wait for it to start
   • Linux:       sudo systemctl start docker
   • WSL2:        wsl.exe -d docker-desktop"
fi

# Check 5: Does the 'brain-mesh' network exist?
# The core docker-compose.yml defines 'networks: brain-mesh' with 'name: brain-mesh'.
# Bot compose files reference this as 'external: true'. If it doesn't exist,
# 'docker compose up' will fail with a confusing network error.
if ! docker network ls --format '{{.Name}}' | grep -q '^brain-mesh$'; then
    print_error "The 'brain-mesh' Docker network does not exist.

   This means the core mesh was never started. Please run:
       cd $BRAIN_DIR && $DOCKER_COMPOSE up -d

   Then re-run this bot installer."
fi

# Check 6: Are the core services running?
# We check Dify API specifically since LangBot and n8n need to connect to it.
if ! docker ps --format '{{.Names}}' | grep -q '^brain-dify-api$'; then
    print_warning "Dify API is not running. Starting core services first..."
    $DOCKER_COMPOSE up -d
    # Give services a moment to start. The '|| true' handles race conditions.
    sleep 5 || true
fi

# =============================================================================
# WELCOME BANNER
# =============================================================================
print_banner "$CYAN" "🤖 BRAIN LOADER v6 — Universal Bot Gateway" "Add Telegram, Discord, Slack, WhatsApp & More"

# =============================================================================
# PLATFORM SELECTION
# =============================================================================
echo ""
echo -e "${YELLOW}🎮 Which platforms do you want to enable?${NC}"
echo "   Type numbers separated by spaces, then press ENTER"
echo ""
echo "   1) Telegram     — Easiest. Free. Message @BotFather for token."
echo "   2) Discord      — Great for communities. Need Developer Portal."
echo "   3) Slack        — Best for work teams. Need Slack API app."
echo "   4) WhatsApp     — Uses WhatsApp Web. Scan QR code with phone."
echo "   5) n8n          — Visual workflow builder for ALL platforms."
echo "   6) ALL OF ABOVE — Start everything at once."
echo ""

# Read user input with default "1 5" (Telegram + n8n — easiest combo).
read -p "Enter choices [default: 1 5]: " PLATFORM_CHOICES
PLATFORM_CHOICES=${PLATFORM_CHOICES:-"1 5"}

# Validate input: reject completely empty or obviously wrong input.
# We trim whitespace and check if anything remains.
TRIMMED=$(echo "$PLATFORM_CHOICES" | tr -d '[:space:]')
if [ -z "$TRIMMED" ]; then
    print_warning "No input detected. Using default: 1 5 (Telegram + n8n)"
    PLATFORM_CHOICES="1 5"
fi

# Additional validation: warn if input contains characters other than digits and spaces.
# 'tr -d' removes all digits and spaces. If anything remains, it's invalid input.
INVALID_CHARS=$(echo "$PLATFORM_CHOICES" | tr -d '[:digit:][:space:]')
if [ -n "$INVALID_CHARS" ]; then
    print_warning "Invalid characters detected: '$INVALID_CHARS'"
    print_warning "Using default: 1 5 (Telegram + n8n)"
    PLATFORM_CHOICES="1 5"
fi

print_success "Platform choices: $PLATFORM_CHOICES"

# =============================================================================
# CREATE COMPOSE FILES BASED ON SELECTION
# =============================================================================
print_step "Creating bot gateway files..."

# ---------------------------------------------------------------------------
# LANGGATEWAY (LangBot) — Platforms 1, 2, 3, 4, 6
# LangBot is needed for Telegram, Discord, Slack, and WhatsApp.
# We check if ANY of these platforms were selected.
#
# 'grep -qE "pattern"' uses Extended Regex. The pipe '|' means OR.
# So "1|2|3|4|6" matches if the input contains ANY of those digits.
# NOTE: This could theoretically match "16" as containing "1", but since
# users enter space-separated single digits, this works correctly in practice.
# ---------------------------------------------------------------------------
if echo "$PLATFORM_CHOICES" | grep -qE "1|2|3|4|6"; then
    # Write the LangBot docker compose overlay.
    # The '\'EOF\'' (quoted delimiter) prevents shell variable expansion.
    # This is SAFE because the compose file has no shell variables to expand.
    cat > docker-compose.bots.yml << 'EOF'
version: "3.8"

services:
  langbot:
    image: rockchin/langbot:latest
    container_name: brain-langbot
    ports:
      - "5300:5300"
    environment:
      - LANGBOT_CONFIG_PATH=/app/data/config
      - LANGBOT_CONFIG_PROVIDER=yaml
      - LANGBOT_PLUGIN_PATH=/app/data/plugins
    volumes:
      - langbot-data:/app/data
      - ./langbot-config:/app/data/config:ro
    networks:
      - brain-mesh
    restart: unless-stopped
    depends_on:
      - dify-api

volumes:
  langbot-data:

networks:
  brain-mesh:
    external: true
    name: brain-mesh
EOF
    print_success "LangBot config created (docker-compose.bots.yml)"
fi

# ---------------------------------------------------------------------------
# n8n — Platforms 5, 6
# n8n is a visual workflow builder. Selected independently of LangBot.
# ---------------------------------------------------------------------------
if echo "$PLATFORM_CHOICES" | grep -qE "5|6"; then
    cat > docker-compose.n8n.yml << 'EOF'
version: "3.8"

services:
  n8n:
    image: n8nio/n8n:latest
    container_name: brain-n8n
    ports:
      - "5678:5678"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=brain
      - N8N_BASIC_AUTH_PASSWORD=loader-v6-n8n
      - WEBHOOK_URL=http://localhost:5678
      - N8N_ENCRYPTION_KEY=brain-loader-v6-encrypt-key-change-me
    volumes:
      - n8n-data:/home/node/.n8n
    networks:
      - brain-mesh
    restart: unless-stopped

volumes:
  n8n-data:

networks:
  brain-mesh:
    external: true
    name: brain-mesh
EOF
    print_success "n8n config created (docker-compose.n8n.yml)"
fi

# ---------------------------------------------------------------------------
# WHATSAPP BUSINESS — Platforms 4, 6
# WPPConnect for production WhatsApp use (separate from LangBot's WhatsApp Web).
# ---------------------------------------------------------------------------
if echo "$PLATFORM_CHOICES" | grep -qE "4|6"; then
    cat > docker-compose.whatsapp.yml << 'EOF'
version: "3.8"

services:
  whatsapp:
    image: wppconnect/wppconnect-server:latest
    container_name: brain-whatsapp
    ports:
      - "21465:21465"
    environment:
      - SECRET_KEY=brain-loader-v6-whatsapp-change-me
      - PORT=21465
      - NODE_ENV=production
    volumes:
      - whatsapp-data:/usr/src/wpp-server
    networks:
      - brain-mesh
    restart: unless-stopped

volumes:
  whatsapp-data:

networks:
  brain-mesh:
    external: true
    name: brain-mesh
EOF
    print_success "WhatsApp config created (docker-compose.whatsapp.yml)"
fi

# =============================================================================
# START ALL SELECTED SERVICES
# =============================================================================
print_step "Starting bot services..."

# Build the compose file chain.
# We ALWAYS include the core docker-compose.yml first (it defines the network).
# Then we append any overlay files that were just created.
#
# CRITICAL: COMPOSE_FILES is intentionally UNQUOTED when used.
# Each '-f filename' needs to be a separate argument to 'docker compose'.
# Quoting would pass the entire string as ONE argument, breaking the command.
# Word splitting here is DESIRED BEHAVIOR, not a bug.
COMPOSE_FILES="-f docker-compose.yml"

# '[ -f filename ]' checks if a file exists (was created above).
# '&&' means: if the file exists, append it to COMPOSE_FILES.
[ -f docker-compose.bots.yml ]    && COMPOSE_FILES="$COMPOSE_FILES -f docker-compose.bots.yml"
[ -f docker-compose.n8n.yml ]     && COMPOSE_FILES="$COMPOSE_FILES -f docker-compose.n8n.yml"
[ -f docker-compose.whatsapp.yml ] && COMPOSE_FILES="$COMPOSE_FILES -f docker-compose.whatsapp.yml"

# Pull images first (fail fast if network issues), then start.
# We use 'eval' carefully here — COMPOSE_FILES contains safe, script-generated content only.
echo "Pulling images..."
$DOCKER_COMPOSE $COMPOSE_FILES pull

# Start all services.
# The unquoted $COMPOSE_FILES is INTENTIONAL — see explanation above.
echo "Starting containers..."
$DOCKER_COMPOSE $COMPOSE_FILES up -d

print_success "All bot services started"

# =============================================================================
# SETUP INSTRUCTIONS
# =============================================================================
# Display platform-specific setup instructions based on what was selected.
# These are the MANUAL steps users must complete outside this script.
# =============================================================================

print_banner "$GREEN" "🤖 YOUR BOT GATEWAY IS READY!" "Follow the setup steps below"

# Telegram setup instructions
if echo "$PLATFORM_CHOICES" | grep -qE "1|6"; then
    echo -e "${BOLD}${GREEN}📱 Telegram Setup:${NC}"
    echo "   1. Open Telegram → Search @BotFather → Send /newbot"
    echo "   2. Name your bot → Copy the API token (looks like: 123456789:ABC...)"
    echo "   3. Open http://localhost:5300 in your browser"
    echo "   4. Go to Pipelines → ChatPipeline → AI Capability"
    echo "   5. Set Runner to 'Dify Service API'"
    echo "   6. Base URL: http://brain-dify-api:5001/v1"
    echo "   7. Get API Key from Dify → Your App → Access API → Create Key"
    echo "   8. Go to Platform Adapters → Telegram → Paste token → Enable"
    echo "   9. Message your bot on Telegram — it will respond via Dify!"
    echo ""
fi

# Discord setup instructions
if echo "$PLATFORM_CHOICES" | grep -qE "2|6"; then
    echo -e "${BOLD}${GREEN}💬 Discord Setup:${NC}"
    echo "   1. Go to https://discord.com/developers/applications"
    echo "   2. Click 'New Application' → Name it → Create"
    echo "   3. Go to 'Bot' section → 'Add Bot' → Copy the Token"
    echo "   4. Go to 'OAuth2 → URL Generator':"
    echo "      • Scopes: bot"
    echo "      • Bot Permissions: Send Messages, Read Message History"
    echo "   5. Copy the generated URL → Open in browser → Add to your server"
    echo "   6. Open http://localhost:5300 → Platform Adapters → Discord"
    echo "   7. Paste your token → Enable"
    echo "   8. In Discord, @mention your bot — it responds via Dify!"
    echo ""
fi

# Slack setup instructions
if echo "$PLATFORM_CHOICES" | grep -qE "3|6"; then
    echo -e "${BOLD}${GREEN}💼 Slack Setup:${NC}"
    echo "   1. Go to https://api.slack.com/apps → Create New App → From scratch"
    echo "   2. Go to 'OAuth & Permissions' → Add Bot Token Scopes:"
    echo "      • chat:write, chat:write.public, im:history, app_mentions:read"
    echo "   3. 'Install to Workspace' → Copy 'Bot User OAuth Token'"
    echo "   4. Go to 'Event Subscriptions' → Enable → Subscribe to bot events:"
    echo "      • app_mention, message.im"
    echo "   5. Open http://localhost:5300 → Platform Adapters → Slack"
    echo "   6. Paste your token → Enable"
    echo "   7. DM your bot or @mention it in a channel!"
    echo ""
fi

# WhatsApp setup instructions
if echo "$PLATFORM_CHOICES" | grep -qE "4|6"; then
    echo -e "${BOLD}${GREEN}📞 WhatsApp Setup:${NC}"
    echo "   1. Open http://localhost:21465 in your browser"
    echo "   2. A QR code will appear (expires in 2 minutes — be ready!)"
    echo "   3. On your phone: WhatsApp → Settings → Linked Devices → Link a Device"
    echo "   4. Scan the QR code with your phone camera"
    echo "   5. Your WhatsApp account is now connected to the AI brain!"
    echo ""
    echo -e "   ${YELLOW}⚠️  NOTE: This uses your personal WhatsApp account.${NC}"
    echo "   For business use, consider WhatsApp Business API instead."
    echo ""
fi

# n8n setup instructions
if echo "$PLATFORM_CHOICES" | grep -qE "5|6"; then
    echo -e "${BOLD}${GREEN}🔧 n8n Visual Builder Setup:${NC}"
    echo "   1. Open http://localhost:5678"
    echo "   2. Login: brain / loader-v6-n8n"
    echo "   3. Click 'Add Workflow'"
    echo "   4. Add a Trigger node (Telegram Trigger / Discord Trigger / Webhook)"
    echo "   5. Add an HTTP Request node to call Dify:"
    echo "      • Method: POST"
    echo "      • URL: http://brain-dify-api:5001/v1/chat-messages"
    echo "      • Headers: Authorization: Bearer YOUR_DIFY_API_KEY"
    echo "   6. Add a Send Message node to reply"
    echo "   7. Connect nodes → Save → Activate"
    echo ""
fi

# =============================================================================
# DAILY COMMANDS
# =============================================================================
echo -e "${BOLD}${YELLOW}⚡ Quick Commands:${NC}"
echo "   View LangBot logs:   docker logs brain-langbot -f"
echo "   View n8n logs:       docker logs brain-n8n -f"
echo "   View WhatsApp logs:  docker logs brain-whatsapp -f"
echo "   Stop all bots:       cd $BRAIN_DIR && $DOCKER_COMPOSE $COMPOSE_FILES down"
echo "   Restart:             cd $BRAIN_DIR && $DOCKER_COMPOSE $COMPOSE_FILES restart"
echo "   Check all services:  docker ps --format 'table {{.Names}}\t{{.Status}}'"
echo ""

echo -e "${CYAN}Happy chatting! 🤖${NC}"
