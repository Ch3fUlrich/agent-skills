# Manual Installation Guide — MCP Server Stack

This guide covers every step to set up the self-hosted MCP server stack
manually. Use this when you can't run the automated scripts or want to
understand each component.

## Prerequisites

| Requirement | Windows Command | Linux Command |
|---|---|---|
| Docker Desktop | `winget install Docker.DockerDesktop` | `curl -fsSL https://get.docker.com \| sh` |
| uv | `winget install --id=astral-sh.uv -e` | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| Git | `winget install Git.Git` | `apt install git` / `brew install git` |
| curl (for API tests) | Built-in (`Invoke-WebRequest`) | `apt install curl` / built-in on macOS |

---

## Step 1: Start Docker Services

### 1a. Launch Docker Desktop

- **Windows**: Start Docker Desktop from the Start menu. Wait for the whale icon to stop animating.
- **Linux**: `sudo systemctl start docker`

### 1b. Start Qdrant and Ollama

```powershell
# Windows
cd C:\Users\mauls\Documents\Code\agent-skills\mcp-servers
docker compose up -d
```

```bash
# Linux
cd ~/Documents/Code/agent-skills/mcp-servers
docker compose up -d
```

### 1c. Verify Services

```powershell
# Qdrant health check
Invoke-WebRequest -Uri "http://localhost:6333/health" -UseBasicParsing
# Should return: {"title":"qdrant - vector search engine","version":"..."}

# Ollama API
Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -UseBasicParsing
# Should return: {"models":[...]}
```

```bash
# Qdrant health check
curl http://localhost:6333/health

# Ollama API
curl http://localhost:11434/api/tags
```

### 1d. Pull the bge-m3 Embedding Model

```powershell
docker exec -it mcp-ollama ollama pull bge-m3
```

```bash
docker exec -it mcp-ollama ollama pull bge-m3
```

This downloads ~2 GB. Wait for completion. Verify:

```powershell
docker exec mcp-ollama ollama list
# Should include: bge-m3:latest
```

### 1e. (Optional) Test Embedding

```powershell
$body = '{"model":"bge-m3:latest","input":"test embedding"}'
Invoke-WebRequest -Uri "http://localhost:11434/api/embed" -Method POST -Body $body -ContentType "application/json" -UseBasicParsing
```

```bash
curl -X POST http://localhost:11434/api/embed -d '{"model":"bge-m3:latest","input":"test embedding"}'
```

Should return a 1024-dimensional vector.

---

## Step 2: Install Serena MCP Server

### 2a. Install via uv

```powershell
# Windows & Linux
uv tool install serena-agent
```

### 2b. Verify Installation

```powershell
serena --version
# Should output version number
```

### 2c. Test Serena Tool Listing

```powershell
# Create a temporary test project
serena project create "C:\Users\mauls\Documents\Code\agent-skills" --index

# List available tools
serena tools list --all --project C:\Users\mauls\Documents\Code\agent-skills
```

```bash
serena project create ~/Documents/Code/agent-skills --index
serena tools list --all --project ~/Documents/Code/agent-skills
```

You should see tools like `find_symbol`, `find_references`, `get_file_structure`, etc.

---

## Step 3: Install Superpowers MCP Server

```powershell
# Windows & Linux
uv tool install --from git+https://github.com/erophames/superpowers-mcp superpowers-mcp
```

Verify:

```powershell
superpowers-mcp --help
```

---

## Step 4: Configure CodeWhale

### 4a. Copy MCP Config

```powershell
# Windows
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.codewhale" | Out-Null
Copy-Item "C:\Users\mauls\Documents\Code\agent-skills\mcp-servers\config\mcp.json" "$env:USERPROFILE\.codewhale\mcp.json" -Force
```

```bash
# Linux
mkdir -p ~/.codewhale
cp ~/Documents/Code/agent-skills/mcp-servers/config/mcp.json ~/.codewhale/mcp.json
```

### 4b. Verify Config

```powershell
Get-Content "$env:USERPROFILE\.codewhale\mcp.json" | ConvertFrom-Json | Select-Object -ExpandProperty servers | Get-Member -MemberType NoteProperty
# Should show: serena, mem0, superpowers
```

```bash
cat ~/.codewhale/mcp.json | python3 -m json.tool
```

### 4c. Understanding the Config

The `mcp.json` defines three stdio MCP servers:

| Server | Command | Purpose |
|---|---|---|
| `serena` | `uvx --from serena-agent serena start-mcp-server --project-from-cwd` | Semantic code navigation |
| `mem0` | `uvx --from git+https://... mem0-mcp-selfhosted` | Persistent memory |
| `superpowers` | `uvx --from git+https://... superpowers-mcp` | Workflow skills |

