## Serena Project Management

### Where Indices Are Stored

Serena stores data in two places:

| Location | Content |
|----------|---------|
| **Per-repo** `.serena/project.yml` | Project language, workspace folders, indexing settings |
| **Per-repo** `.serena/` cache | LSP language server data, symbol cache |
| **Global** `~/.serena/serena_config.yml` | Excluded tools, registered projects list, global timeouts |

Currently **9 repos** are indexed with Serena LSP support.

### Adding a New Repository

When you create a new repo under `C:\Users\mauls\Documents\Code`, add it to Serena:

```powershell
# Method 1: Direct command
cd C:\Users\mauls\Documents\Code
("N`n" * 10) | serena project create "C:\Users\mauls\Documents\Code\NewRepo" --index

# Method 2: Via the initialization script (indexes ALL unindexed repos)
cd C:\Users\mauls\Documents\Code\agent-skills\mcp-servers
.\windows\init-serena-projects.ps1
```

The `("N`n" * 10)` pipes "No" answers for any language detection prompts.
The `--index` flag triggers immediate LSP indexing. Indexing takes 10-60 seconds
depending on repo size.

### How the Agent Uses Serena

Once a project is indexed, any CodeWhale session can use it:

```
# Step 1: Activate the project (once per session)
mcp_serena_activate_project(project="DeepLabCut")

# Step 2: Navigate code symbolically
mcp_serena_find_symbol(name_path_pattern="train_model")
mcp_serena_find_references(name_path_pattern="train_model", relative_path="src/")
mcp_serena_get_symbols_overview(relative_path="src/models.py")

# Step 3: Store project-level notes (persistent across sessions)
mcp_serena_write_memory(memory_name="training-pipeline", content="Uses PyTorch Lightning with custom callbacks")
mcp_serena_read_memory(memory_name="training-pipeline")
```

The agent skill at `skills/mcp-servers-setup/SKILL.md` contains the full
workflow instructions that agents follow automatically.
