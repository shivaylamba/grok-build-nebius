# grok build × Nebius Token Factory

Run [grok build](https://github.com/xai-org/grok-build) (xAI's terminal coding
agent) **without a Grok subscription**, using any OpenAI-compatible provider —
here: [Nebius Token Factory](https://docs.tokenfactory.nebius.com/quickstart)
serving **Kimi K2.7 Code**, with web search via
[Tavily](https://tavily.com)'s MCP server.

No source changes, no forks, no proxies — grok build has first-class BYOK
support via `~/.grok/config.toml`; this repo is the working config plus the
non-obvious details that make it actually work end-to-end.

Verified working with grok build **0.1.210** on macOS (2026-07-16): headless
runs, TUI without any login screen, file read/edit tool calling, and live
Tavily web search.

## What you get

| Piece | Provider | How |
|---|---|---|
| Coding agent model | `moonshotai/Kimi-K2.7-Code` @ Nebius | `[model."kimi-k2.7-code"]`, default |
| Image description | `Qwen/Qwen2.5-VL-72B-Instruct` @ Nebius | Kimi is text-only |
| Web search | Tavily MCP server | built-in xAI web search disabled |
| xAI login | **skipped entirely** | model has its own `env_key` |
| Telemetry / feedback / managed config / auto-update / image & video gen | **all disabled** | `[features]`, `[cli]`, `GROK_IMAGE_GEN=0` |

## Setup

1. Install grok build if you haven't:
   ```sh
   curl -fsSL https://x.ai/cli/install.sh | bash
   ```
2. Get API keys: [tokenfactory.nebius.com](https://tokenfactory.nebius.com)
   and [app.tavily.com](https://app.tavily.com).
3. Add the exports from [`env.example`](env.example) to your `~/.zshrc` /
   `~/.bashrc` and reload your shell.
4. Run:
   ```sh
   ./setup.sh
   ```
   (Backs up any existing `~/.grok/config.toml`, installs this one, and
   smoke-tests the endpoint.)
5. Launch:
   ```sh
   grok -p "What is 2+2?" -m kimi-k2.7-code   # headless
   grok                                        # TUI — goes straight to the prompt
   ```

Tavily's MCP server runs via `npx`, so Node.js is required. (No Node? Use
Tavily's remote server instead: replace the `[mcp_servers.tavily]` block with
`url = "https://mcp.tavily.com/mcp/"`, `type = "http"`,
`bearer_token_env_var = "TAVILY_API_KEY"`.)

## How the login skip works

grok build's auth-method list puts API-key auth first whenever any configured
model carries its own `api_key`/`env_key`; the TUI only shows the login screen
when the *first* method needs interactive login. Since our default model reads
`NEBIUS_API_KEY`, no xAI account is ever consulted. Don't set
`GROK_DISABLE_API_KEY_AUTH` or `[auth] preferred_method = "oidc"` — those
force the interactive login back on.

## Gotchas we hit (so you don't)

1. **Quote dotted TOML table names.** `[model.kimi-k2.7-code]` silently parses
   as nested tables (`model."kimi-k2"."7-code"`) and you end up with a mangled
   model called `kimi-k2`. It must be `[model."kimi-k2.7-code"]`.
2. **Pin the auxiliary models — with full upstream IDs.** grok uses hidden
   helper models (session summary, image description) that default to
   `grok-build`, which 404s against a non-xAI endpoint. Pin them under
   `[models]`, and use the *upstream* ID (`moonshotai/Kimi-K2.7-Code`), not
   your alias: the aux sampler sends the pinned string verbatim on the wire,
   while catalog lookup still matches it against your `[model.*]` entry's
   `model` field (so base URL and key resolve correctly).
3. **Built-in web search can't be repointed.** It only works through a hosted
   WebSearch tool on xAI's `/responses` endpoint — no generic provider will
   serve it. Disable it (`disable_web_search = true`, valid as a top-level
   config key) and bring your own search via MCP.
4. **Headless writes need approval flags.** `grok -p "...edit something..."`
   silently does nothing without `--always-approve` (or a suitable
   `--permission-mode`). The interactive TUI prompts normally.
5. **Stale MCP servers from other tools.** grok also reads MCP servers from
   `~/.claude.json`, `~/.cursor/mcp.json`, and `.mcp.json`. A broken entry
   spams errors on every run; disable it from grok's side with
   `[mcp_servers.<name>] enabled = false` (plus its `command`) in
   `config.toml`.
6. **Image generation has no config key.** It's gated only by the
   `GROK_IMAGE_GEN` env var — hence `GROK_IMAGE_GEN=0` in `env.example`.

## Swapping models

Any model in Nebius's catalog works — list them with:

```sh
curl -s https://api.tokenfactory.nebius.com/v1/models \
  -H "Authorization: Bearer $NEBIUS_API_KEY"
```

Copy the `[model.*]` block in `config.toml`, change `model` (exact catalog ID)
and `context_window`, and switch with `/model` in the TUI or `-m` headlessly.
The same pattern works for any OpenAI-compatible provider — just change
`base_url` and `env_key`.

## Files

- [`config.toml`](config.toml) — drop-in `~/.grok/config.toml` (no secrets;
  keys come from env vars)
- [`env.example`](env.example) — shell exports to add to your rc file
- [`setup.sh`](setup.sh) — install + verify in one step