Each is a stdio process that CodeWhale spawns on demand.

---

## Step 5: Restart CodeWhale

Close and reopen CodeWhale. The MCP servers auto-load on startup.

Inside CodeWhale, run:

```
/mcp
```

This opens the MCP manager. You should see all three servers with green
status indicators.

```
/mcp validate
```

This reconnects and refreshes the tool list.

---

## Step 6: Test MCP Tools

Inside a CodeWhale session:

### Serena Test

```
Find the definition of the main function in IsingModel.py
```

The agent should use `mcp_serena_find_symbol` instead of reading the whole file.

### Mem0 Test

```
Remember: The IsingModelSimulator uses a Metropolis algorithm for Monte Carlo simulation
```

Then in a **new session**:

```
What do you know about the IsingModelSimulator?
```

The agent should recall the stored memory.

### Superpowers Test

```
Use the TDD skill to add a test for the IsingModel class
```

The agent should use `mcp_superpowers_use_skill("tdd")`.

---

## Step 7: Bootstrap Memories (Optional)

```powershell
# Create a bootstrap file with key project knowledge
@"
Code monorepo at C:\Users\mauls\Documents\Code containing 20+ projects
Primary languages: Python, TypeScript, Shell, C#
Key frameworks: PyTorch, DeepLabCut, MARBLE, MaxEnt, IsingModel
User prefers Python type hints and uv for package management
All MCP servers are self-hosted, no cloud API keys
"@ | Out-File "C:\Users\mauls\Documents\Code\agent-skills\mcp-servers\data\mem0\bootstrap_memories.txt" -Encoding UTF8
```

Then ask your agent to read and remember this file.

---

## Troubleshooting

### Docker issues

```powershell
# Check if Docker is running
docker info

# Restart Docker containers
cd C:\Users\mauls\Documents\Code\agent-skills\mcp-servers
docker compose down
docker compose up -d

# Check logs
docker compose logs qdrant --tail=50
docker compose logs ollama --tail=50
```

### Serena not found

```powershell
# uv tools are installed to a user-local directory
uv tool dir

# Add to PATH if not already
$env:Path += ";$env:USERPROFILE\.local\bin;$env:USERPROFILE\.cargo\bin"
```

### MCP tools not appearing in CodeWhale

```powershell
# Check CodeWhale MCP status
codewhale-tui doctor
codewhale-tui mcp validate
codewhale-tui mcp list

# Force regenerate config
codewhale-tui mcp init --force
# Then re-copy the custom config
Copy-Item "C:\Users\mauls\Documents\Code\agent-skills\mcp-servers\config\mcp.json" "$env:USERPROFILE\.codewhale\mcp.json" -Force
```

### Ollama using CPU instead of GPU

```powershell
# Check if NVIDIA container toolkit is available
docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi

# If not, Ollama falls back to CPU (slower but functional)
# For GPU support on Windows: enable WSL2 GPU acceleration in Docker Desktop settings
```

### Complete reset

```powershell
# Remove everything and start over
cd C:\Users\mauls\Documents\Code\agent-skills\mcp-servers
docker compose down -v
Remove-Item -Recurse -Force .\data
uv tool uninstall serena-agent superpowers-mcp
Remove-Item "$env:USERPROFILE\.codewhale\mcp.json"
# Then re-run from Step 1
```

---

## Manual TODO Checklist

- [ ] Docker Desktop installed and running
- [ ] Docker services started (`docker compose up -d`)
- [ ] Qdrant healthy (`curl localhost:6333/health`)
- [ ] Ollama running (`curl localhost:11434/api/tags`)
- [ ] bge-m3 model pulled (`docker exec mcp-ollama ollama pull bge-m3`)
- [ ] uv installed (`uv --version`)
- [ ] Serena installed (`serena --version`)
- [ ] Superpowers installed (`superpowers-mcp --help`)
- [ ] MCP config copied to `~/.codewhale/mcp.json`
- [ ] CodeWhale restarted
- [ ] `/mcp` shows all 3 servers connected
- [ ] Tested: `mcp_serena_find_symbol` works
- [ ] Tested: `mcp_mem0_remember` works
- [ ] Tested: `mcp_superpowers_use_skill` works
- [ ] Knowledge transferred from Claude Code (if applicable)
- [ ] Token savings measured (compare `/cost` before/after)

---

## Next Steps

1. Use CodeWhale with MCP for a week to build up Mem0 knowledge and Serena indices
2. Track token usage: run `/cost` at the start and end of sessions
3. After confirming stability, follow `TODO.md` to migrate Claude Code
4. Share any issues or improvements as GitHub issues in the `agent-skills` repo
