# Mesh (formerly Brain Loader v6) — The Visual Mesh + Universal Bot Gateway

> **One command.** Your entire AI team — brain, memory, skills, bots on 10+ platforms — running locally for free. No coding. Copy, paste, chat.

[![Docker](https://img.shields.io/badge/Docker-Required-blue?logo=docker)](https://docker.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Ollama](https://img.shields.io/badge/Ollama-Llama3.2-orange?logo=ollama)](https://ollama.com)

---

## Table of Contents

- [What Makes Mesh Different](#what-makes-mesh-different)
- [The 6-Layer Stack](#the-6-layer-stack)
- [Quick Start](#quick-start)
- [System Requirements](#system-requirements)
- [File Overview](#file-overview)
- [Bug Fixes in This Release](#bug-fixes-in-this-release)
- [Architecture](#architecture)
- [Daily Commands](#daily-commands)
- [Adding Chatbots](#adding-chatbots)
- [Troubleshooting](#troubleshooting)
- [Security Notes](#security-notes)
- [License](#license)

---

## What Makes Mesh Different

| | v4 (Python) | v5 (Trio) | **v6 (Mesh)** |
|---|---|---|---|
| **Setup** | `pip install`, edit YAML | `pip install`, edit YAML | **One Docker command** |
| **Orchestration** | Python classes | Trio nurseries | **Visual drag-and-drop** |
| **Interface** | Terminal REPL | Terminal REPL | **Web UI + Telegram + Discord + Slack + WhatsApp** |
| **Skills** | Python code | Python code | **Markdown files** |
| **For non-coders?** | ❌ | ❌ | **✅ Yes** |
| **Unique factor** | Async router | Structured concurrency | **Visual mesh of real FOSS tools** |

**Mesh is not a Python program. It is a network of best-in-class open-source tools that talk to each other.** You are the conductor. The tools are the orchestra.

---

## The 6-Layer Stack

```
┌─────────────────────────────────────────────────────────────┐
│ LAYER 1: THE FACE        Odysseus (Web UI)                  │
│ Web UI, chat, documents  localhost:7000                     │
├─────────────────────────────────────────────────────────────┤
│ LAYER 2: THE BRAIN       Dify (LangGenius)                  │
│ Visual workflow builder  localhost:3000                     │
├─────────────────────────────────────────────────────────────┤
│ LAYER 3: THE MUSCLE      Hermes Agent (Nous Research)       │
│ 118+ built-in skills     ~/.hermes/skills/                  │
├─────────────────────────────────────────────────────────────┤
│ LAYER 4: THE MEMORY      brain CLI (codejunkie99)           │
│ Git-backed memory        ~/.brain (a git repo!)             │
├─────────────────────────────────────────────────────────────┤
│ LAYER 5: THE ENGINE      Ollama                             │
│ Local model runner       localhost:11434                    │
├─────────────────────────────────────────────────────────────┤
│ LAYER 6: THE SAFETY NET  GitHub Actions (FREE)              │
│ 2,000 min/month          Cloud backup execution             │
└─────────────────────────────────────────────────────────────┘
```

---

## Quick Start

### Prerequisites

You need exactly **two things**:

1. **Docker Desktop** — [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop)
   - Verify: `docker --version` should show `Docker version 26.x.x` or higher
2. **GitHub Account** — [github.com](https://github.com) (Free plan)
   - For 2,000 free GitHub Actions minutes/month (~33 hours of cloud compute)

### One-Command Install

```bash
# Download and run the installer
curl -fsSL https://raw.githubusercontent.com/Ehsas317/mesh/main/install.sh | bash
```

Or manually:

```bash
git clone https://github.com/Ehsas317/mesh.git
cd mesh
bash install.sh
```

The installer will:
1. ✅ Check Docker is installed and running
2. 🎮 Ask your execution mode (Local / Cloud / Hybrid)
3. 🐳 Create Docker Compose configuration
4. ⬇️ Download all AI tools (3-5 minutes on first run)
5. 🚀 Start all services with health checks
6. 🎭 Create AI personas (planner, coder, researcher, critic)
7. 🧠 Optionally install brain CLI and Hermes Agent

### After Install — Your Services

| Service | URL | What It Does |
|---------|-----|-------------|
| **Dify** | http://localhost:3000 | Visual AI workflow builder |
| **Flowise** | http://localhost:3001 | Simpler alternative builder |
| **Ollama** | http://localhost:11434 | Local AI models (free, private) |
| **Weaviate** | http://localhost:8080 | Vector memory for documents |

---

## System Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| **RAM** | 4 GB | 8 GB |
| **Disk** | 10 GB free | 20 GB free |
| **CPU** | Any (slower) | 4+ cores |
| **OS** | Linux, macOS, Windows (WSL2) | Linux/macOS |

**For 4GB RAM systems:** Run only Ollama + Flowise:
```bash
cd ~/mesh && docker compose up -d ollama flowise
```

---

## File Overview

```
mesh/
├── docker-compose.yml              ← Core mesh (6 services)
├── docker-compose.bots.yml         ← LangBot gateway (overlay)
├── docker-compose.n8n.yml          ← n8n automation (overlay)
├── docker-compose.whatsapp.yml     ← WhatsApp Business (overlay)
├── install.sh                      ← Main installer (7 steps)
├── install-bots.sh                 ← Bot gateway installer
├── ollama-personas/
│   ├── brain-planner.modelfile     ← Strategic task planner
│   ├── coder.modelfile             ← Code writer
│   ├── researcher.modelfile        ← Research analyst
│   └── critic.modelfile            ← Code reviewer
├── config/
│   └── hermes-config.yaml          ← Hermes Agent template
├── .github/
│   └── workflows/
│       └── wave.yml                ← GitHub Actions cloud execution
└── README.md                       ← This file
```

**Every file has comprehensive inline comments** explaining what each line does and why it works that way.

---

## Bug Fixes in This Release

### Critical Fixes

1. **Fixed MODE variable not being substituted into docker-compose.yml**
   - **Original bug:** Used `<< 'EOF'` (quoted heredoc) which **prevents ALL shell variable expansion**. The `${MODE:-hybrid}` was written literally into the file.
   - **Fix:** Two-phase approach — write a placeholder (`__EXEC_MODE__`), then use `sed` to replace it with the actual value.

2. **Added Docker daemon running check**
   - **Original bug:** Only checked if `docker` binary existed. Many users have Docker installed but the daemon not running (especially Docker Desktop on macOS/Windows).
   - **Fix:** Added `docker info` check that actually communicates with the daemon.

3. **Auto-detect docker compose vs docker-compose**
   - **Original bug:** Checked for both but only used `docker compose` (space), which fails on systems with only the old standalone.
   - **Fix:** Stores the working command in `$DOCKER_COMPOSE` variable and uses it consistently throughout.

4. **Added health checks to all infrastructure services**
   - **Original bug:** Dify would crash-loop 3-5 times on startup because Postgres/Redis/Weaviate weren't actually ready — just their containers were "running."
   - **Fix:** Added `healthcheck` blocks to postgres, redis, weaviate, and ollama with `depends_on: condition: service_healthy` in Dify.

5. **Sanitized GitHub Actions user input**
   - **Original bug:** `${{ github.event.inputs.goal }}` was directly interpolated into shell commands, enabling shell injection attacks.
   - **Fix:** Passed user input via `env:` (environment variables), which the shell treats as data, not code.

6. **Added system requirements checks**
   - **Original bug:** No warning for insufficient RAM or disk space. Users would get cryptic failures mid-install.
   - **Fix:** Added `get_ram_gb()` and `get_free_disk_gb()` functions with clear warnings and suggested alternatives.

7. **Added retry logic for network operations**
   - **Original bug:** `ollama pull llama3.2` would fail permanently on a single network hiccup.
   - **Fix:** Added `retry()` helper with configurable attempts and delays.

8. **Added container readiness wait loops**
   - **Original bug:** Used `sleep 5` (arbitrary wait) and hoped containers were ready.
   - **Fix:** Replaced with `wait_for_container()` that polls Docker until services report healthy.

9. **Fixed install-bots.sh prerequisite validation**
   - **Original bug:** Would fail with confusing "network not found" errors if core mesh wasn't installed.
   - **Fix:** Added explicit checks for: directory existence, docker-compose.yml existence, mesh network existence, and Dify API running.

10. **Added input validation for all user prompts**
    - **Original bug:** No validation of MODE_CHOICE or PLATFORM_CHOICES input.
    - **Fix:** Added case statements, regex validation, and sensible fallbacks.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ YOU (on your phone/computer)                                │
│ Telegram │ Discord │ Slack │ WhatsApp │ Web Browser         │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ LAYER 1: BOT GATEWAY     LangBot / n8n / Dify Plugins      │
│ Multi-platform adapter   localhost:5300 / :5678             │
├─────────────────────────────────────────────────────────────┤
│ LAYER 2: AI BRAIN        Dify (langgenius/dify)            │
│ Visual workflow builder  localhost:3000                     │
├─────────────────────────────────────────────────────────────┤
│ LAYER 3: EXECUTION       Ollama / APIs / Tools             │
│ Local models             Free, private                      │
│ Cloud APIs               Fast, cheap                        │
│ Tools (web scrape, etc.) Dify's 50+ built-in tools         │
└─────────────────────────────────────────────────────────────┘
```

**All platforms share the same Dify brain.** One workflow, many faces.

---

## Daily Commands

```bash
# Start everything
cd ~/mesh && docker compose up -d

# Stop everything
cd ~/mesh && docker compose down

# View logs
cd ~/mesh && docker compose logs -f

# Reset everything (DELETES ALL DATA — use with caution!)
cd ~/mesh && docker compose down -v

# Check service status
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# View specific service logs
docker logs mesh-dify-api -f
docker logs mesh-ollama -f
docker logs mesh-postgres -f
```

---

## Adding Chatbots

After the core mesh is running, add chatbots with:

```bash
cd ~/mesh
bash install-bots.sh
```

This interactive installer lets you choose:
- 📱 **Telegram** — Easiest. Free. Message @BotFather.
- 💬 **Discord** — Great for communities.
- 💼 **Slack** — Best for work teams.
- 📞 **WhatsApp** — Uses WhatsApp Web. Scan QR code.
- 🔧 **n8n** — Visual workflow builder for ALL platforms.

**All platforms share the same Dify brain.** Configure your workflow once, access it everywhere.

---

## Troubleshooting

### "Docker not found"
**Fix:** Install Docker Desktop → Restart computer → Try again.

### "Port already in use"
**Fix:** Change the port in `docker-compose.yml`:
```yaml
ports:
  - "3002:3000"  # Use 3002 instead of 3000
```

### "Ollama model not responding"
```bash
# Check if Ollama is running
docker compose ps
docker compose logs mesh-ollama

# Retry model download
docker exec mesh-ollama ollama pull llama3.2
```

### "Dify won't connect to Ollama"
**Fix:** In Dify → Settings → Model Providers → Ollama, use `http://mesh-ollama:11434` (NOT localhost). Docker containers talk to each other by service name.

### "Out of memory"
**Fix:** Run minimal stack only:
```bash
docker compose up -d ollama flowise
```

### "brain command not found"
**Fix:** Install Homebrew → `brew install codejunkie99/tap/brain`

---

## Security Notes

- **Default passwords** in docker-compose.yml are for LOCAL DEVELOPMENT ONLY.
- **Change `SECRET_KEY`** before any non-local deployment: `openssl rand -hex 32`
- **Weaviate** has anonymous access enabled — fine for local, disable for production.
- **n8n encryption key** should be changed: `openssl rand -hex 32`
- **Never commit real API tokens** to git. Use environment variables.
- **GitHub Actions** runs on public cloud — don't send sensitive data.

---

## Cost Breakdown

| Setup | Monthly Cost | Speed | Privacy | Best For |
|-------|-------------|-------|---------|----------|
| **100% Local** (Ollama only) | $0 | Slow (your CPU) | Perfect | Daily use, privacy |
| **Hybrid** (Ollama + DeepSeek) | ~$0.50-2 | Fast | Good | Most projects |
| **100% API** (DeepSeek/Groq) | ~$5-15 | Very fast | Cloud | Speed-critical |
| **GitHub Actions** | $0 (2,000 min) | Medium | Public only | Background tasks |

---

## License

All components are open source:

- **Dify:** Apache-2.0 (LangGenius)
- **Flowise:** MIT (FlowiseAI)
- **LangBot:** Open Source (rockchin)
- **n8n:** Fair-code (n8n.io)
- **Ollama:** MIT (Ollama)
- **brain CLI:** MIT (codejunkie99)
- **Hermes:** MIT (Nous Research)
- **This project:** MIT License

**Total vendor lock-in: Zero.** Every tool is replaceable.

---

*Built with: Dify + Flowise + LangBot + n8n + Hermes + brain + Ollama + GitHub Actions + Docker.*
*For non-coders who think like coders.*
*Chat anywhere. Think everywhere.*
