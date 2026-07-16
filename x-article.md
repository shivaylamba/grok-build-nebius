# Grok Build is open source — and the agent harness is the part worth reading

On July 15, xAI open-sourced Grok Build, their terminal coding agent. Most people saw "Grok CLI is OSS" and moved on. The interesting part isn't that you can read the code — it's what the architecture makes possible. I spent a day inside the source and ended up running the whole agent on a different provider, with a different model, no subscription, no fork. Here's the short tour, and the swap.

## One binary, two programs

The repo is a pure Rust workspace (~40 crates), but architecturally it's two programs talking over a protocol:

**The TUI** (`xai-grok-pager`) — scrollback, prompt, modals, rendering. It contains no agent logic at all.

**The agent runtime** (`xai-grok-shell`) — the actual brain: session state, the sampling loop, tool dispatch, permissions, checkpoints.

They communicate over ACP, the Agent Client Protocol — JSON-RPC with methods like `initialize` and `session/new`. Run it with `RUST_LOG=debug` and you can watch the TUI negotiate capabilities with the runtime like two separate services.

This split is why the same runtime drives four frontends: the full-screen TUI, headless mode for CI (`grok -p "..."`), editor embedding (any ACP-capable editor), and stdio for scripting. The UI is a client. The agent is a server. Everything below is swappable.

## The harness, crate by crate

The supporting crates read like a checklist of what a production agent harness actually needs:

- `xai-grok-tools` — tool implementations: terminal, file edit, search, web
- `xai-grok-workspace` + `xai-fast-worktree` — host filesystem, VCS awareness, checkpoints, fast git worktrees for parallel work
- `xai-grok-sandbox` — OS-level sandboxing profiles for tool execution
- `xai-grok-mcp` — MCP client support; reads servers from its own config *and* from `~/.claude.json`, `~/.cursor/mcp.json`, `.mcp.json`
- `xai-grok-memory`, `xai-codebase-graph` — persistent memory and code understanding
- `xai-grok-hooks`, plugins, skills, subagent roles — the extensibility surface

The user guide ships in-repo: 24 chapters covering everything from plan mode to sandboxing to subagents. For a "synced periodically from the monorepo" release, it's remarkably complete.

## The part nobody talks about: the model layer is provider-agnostic

Here's the design decision that matters. The sampler (`xai-grok-sampler`) doesn't speak "xAI" — it speaks three wire protocols:

1. OpenAI Chat Completions (the default)
2. OpenAI Responses
3. Anthropic Messages

And the model catalog is a three-layer merge: hardcoded defaults < models prefetched from `/v1/models` < **your own entries in `~/.grok/config.toml`**. Credentials resolve per model: a model's own `api_key`/`env_key` beats the session token, which beats the global env key. If your default model carries its own key, the xAI login screen never even renders — the auth method list is built from what can actually authenticate.

That's not an accident. That's a BYOK escape hatch designed into the core.

## So I swapped the provider

I pointed Grok Build at Nebius Token Factory running Kimi K2.7 Code. The entire "integration" is a TOML block:

```toml
[models]
default = "kimi-k2.7-code"

[model."kimi-k2.7-code"]
model = "moonshotai/Kimi-K2.7-Code"
base_url = "https://api.tokenfactory.nebius.com/v1"
env_key = "NEBIUS_API_KEY"
api_backend = "chat_completions"
context_window = 256000
```

That's it. No login, no subscription, no proxy shim. Tool calling, file edits, MCP servers — the whole agent loop runs against an open-weights model on someone else's infrastructure. Web search needed one extra move (the built-in tool is hardwired to a hosted xAI capability, so I disabled it and dropped in Tavily's MCP server), and pasted images route to Qwen2.5-VL on the same endpoint.

Three gotchas if you try this, all learned the hard way:

1. **Quote dotted TOML keys.** `[model.kimi-k2.7-code]` silently parses as nested tables and your model shows up mangled. It must be `[model."kimi-k2.7-code"]`.
2. **Pin the hidden helper models.** Session summaries and image description default to the `grok-build` model and 404 against any non-xAI endpoint. Pin them under `[models]` using full upstream IDs.
3. **Headless writes need `--always-approve`.** The permission system fails closed — which is the right default, but confusing the first time an edit silently doesn't happen.

## Why this matters

Every serious coding agent — Claude Code, Codex, Grok Build — is converging on the same shape: a model-agnostic harness (tools, permissions, checkpoints, MCP, sandboxing) with a model plugged into one end. xAI open-sourcing theirs means you can now read a production-grade implementation of that shape, end to end, in Rust.

And because the harness is honestly decoupled from the model, "which agent CLI" and "which model" are now separate decisions. I'm running xAI's harness with Moonshot's model on Nebius's infrastructure, searching with Tavily. Four vendors, one config file, zero forks.

Full working config, setup script, and all the gotchas: **github.com/shivaylamba/grok-build-nebius**

Grok Build source: **github.com/xai-org/grok-build**
