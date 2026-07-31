# RStudio Chat

A Copilot/Claude-style chat panel for RStudio. It runs in the RStudio **Viewer**
pane and connects to Anthropic- or OpenAI-compatible LLM providers. Behind the
scenes it runs a **tool-use agent** that can inspect and control the R session:
run code, read/write files, inspect the editor, insert suggestions, and more.

## Features

- Chat sidebar hosted in the RStudio Viewer pane (dockable tab)
- Streaming responses (token by token)
- Tool-use agent loop with guardrails (max iterations)
- Two provider protocols so *any* hosting provider works:
  - `claude` — Anthropic Messages API (Anthropic, OpenRouter, many local hosts)
  - `openai` — OpenAI Chat Completions (OpenAI, OpenRouter, vLLM, LM Studio, etc.)
- Code blocks in replies with **Insert** and **Run** buttons
- Ghost-text inline suggestions (Copilot-style)

## Requirements

- R (>= 4.0)
- RStudio (any recent version)
- R packages: `httpuv`, `httr2`, `jsonlite` (installed automatically with the
  package)

## Installation

```r
# install.packages("remotes")
remotes::install_github("<you>/rstudio-chat")
```

Or install from a local checkout:

```r
devtools::install("path/to/rstudio-chat")
```

## Configuration

Create or edit your `~/.Renviron` file (restart R after editing) with the
settings for your provider.

### Anthropic-compatible (default)

```r
RCHAT_PROVIDER=claude
RCHAT_API_KEY=sk-ant-...
RCHAT_MODEL=claude-sonnet-4-5
# RCHAT_BASE_URL=https://api.anthropic.com/v1/messages   # default
```

### OpenAI-compatible

```r
RCHAT_PROVIDER=openai
RCHAT_API_KEY=sk-...
RCHAT_MODEL=gpt-4o-mini
# RCHAT_BASE_URL=https://api.openai.com/v1/chat/completions  # default
```

### Any other Anthropic/OpenAI-compatible host

```r
RCHAT_PROVIDER=claude          # or openai
RCHAT_BASE_URL=https://your-host.example/v1/messages        # anthropic-compatible
# RCHAT_BASE_URL=https://your-host.example/v1/chat/completions  # openai-compatible
RCHAT_API_KEY=...
RCHAT_MODEL=...
```

Optional settings:

```r
RCHAT_MAX_ITERATIONS=20   # max agent tool-use rounds
```

You can also set these at runtime:

```r
library(rstudiochat)
rchat_set_config(
  provider = "openai",
  base_url = "https://your-host.example/v1/chat/completions",
  api_key = "sk-...",
  model = "gpt-4o"
)
```

## Usage

1. Launch RStudio and install/load the package.
2. Run the addin: **Tools → Addins → RStudio Chat**, or run:

   ```r
   library(rstudiochat)
   rchat_start()
   ```

3. A chat tab opens in the Viewer pane. Type a request — for example:

   > "Read iris, compute the mean of Sepal.Length by Species, and show a summary."

   The agent will run code in your session and report results. Code blocks in the
   reply have **Insert** (insert at the cursor in your editor) and **Run**
   (execute in the console/session) buttons.

To stop the server:

```r
rchat_stop()
```

## How it works

- `R/server.R` — an `httpuv` server on localhost serving the chat UI and a
  WebSocket endpoint.
- `R/llm.R` — provider abstraction (`claude` / `openai` adapters) with
  streaming and tool-use support.
- `R/agent.R` — the tool-use loop: send messages + tools → LLM → dispatch tool
  calls → append results → repeat (bounded by `max_iterations`).
- `R/tools.R` — tools backed by `rstudioapi`:

  | Tool | Purpose |
  |------|---------|
  | `run_r_code` | Evaluate R code in the session, return output/errors |
  | `get_editor_context` | Active document path, cursor, selection |
  | `read_file` / `write_file` | Read/write files on disk |
  | `list_files` | List a directory |
  | `insert_code` | Insert code at the editor cursor |
  | `set/clear_ghost_text` | Copilot-style inline suggestions |
  | `install_pkg` | Install an R package from CRAN |

## Development

Run checks and tests:

```bash
R CMD build .
R CMD check rstudiochat_0.1.0.tar.gz
```

```r
# from the package root
testthat::test_local()
```

## Roadmap

- Config UI in the panel (instead of env vars only)
- Persistent conversation history across sessions
- More tools (plots, git, background jobs)
- `rstudioapi`-backed "Run" so code executes in the user's console
