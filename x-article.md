# Inside Grok Build: the agent harness xAI just open-sourced, and how to run it on your own provider

**Key takeaways**

- Grok Build is two programs in one binary: a TUI client and an agent runtime server, talking over the Agent Client Protocol (ACP). The UI knows nothing about models or tools.
- The harness is the real product: a five-step tool authorization pipeline, kernel-level sandboxing, git-aware checkpoints, subagents with their own context windows, and MCP support that even reads your existing Claude and Cursor configs.
- The model layer is provider-agnostic by design. Three wire protocols, a three-layer model catalog, and per-model credentials mean you can swap xAI out for any OpenAI-compatible endpoint in about 15 lines of TOML.
- I run it on Nebius Token Factory with Kimi K2.7 Code. No subscription, no login screen, no fork. Working config: github.com/shivaylamba/grok-build-nebius

You install a terminal coding agent. You type a prompt. It edits three files, runs your tests, and opens a browser tab asking you to log in to a subscription you do not want.

That last step is the one this article removes. On July 15, xAI open-sourced Grok Build, their Rust terminal coding agent. Most coverage stopped at "the Grok CLI is now OSS". The more useful story is underneath: the agent harness is cleanly separated from the model it drives, and once you can read the source, you can see exactly where to unplug one provider and plug in another.

This article walks through the architecture, then does the swap for real.

## One binary, two programs

The repository is a Rust workspace of roughly 40 crates, but architecturally it is two programs:

The **TUI** (`xai-grok-pager`) handles scrollback, the prompt, modals, and rendering. It contains no agent logic.

The **agent runtime** (`xai-grok-shell`) owns everything that matters: session state, the sampling loop, tool dispatch, permissions, and checkpoints.

They talk over ACP, the Agent Client Protocol. It is JSON-RPC with methods like `initialize` and `session/new`. You can watch the handshake yourself:

```bash
RUST_LOG=debug grok 2>debug.log
grep "initialize" debug.log
```

The response advertises auth methods, model state, MCP servers, and capabilities. The TUI is just the first client of that protocol. The same runtime also serves headless mode for CI (`grok -p "fix the failing test"`), editor embedding through ACP, and stdio for scripting.

The practical rule is: the UI is a client, the agent is a server, and everything below the protocol line is swappable.

## How a tool call actually runs

The loop itself is what you expect: sample the model, get tool calls back, execute them, append results, repeat until the model stops asking for tools. The interesting part is what stands between "the model wants to run a command" and "the command runs". Authorization is a five-step pipeline, checked in order:

1. **PreToolUse hooks.** A hook can veto the call before anything else sees it.
2. **Permission rules.** `deny` beats everything, `ask` forces a prompt, `allow` approves. Configurable per project or via `--allow`/`--deny` flags.
3. **Remembered grants.** Approvals you saved earlier, scoped to the project. Dangerous commands re-prompt no matter what you saved.
4. **Built-in auto-approvals.** Read-only tools (`read_file`, `grep`, `list_dir`) never prompt.
5. **Prompt policy.** Whatever the current permission mode says: prompt, auto-approve, or auto-deny.

This fails closed, which you will notice the first time a headless run silently skips a file edit. Headless writes need `--always-approve` or an explicit permission mode. That is the right default, and it is confusing exactly once.

Below all of that sits a second, independent layer: OS-level sandboxing (`xai-grok-sandbox`), enforced by the kernel rather than the agent. Landlock on Linux, Seatbelt on macOS:

| Profile | Read | Write | Child network |
|---|---|---|---|
| `workspace` | everywhere | CWD, `~/.grok/`, temp | allowed |
| `read-only` | everywhere | `~/.grok/`, temp | blocked on Linux |
| `strict` | CWD + system paths | CWD, `~/.grok/`, temp | blocked on Linux |

```bash
grok --sandbox strict    # reviewing untrusted code
```

A permission bug in the agent cannot out-argue the kernel. Layering these two is the correct design, and it is worth copying.

## The rest of the harness

Three more subsystems deserve a mention, because every serious coding agent is converging on the same checklist:

