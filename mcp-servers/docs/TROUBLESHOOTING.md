# Troubleshooting

## Common Issues

### Docker services won't start

**Symptom**: `docker compose up -d` fails or Qdrant/Ollama unreachable.

```powershell
# Check Docker is running
docker info

# Check container status
docker compose ps

# Check logs
docker compose logs qdrant
docker compose logs ollama

# Full restart
docker compose down
docker compose up -d
```

**Port conflicts**: If ports 6333 or 11434 are in use:
```powershell
# Check what's using the ports
netstat -ano | findstr :6333
netstat -ano | findstr :11434
```

### bge-m3 model not pulled

**Symptom**: Ollama returns errors about missing model.

```powershell
# Check available models
docker exec mcp-ollama ollama list

# Pull manually
docker exec -it mcp-ollama ollama pull bge-m3
```

### Serena not on PATH

**Symptom**: `serena` command not found after `uv tool install serena-agent`.

```powershell
# uv tools are installed to ~/.local/bin or ~/.cargo/bin
# Add to PATH:
$env:Path += ";$env:USERPROFILE\.local\bin"
$env:Path += ";$env:USERPROFILE\.cargo\bin"

# Or use full path in mcp.json
uv tool dir  # Shows where tools are installed
```

### Serena times out on first launch

**Symptom**: CodeWhale shows "MCP server serena connection timeout".

Serena needs to download language servers on first use. Give it more time:

In `~/.codewhale/mcp.json`, increase `connect_timeout`:
```json
"serena": {
  "connect_timeout": 120,   // Was 60
  "execute_timeout": 180,   // Was 120
  ...
}
```

### Mem0 can't connect to Qdrant

**Symptom**: Mem0 tools fail with connection errors.

```powershell
# Verify Qdrant is running
curl http://localhost:6333/health

# Check Qdrant logs
docker compose logs qdrant

# Verify Mem0 config
Get-Content config\mem0-config.yaml
```

### Mem0 embedding errors

**Symptom**: Mem0 returns "embedding model unavailable".

```powershell
# Verify bge-m3 is loaded
curl http://localhost:11434/api/tags | ConvertFrom-Json | Select-Object -ExpandProperty models

# Pull if missing
docker exec -it mcp-ollama ollama pull bge-m3
```

### CodeWhale doesn't show MCP tools

**Symptom**: After starting CodeWhale, MCP tools don't appear.

```powershell
# Check MCP config location
codewhale-tui doctor

# Validate MCP config
codewhale-tui mcp validate

# List configured servers
codewhale-tui mcp list

# Force reload (inside TUI)
/mcp reload
```

If the config file doesn't exist:
```powershell
# Run setup again
.\scripts\setup.ps1

# Or manually copy
copy config\mcp.json $env:USERPROFILE\.codewhale\mcp.json
```

### Ollama uses CPU instead of GPU

**Symptom**: Slow embeddings, high CPU usage during Mem0 operations.

On Windows with NVIDIA GPU:
```powershell
# Check if NVIDIA container toolkit is available
docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi

# If GPU not detected, install NVIDIA Container Toolkit:
# https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html

# Fallback: Remove GPU requirement from docker-compose.yml
# Delete the deploy.resources section under ollama service
```

### Superpowers MCP server not available

**Symptom**: `uvx` can't find superpowers-mcp.

```powershell
# Install explicitly
uv tool install --from git+https://github.com/erophames/superpowers-mcp superpowers-mcp

# Or run from source
git clone https://github.com/erophames/superpowers-mcp $env:TEMP\superpowers-mcp
cd $env:TEMP\superpowers-mcp
uv pip install -e .
```

### Too many MCP tools cluttering context

**Symptom**: Agent's context window fills with MCP tool descriptions.

In `~/.codewhale/mcp.json`, you can limit which tools are exposed:
```json
"serena": {
  "enabled_tools": ["find_symbol", "find_references", "get_file_structure"],
  ...
}
```

This only exposes the tools you actually use. List all available tools with:
```powershell
codewhale-tui mcp tools serena
```

## Diagnostic Commands

Run these when something seems wrong:

```powershell
# Full system check
.\scripts\test.ps1

# Docker health
docker compose ps
docker compose logs --tail=50

# CodeWhale MCP status
codewhale-tui doctor
codewhale-tui mcp validate
codewhale-tui mcp list

# Ollama model check
curl http://localhost:11434/api/tags

# Qdrant collections
curl http://localhost:6333/collections | ConvertFrom-Json

# Serena check
serena --version
serena project health-check --project C:\Users\mauls\Documents\Code
```

## Complete Reset

If everything is broken and you want to start fresh:

```powershell
# Stop and remove containers
cd C:\Users\mauls\Documents\Code\agent-skills\mcp-servers
docker compose down -v

# Remove data (warning: deletes all memories and indices)
Remove-Item -Recurse -Force .\data

# Remove installed tools
uv tool uninstall serena-agent
uv tool uninstall superpowers-mcp

# Remove CodeWhale MCP config
Remove-Item $env:USERPROFILE\.codewhale\mcp.json

# Re-run setup
.\scripts\setup.ps1
```
