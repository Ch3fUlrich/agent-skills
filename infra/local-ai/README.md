# Local AI & Coding Stack

An optional, self-hosted LLM inference, UI, and SWE agent stack designed to complement your coding workflow. This environment provides local model execution via Ollama, API proxying and routing via LiteLLM, a chat interface via Open WebUI, and a browser-based agent coding environment via OpenHands.

## Components

- **OpenHands**: Browser-based Software Engineering (SWE) AI agent platform using a sandboxed runtime container for executing code safely.
- **Ollama**: Local LLM engine serving models.
- **Ollama Agent**: A sandboxed container configured to access the main Ollama API via `host.docker.internal`. Useful for running tasks locally.
- **LiteLLM**: Standardizes API calls across multiple providers (e.g., Perplexity, OpenAI, Anthropic). It's pre-configured with Perplexity models and serves as a unified proxy.
- **Open WebUI**: A feature-rich frontend for interacting with your models, connected to both Ollama and LiteLLM.

## Setup Instructions

1. **Copy the environment template:**
   ```bash
   cp .env.example .env
   ```

2. **Configure your `.env` file:**
   - **Workspace**: Create the directory specified in `WORKSPACE_BASE` (default `C:/Apps/coding_workspace`).
   - **Secrets**: Set a strong `WEBUI_SECRET_KEY` (e.g., using `openssl rand -hex 32`).
   - **API Keys**: Provide keys like `PERPLEXITY_API_KEY` for LiteLLM, and any required keys for OpenHands (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, etc.). *Alternatively, you can point OpenHands to the local LiteLLM proxy to centralize key management.*
   - **Paths**: Adjust `APPS_ROOT` and `WORKSPACE_BASE` to match your local setup. 

3. **Start the stack:**
   ```bash
   docker compose up -d
   ```
   *(Note: The first run may take a few minutes as OpenHands downloads its runtime images).*

4. **Access the services:**
   - **OpenHands**: [http://localhost:3000](http://localhost:3000)
   - **Open WebUI**: [http://localhost:3131](http://localhost:3131)
   - **LiteLLM Proxy**: [http://localhost:4000](http://localhost:4000)
   - **Ollama API**: [http://localhost:11434](http://localhost:11434)

## Using the Ollama Agent

The `ollama-agent` container runs continuously (via `tail -f /dev/null`) and shares the models directory (`C:/Apps/ollama`) with the main `ollama` service. To run a model inside this isolated environment:

```bash
docker exec -it ollama-agent ollama run llama3.1:8b-instruct-q5_k_m
```
