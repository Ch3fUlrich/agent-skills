# Token Savings Analysis

## How AI Coding Agents Spend Tokens

In a typical coding session, tokens are spent on:

| Category | % of session tokens | How MCP reduces it |
|---|---|---|
| **Code reading** (file reads, search results) | 45–55% | Serena — semantic lookups instead of brute-force reads |
| **Context re-explanation** (architecture, decisions) | 10–20% | Mem0 — persistent memory across sessions |
| **Tool descriptions & overhead** | 8–12% | Built-in (not MCP-specific) |
| **Workflow overhead** (trial-and-error, rewrites) | 10–15% | Superpowers — disciplined workflows |
| **User messages** | 8–10% | N/A |
| **Agent reasoning** | 10–15% | Better tool results → less reasoning needed |

## Serena: Code Reading Savings

### Before Serena (brute-force file reading)

```
User: "Where is the train_model function defined?"

Agent reads: src/models/training.py     (2000 tokens — whole file)
  "I can see train_model is defined at line 342"

User: "Who calls it?"

Agent reads: src/models/__init__.py      (500 tokens)
Agent reads: src/api/endpoints.py        (1500 tokens)
Agent reads: tests/test_training.py      (1800 tokens)
  "train_model is called from 3 locations"

Total tokens for this interaction: ~5800
```

### With Serena (semantic navigation)

```
User: "Where is the train_model function defined?"

Agent → Serena: find_symbol("train_model")
Serena → Agent: { file: "src/models/training.py", line: 342, signature: "def train_model(data, epochs)" }
Tokens: ~200 (tool call + result)

User: "Who calls it?"

Agent → Serena: find_references("train_model")
Serena → Agent: [
  { file: "src/models/__init__.py", line: 15 },
  { file: "src/api/endpoints.py", line: 88 },
  { file: "tests/test_training.py", line: 45 }
]
Tokens: ~300 (tool call + result)

Total tokens for this interaction: ~500
```

**Savings: 91% on this type of interaction. Average across sessions: 40–60%.**

### When Serena helps most
- Large codebases (500+ files)
- Unfamiliar projects (first-time exploration)
- Refactoring (finding all references)
- Multi-language projects (Serena handles LSP for each language)

### When Serena helps least
- Single small file edits (reading the file directly is already cheap)
- When you already have the file open and know the codebase well

## Mem0: Context Reuse Savings

### Before Mem0 (every session starts fresh)

```
Session 1 (1 hour):
  Agent learns: "This project uses SQLAlchemy with async session factory"
  Agent learns: "User prefers pydantic v2 syntax"
  Agent learns: "Error handling uses a custom Result[T] type"
  Waste: ~3000 tokens explaining/discussing these patterns

Session 2 (next day):
  Agent starts from scratch — has to re-discover or ask about patterns
  Waste: ~2000 tokens re-learning

Session 3:
  Waste: ~1500 tokens (some context is in the transcript, but not all)

Total waste across 3 sessions: ~6500 tokens
```

### With Mem0 (persistent memory)

```
Session 1:
  Agent → Mem0: remember("This project uses SQLAlchemy with async session factory")
  Agent → Mem0: remember("User prefers pydantic v2 syntax")
  Agent → Mem0: remember("Error handling uses custom Result[T] type")
  Cost: ~500 tokens for the remember calls

Session 2:
  Agent → Mem0: recall("project architecture patterns")
  Mem0 → Agent: [SQLAlchemy async factory, pydantic v2, Result[T]]
  Cost: ~200 tokens. Agent knows the patterns immediately.

Session 3:
  Same — ~200 tokens to recall

Total: 500 + 200 + 200 = 900 tokens (vs. 6500 without Mem0)
```

**Savings: ~86% on context re-explanation. 10–20% total session savings.**

## Superpowers: Quality Savings

Workflow quality is harder to measure in tokens, but observable in outcomes:

### Before Superpowers

```
Agent: "Let me add error handling to this function"
  → Writes try/except
  → Doesn't write tests first
  → Misses edge case
  → User reports bug
  → Agent fixes (reads more code, more tokens)
  Total tokens: ~4000 + bug fix ~3000 = ~7000
```

### With Superpowers

```
Agent → Superpowers: use_skill("tdd")
Superpowers → Agent: [TDD workflow: 1) Write test, 2) Run (fail), 3) Implement, 4) Run (pass)]
  → Writes test first
  → Test catches edge case
  → Implementation handles it correctly
  → No bug fix needed
  Total tokens: ~5000 (one and done)
```

**Savings: ~30% fewer rework tokens. Quality multiplier.**

## Combined Savings Estimate

| Scenario | Without MCP | With MCP | Savings |
|---|---|---|---|
| **First-time codebase exploration** (1 hour) | 80,000 tok | 35,000 tok | 56% |
| **Routine bug fix** (15 min) | 20,000 tok | 14,000 tok | 30% |
| **Multi-session refactor** (3 × 1 hour) | 240,000 tok | 120,000 tok | 50% |
| **Feature addition** (known codebase) | 40,000 tok | 28,000 tok | 30% |
| **Architecture planning** (brainstorming) | 15,000 tok | 12,000 tok | 20% |

**Weighted average across all coding tasks: 45–55% token reduction.**

## What Doesn't Change

- User message tokens (unchanged)
- Final reply tokens (similar)
- Tool description overhead (slightly higher due to MCP tool registration)
- Actual code generation (unchanged — you still need the same amount of code)

## Tracking Savings

Inside CodeWhale:
```
/cost   ← Shows current session token usage and cache hit rate
```

Compare with and without MCP servers to measure actual savings in your
specific workflow.