**Subagents.** Independent child sessions with their own context windows. The main agent delegates research, implementation, or review without burning its own context, and gets a summary back. Agent definitions are markdown files in `.grok/agents/`; personas in config layer behavioral overlays on top.

**Background tasks.** Long commands run with `background: true`, return a `task_id` immediately, and notify the conversation on completion. A `monitor` tool and a `/loop` command build on the same machinery.

**Workspace and checkpoints.** `xai-grok-workspace` plus `xai-fast-worktree` give the agent VCS awareness, compaction checkpoints, and fast git worktrees for parallel work.

MCP support ties it together, and here the compatibility story is genuinely pragmatic: the runtime reads MCP server definitions from its own `config.toml`, and also from `~/.claude.json`, `~/.cursor/mcp.json`, and `.mcp.json`. Your existing tool servers come along for free. The whole thing ships with a 24-chapter user guide in the repo, covering plan mode, hooks, skills, plugins, memory, and sessions.

## The model layer is where it gets interesting

None of the above cares which model is on the other end. The sampler (`xai-grok-sampler`) speaks three wire protocols, selected per model with one config key:

| `api_backend` | Protocol |
|---|---|
| `chat_completions` (default) | OpenAI Chat Completions |
| `responses` | OpenAI Responses |
| `messages` | Anthropic Messages |

The model catalog is a three-layer merge, lowest priority first: hardcoded defaults, then models prefetched from the endpoint's `/v1/models`, then your own `[model.*]` entries in `~/.grok/config.toml`. Your config always wins.

Credentials resolve per model, in order: the model's own `api_key` or `env_key`, then your session token, then the global `XAI_API_KEY`. And the login screen is derived from that same logic. If the first viable auth method is an API key, the browser login flow never triggers. Give your default model its own `env_key` and the subscription simply stops being part of the system.

That is not a loophole. It is a documented feature, and the in-repo guide (`docs/user-guide/11-custom-models.md`) ships recipes for OpenAI, Anthropic, Ollama, and Together.

## Swapping the provider for real

I pointed the harness at Nebius Token Factory running Kimi K2.7 Code, an open-weights coding model. The complete integration:

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

```bash
export NEBIUS_API_KEY="v1...."
grok -p "What is 2+2?" -m kimi-k2.7-code
```

No login. Tool calling, file edits, subagents, MCP: the whole loop runs against a model xAI has never heard of. Pasted images route to Qwen2.5-VL on the same endpoint through a second `[model.*]` block.

Three things will bite you if you try this. All three bit me:

1. **Quote dotted TOML keys.** `[model.kimi-k2.7-code]` parses as nested tables and your model shows up mangled as `kimi-k2`. Write `[model."kimi-k2.7-code"]`.
2. **Pin the hidden helper models.** Session summaries and image description default to the `grok-build` model and 404 against any non-xAI endpoint. Pin them under `[models]`, and use full upstream IDs like `moonshotai/Kimi-K2.7-Code`, because the auxiliary sampler puts that string on the wire verbatim.
3. **Web search cannot be repointed.** The built-in tool calls a hosted WebSearch capability on xAI's `/responses` endpoint. No generic provider serves that. Set `disable_web_search = true` and bring your own search as an MCP server. I use Tavily's.

## What the swap does not give you

Honesty section. The `grok-build` model itself stays closed; open sourcing the harness does not open the weights, so no third party can host it. Hosted extras (image generation, video generation, server-side web search) are xAI services and stop working without an account. And how well the agent loop runs now depends entirely on the tool-calling quality of whatever model you picked. Kimi K2.7 Code handled file edits and multi-step tool use without a stumble. A weaker model will make the same harness feel broken.

## Why this matters

Every serious coding agent is converging on the same shape: a model-agnostic harness handling tools, permissions, sandboxing, and state, with a model plugged into one end. xAI just published a production-grade, kernel-sandboxed, protocol-split implementation of that shape in Rust, readable end to end.

Because the split is honest, "which agent" and "which model" are now separate decisions. I am running xAI's harness, Moonshot's model, Nebius's infrastructure, and Tavily's search. Four vendors, one config file, zero forks.

Full working config, setup script, and every gotcha above: **github.com/shivaylamba/grok-build-nebius**

Grok Build source: **github.com/xai-org/grok-build**
