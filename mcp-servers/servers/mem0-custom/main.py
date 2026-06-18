"""Mem0 REST API server — FastAPI wrapper around mem0ai library.

LLM:      DeepSeek via OpenAI-compatible API
Embedder: Ollama (bge-m3) running on host
Store:    PostgreSQL + pgvector

Exposes the standard mem0 CRUD API that the MCP bridge and dashboard consume:
  GET  /health
  POST /memories
  POST /memories/search
  GET  /memories?user_id=...
  DELETE /memories/{memory_id}?user_id=...

Also exposes auth endpoints for the dashboard setup wizard:
  GET  /auth/config
  POST /auth/register
  POST /auth/login
  GET  /auth/me
  GET  /api-keys
  POST /api-keys
  DELETE /api-keys/{key_id}

Auth is stdlib-only (no pip deps): PBKDF2 passwords + HMAC-SHA256 JWT.
User store: JSON file at /app/history/users.json (volume-mounted).
"""

import base64
import hashlib
import hmac
import json
import os
import secrets
import time
import uuid
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, Header, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from mem0 import Memory
from pydantic import BaseModel


# ─── Config ──────────────────────────────────────────────────────────────────

POSTGRES_HOST = os.environ.get("POSTGRES_HOST", "postgres")
POSTGRES_PORT = int(os.environ.get("POSTGRES_PORT", "5432"))
POSTGRES_USER = os.environ.get("POSTGRES_USER", "postgres")
POSTGRES_PASSWORD = os.environ["POSTGRES_PASSWORD"]
POSTGRES_DB = os.environ.get("POSTGRES_DB", "postgres")

LLM_API_KEY = os.environ.get("OPENAI_API_KEY", os.environ.get("DEEPSEEK_API_KEY", ""))
LLM_BASE_URL = os.environ.get("OPENAI_BASE_URL", os.environ.get("DEEPSEEK_API_BASE", "https://api.deepseek.com/v1"))
LLM_MODEL = os.environ.get("LLM_MODEL", os.environ.get("DEEPSEEK_MODEL", "deepseek-chat"))

EMBED_MODEL = os.environ.get("EMBEDDER_MODEL", os.environ.get("OLLAMA_EMBED_MODEL", "bge-m3"))
OLLAMA_URL = os.environ.get("OLLAMA_BASE_URL", os.environ.get("OLLAMA_EMBED_URL", "http://host.docker.internal:11434"))

EMBED_DIMS = int(os.environ.get("OLLAMA_EMBED_DIMS", "1024"))

# ─── Auth config ─────────────────────────────────────────────────────────────

JWT_SECRET = os.environ.get("JWT_SECRET", "dev-secret-change-me")
ADMIN_API_KEY = os.environ.get("ADMIN_API_KEY", "")
AUTH_DISABLED = os.environ.get("AUTH_DISABLED", "").lower() in {"1", "true", "yes", "on"}

USERS_FILE = Path(os.environ.get("USERS_FILE", "/app/history/users.json"))
API_KEYS_FILE = Path(os.environ.get("API_KEYS_FILE", "/app/history/api_keys.json"))

# Runtime configuration store (persisted across restarts via volume mount)
CONFIG_FILE = Path(os.environ.get("CONFIG_FILE", "/app/history/configure.json"))


# ─── Mem0 config ─────────────────────────────────────────────────────────────

mem0_config = {
    "vector_store": {
        "provider": "pgvector",
        "config": {
            "host": POSTGRES_HOST,
            "port": POSTGRES_PORT,
            "user": POSTGRES_USER,
            "password": POSTGRES_PASSWORD,
            "dbname": POSTGRES_DB,
            "embedding_model_dims": EMBED_DIMS,
        },
    },
    "llm": {
        "provider": "openai",
        "config": {
            "api_key": LLM_API_KEY,
            "model": LLM_MODEL,
            "openai_base_url": LLM_BASE_URL,
        },
    },
    "embedder": {
        "provider": "ollama",
        "config": {
            "model": EMBED_MODEL,
            "ollama_base_url": OLLAMA_URL,
            "embedding_dims": EMBED_DIMS,
        },
    },
}

memory_client = Memory.from_config(mem0_config)


# ─── Auth helpers (stdlib only — no pip deps) ────────────────────────────────

def _b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _b64url_decode(data: str) -> bytes:
    padding = 4 - len(data) % 4
    if padding != 4:
        data += "=" * padding
    return base64.urlsafe_b64decode(data)


def hash_password(password: str) -> str:
    """PBKDF2-SHA256 password hashing."""
    salt = secrets.token_hex(16)
    key = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), 100_000)
    return f"pbkdf2:sha256:100000${salt}${key.hex()}"


def verify_password(password: str, hashed: str) -> bool:
    """Verify a PBKDF2-SHA256 password hash. Format: pbkdf2:sha256:100000$salt$hex"""
    try:
        algo, hash_func, params = hashed.split(":", 2)
        if algo != "pbkdf2":
            return False
        iters_str, salt, stored_key = params.split("$")
        key = hashlib.pbkdf2_hmac(hash_func, password.encode(), salt.encode(), int(iters_str))
        return hmac.compare_digest(key.hex(), stored_key)
    except (ValueError, IndexError):
        return False


def create_jwt(user_id: str, role: str = "admin") -> str:
    """Create a HS256 JWT access token."""
    secret = JWT_SECRET.encode()
    header = _b64url_encode(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    payload = _b64url_encode(json.dumps({
        "sub": user_id,
        "role": role,
        "exp": int(time.time()) + 86400,  # 24 hours
        "iat": int(time.time()),
        "type": "access",
    }).encode())
    sig = _b64url_encode(hmac.new(secret, f"{header}.{payload}".encode(), hashlib.sha256).digest())
    return f"{header}.{payload}.{sig}"


def verify_jwt(token: str) -> dict:
    """Verify a HS256 JWT and return claims. Raises HTTPException on failure."""
    secret = JWT_SECRET.encode()
    parts = token.split(".")
    if len(parts) != 3:
        raise HTTPException(status_code=401, detail="Invalid token format")
    header_b64, payload_b64, sig_b64 = parts
    expected_sig = _b64url_encode(hmac.new(
        secret, f"{header_b64}.{payload_b64}".encode(), hashlib.sha256
    ).digest())
    if not hmac.compare_digest(sig_b64, expected_sig):
        raise HTTPException(status_code=401, detail="Invalid token signature")
    claims = json.loads(_b64url_decode(payload_b64))
    if claims.get("exp", 0) < time.time():
        raise HTTPException(status_code=401, detail="Token expired")
    return claims


def _load_json(path: Path) -> dict:
    """Load a JSON file, returning {} if missing or corrupt."""
    try:
        if path.exists():
            return json.loads(path.read_text())
    except (json.JSONDecodeError, OSError):
        pass
    return {}


def _save_json(path: Path, data: dict) -> None:
    """Atomically save a JSON file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2, default=str))
    tmp.replace(path)


def load_users() -> dict:
    return _load_json(USERS_FILE)


def save_users(users: dict) -> None:
    _save_json(USERS_FILE, users)


def load_api_keys() -> dict:
    return _load_json(API_KEYS_FILE)


def save_api_keys(keys: dict) -> None:
    _save_json(API_KEYS_FILE, keys)


def gen_api_key() -> tuple[str, str, str]:
    """Returns (full_key, prefix, hash)."""
    raw = secrets.token_urlsafe(32)
    full_key = f"m0sk_{raw}"
    prefix = full_key[:12]
    key_hash = hash_password(full_key)
    return full_key, prefix, key_hash


# ─── Auth dependency ─────────────────────────────────────────────────────────

def get_current_user(
    request: Request,
    authorization: Optional[str] = Header(None),
    x_api_key: Optional[str] = Header(None, alias="X-API-Key"),
) -> Optional[dict]:
    """Resolve current user from Bearer token, X-API-Key, or admin key.
    
    Returns user dict or None when auth is disabled and no user exists.
    """
    # Bearer token
    if authorization and authorization.startswith("Bearer "):
        token = authorization[7:]
        claims = verify_jwt(token)
        users = load_users()
        user_id = claims.get("sub")
        if user_id and user_id in users:
            return users[user_id]
        raise HTTPException(status_code=401, detail="User not found")

    # X-API-Key
    if x_api_key:
        # Admin API key
        if ADMIN_API_KEY and hmac.compare_digest(x_api_key, ADMIN_API_KEY):
            users = load_users()
            if users:
                return next(iter(users.values()))
            return None
        # User API key
        keys = load_api_keys()
        prefix = x_api_key[:12] if len(x_api_key) >= 12 else x_api_key
        for kid, kdata in keys.items():
            if kdata.get("key_prefix") == prefix and not kdata.get("revoked"):
                if verify_password(x_api_key, kdata["key_hash"]):
                    users = load_users()
                    user_id = kdata.get("user_id")
                    if user_id and user_id in users:
                        return users[user_id]
        raise HTTPException(status_code=401, detail="Invalid API key")

    # Auth disabled — return first user or None
    if AUTH_DISABLED:
        users = load_users()
        if users:
            return next(iter(users.values()))
        return None

    # Auth enabled and no credentials provided
    return None


# ─── App ─────────────────────────────────────────────────────────────────────

app = FastAPI(
    title="Mem0 API",
    description="Self-hosted Mem0 REST API — DeepSeek LLM + Ollama embedder + pgvector",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ─── Models ──────────────────────────────────────────────────────────────────


class Message(BaseModel):
    role: str
    content: str


class AddMemoryRequest(BaseModel):
    messages: list[Message]
    user_id: str
    metadata: dict | None = None


class SearchRequest(BaseModel):
    query: str
    user_id: str
    limit: int = 10


class RegisterRequest(BaseModel):
    email: str
    password: str
    full_name: str = ""


class LoginRequest(BaseModel):
    email: str
    password: str


class ApiKeyCreateRequest(BaseModel):
    name: str = "default"


# ─── Auth Endpoints ──────────────────────────────────────────────────────────


@app.get("/auth/config")
def auth_config():
    """Dashboard calls this to check if auth is required."""
    return {
        "auth_disabled": AUTH_DISABLED,
        "has_users": bool(load_users()),
    }


@app.get("/auth/setup-status")
def auth_setup_status():
    """Dashboard checks this to determine if initial setup is complete."""
    users = load_users()
    return {
        "setup_complete": bool(users),
        "has_users": bool(users),
    }


@app.get("/configure")
def get_configure():
    """Return current LLM/embedder configuration for the dashboard."""
    saved = _load_json(CONFIG_FILE)
    return {
        "llm": {
            "provider": saved.get("llm", {}).get("provider") or "openai",
            "config": {
                "model": saved.get("llm", {}).get("config", {}).get("model") or LLM_MODEL,
                "openai_base_url": LLM_BASE_URL,
            },
        },
        "embedder": {
            "provider": saved.get("embedder", {}).get("provider") or "ollama",
            "config": {
                "model": saved.get("embedder", {}).get("config", {}).get("model") or EMBED_MODEL,
                "ollama_base_url": OLLAMA_URL,
            },
        },
    }


@app.get("/configure/providers")
def get_configure_providers():
    """Return available provider options for the dashboard config UI."""
    return {
        "llm": ["openai"],
        "embedder": ["ollama"],
    }


@app.post("/configure")
async def post_configure(request: Request):
    """Accept configuration from the dashboard setup wizard or config page."""
    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON body")

    # Store the config for GET /configure to read back, keeping only
    # the llm + embedder blocks the dashboard cares about.
    stored = {
        "llm": body.get("llm", {}),
        "embedder": body.get("embedder", {}),
    }
    if body.get("custom_instructions"):
        stored["custom_instructions"] = body["custom_instructions"]

    _save_json(CONFIG_FILE, stored)
    return {
        "message": "Configuration updated",
        "llm": stored.get("llm"),
        "embedder": stored.get("embedder"),
    }


@app.post("/auth/register")
def register(req: RegisterRequest):
    """Register a new user. First user gets admin role."""
    users = load_users()

    # Check for duplicate email
    for uid, udata in users.items():
        if udata.get("email") == req.email:
            raise HTTPException(status_code=409, detail="Email already registered")

    # Validate password length
    if len(req.password) < 8:
        raise HTTPException(status_code=422, detail="Password must be at least 8 characters")

    user_id = str(uuid.uuid4())
    role = "admin" if not users else "user"  # First user is admin
    now_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    user = {
        "id": user_id,
        "email": req.email,
        "full_name": req.full_name,
        "password_hash": hash_password(req.password),
        "role": role,
        "created_at": now_iso,
        "updated_at": now_iso,
    }
    users[user_id] = user
    save_users(users)

    token = create_jwt(user_id, role)

    return {
        "token": token,
        "user": {
            "id": user_id,
            "email": req.email,
            "full_name": req.full_name,
            "role": role,
            "created_at": now_iso,
        },
    }


@app.post("/auth/login")
def login(req: LoginRequest):
    """Login with email + password, return JWT."""
    users = load_users()

    # Find user by email
    found_user = None
    for uid, udata in users.items():
        if udata.get("email") == req.email:
            found_user = udata
            break

    if not found_user:
        # Burn a hash cycle to avoid timing leak
        hash_password("dummy")
        raise HTTPException(status_code=401, detail="Invalid email or password")

    if not verify_password(req.password, found_user["password_hash"]):
        raise HTTPException(status_code=401, detail="Invalid email or password")

    token = create_jwt(found_user["id"], found_user.get("role", "user"))

    return {
        "token": token,
        "user": {
            "id": found_user["id"],
            "email": found_user["email"],
            "full_name": found_user.get("full_name", ""),
            "role": found_user.get("role", "user"),
            "created_at": found_user.get("created_at", ""),
        },
    }


@app.get("/auth/me")
def auth_me(
    authorization: Optional[str] = Header(None),
    x_api_key: Optional[str] = Header(None, alias="X-API-Key"),
):
    """Return current user from JWT or API key."""
    user = _resolve_user(authorization, x_api_key)
    if not user:
        raise HTTPException(status_code=401, detail="Authentication required")
    return {
        "id": user["id"],
        "email": user["email"],
        "full_name": user.get("full_name", ""),
        "role": user.get("role", "user"),
        "created_at": user.get("created_at", ""),
    }


@app.get("/api-keys")
def list_api_keys(
    authorization: Optional[str] = Header(None),
    x_api_key: Optional[str] = Header(None, alias="X-API-Key"),
):
    """List API keys for the authenticated user."""
    user = _resolve_user(authorization, x_api_key)
    if not user:
        raise HTTPException(status_code=401, detail="Authentication required")

    keys = load_api_keys()
    user_keys = []
    for kid, kdata in keys.items():
        if kdata.get("user_id") == user["id"] and not kdata.get("revoked"):
            user_keys.append({
                "id": kid,
                "name": kdata.get("name", ""),
                "key_prefix": kdata.get("key_prefix", ""),
                "created_at": kdata.get("created_at", ""),
                "last_used_at": kdata.get("last_used_at"),
            })
    return user_keys


@app.post("/api-keys")
def create_api_key(
    req: ApiKeyCreateRequest,
    authorization: Optional[str] = Header(None),
    x_api_key: Optional[str] = Header(None, alias="X-API-Key"),
):
    """Create a new API key for the authenticated user."""
    user = _resolve_user(authorization, x_api_key)
    if not user:
        raise HTTPException(status_code=401, detail="Authentication required")

    full_key, prefix, key_hash = gen_api_key()
    key_id = str(uuid.uuid4())
    now_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    keys = load_api_keys()
    keys[key_id] = {
        "id": key_id,
        "name": req.name,
        "user_id": user["id"],
        "key_prefix": prefix,
        "key_hash": key_hash,
        "created_at": now_iso,
        "last_used_at": None,
        "revoked": False,
    }
    save_api_keys(keys)

    return {
        "id": key_id,
        "name": req.name,
        "key": full_key,
        "key_prefix": prefix,
        "created_at": now_iso,
    }


@app.delete("/api-keys/{key_id}")
def delete_api_key(
    key_id: str,
    authorization: Optional[str] = Header(None),
    x_api_key: Optional[str] = Header(None, alias="X-API-Key"),
):
    """Revoke an API key."""
    user = _resolve_user(authorization, x_api_key)
    if not user:
        raise HTTPException(status_code=401, detail="Authentication required")

    keys = load_api_keys()
    if key_id not in keys:
        raise HTTPException(status_code=404, detail="API key not found")
    if keys[key_id].get("user_id") != user["id"]:
        raise HTTPException(status_code=403, detail="Not your API key")

    keys[key_id]["revoked"] = True
    save_api_keys(keys)
    return {"message": "API key revoked"}


def _resolve_user(authorization: Optional[str], x_api_key: Optional[str]) -> Optional[dict]:
    """Resolve user from auth headers. Returns user dict or None."""
    # Bearer token
    if authorization and authorization.startswith("Bearer "):
        token = authorization[7:]
        claims = verify_jwt(token)
        users = load_users()
        user_id = claims.get("sub")
        if user_id and user_id in users:
            return users[user_id]
        raise HTTPException(status_code=401, detail="User not found")

    # X-API-Key
    if x_api_key:
        if ADMIN_API_KEY and hmac.compare_digest(x_api_key, ADMIN_API_KEY):
            users = load_users()
            if users:
                return next(iter(users.values()))
            return None
        keys = load_api_keys()
        prefix = x_api_key[:12] if len(x_api_key) >= 12 else x_api_key
        for kid, kdata in keys.items():
            if kdata.get("key_prefix") == prefix and not kdata.get("revoked"):
                if verify_password(x_api_key, kdata["key_hash"]):
                    users = load_users()
                    user_id = kdata.get("user_id")
                    if user_id and user_id in users:
                        return users[user_id]
        return None

    # Auth disabled
    if AUTH_DISABLED:
        users = load_users()
        if users:
            return next(iter(users.values()))
        return None

    return None


# ─── Memory Endpoints ────────────────────────────────────────────────────────


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/memories")
def add_memory(req: AddMemoryRequest):
    try:
        messages = [{"role": m.role, "content": m.content} for m in req.messages]
        result = memory_client.add(messages, user_id=req.user_id, metadata=req.metadata)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/memories/search")
def search_memories(req: SearchRequest):
    try:
        results = memory_client.search(
            req.query, filters={"user_id": req.user_id}, top_k=req.limit
        )
        return {"results": results}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/memories")
def get_memories(user_id: str = Query(...)):
    try:
        memories = memory_client.get_all(filters={"user_id": user_id})
        return {"results": memories}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/memories/{memory_id}")
def delete_memory(memory_id: str, user_id: str = Query(...)):
    try:
        memory_client.delete(memory_id)
        return {"message": "deleted", "id": memory_id}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ─── Startup ─────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
