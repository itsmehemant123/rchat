.rchat_llm_defaults <- function(provider) {
  switch(
    provider,
    claude = list(
      base_url = "https://api.anthropic.com/v1/messages",
      model = "claude-sonnet-4-5"
    ),
    openai = list(
      base_url = "https://api.openai.com/v1/chat/completions",
      model = "gpt-4o-mini"
    ),
    stop("Unknown provider: ", provider, call. = FALSE)
  )
}

.rchat_llm_resolve <- function(cfg) {
  d <- .rchat_llm_defaults(cfg$provider)
  list(
    base_url = if (is.null(cfg$base_url)) d$base_url else cfg$base_url,
    model = if (is.null(cfg$model)) d$model else cfg$model,
    api_key = cfg$api_key
  )
}

.rchat_llm_headers <- function(provider, api_key) {
  switch(
    provider,
    claude = c(
      "x-api-key" = api_key,
      "anthropic-version" = "2023-06-01",
      "Content-Type" = "application/json"
    ),
    openai = c(
      "Authorization" = paste0("Bearer ", api_key),
      "Content-Type" = "application/json"
    )
  )
}

# tools: normalized list(name, description, parameters)
.rchat_tools_claude <- function(tools) {
  lapply(tools, function(t) {
    list(name = t$name, description = t$description, input_schema = t$parameters)
  })
}
.rchat_tools_openai <- function(tools) {
  lapply(tools, function(t) {
    list(
      type = "function",
      `function` = list(name = t$name, description = t$description, parameters = t$parameters)
    )
  })
}

.rchat_parse_sse_event <- function(block, on_event) {
  lines <- strsplit(block, "\n")[[1]]
  ev <- "message"
  data_lines <- character()
  for (ln in lines) {
    if (startsWith(ln, "event:")) ev <- trimws(substring(ln, 7))
    else if (startsWith(ln, "data:")) data_lines <- c(data_lines, trimws(substring(ln, 6)))
  }
  if (!length(data_lines)) return(invisible())
  payload <- tryCatch(
    jsonlite::fromJSON(paste(data_lines, collapse = ""), simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (!is.null(payload)) on_event(ev, payload)
  invisible()
}

# Returns an accumulator function( chunk ) -> parses SSE and forwards each
# event to on_event(event_type, data). Internal buffer is per-accumulator.
.rchat_sse_accumulator <- function(on_event) {
  buf <- raw()
  function(chunk) {
    buf <<- c(buf, chunk)
    txt <- rawToChar(buf)
    parts <- strsplit(txt, "\n\n", fixed = TRUE)[[1]]
    buf <<- charToRaw(parts[length(parts)])
    if (length(parts) > 1) for (i in seq_len(length(parts) - 1L)) .rchat_parse_sse_event(parts[i], on_event)
    TRUE
  }
}

.rchat_claude_chat <- function(cfg, resolved, messages, tools, stream_cb) {
  body <- list(
    model = resolved$model,
    max_tokens = 4096,
    stream = TRUE,
    messages = messages$content,
    tools = .rchat_tools_claude(tools)
  )
  if (!is.null(messages$system)) body$system <- messages$system

  req <- httr2::request(resolved$base_url) |>
    httr2::req_method("POST") |>
    httr2::req_headers(!!!.rchat_llm_headers("claude", resolved$api_key)) |>
    httr2::req_body_json(body)

  text <- ""
  tool_blocks <- list()

  on_event <- function(ev, data) {
    if (identical(data$type, "content_block_start")) {
      cb <- data$content_block
      if (identical(cb$type, "tool_use")) tool_blocks[[data$index + 1L]] <<- list(id = cb$id, name = cb$name, args = "")
    } else if (identical(data$type, "content_block_delta")) {
      delta <- data$delta
      if (is.null(delta)) return(invisible())
      if (identical(delta$type, "text_delta")) {
        text <<- paste0(text, delta$text)
        if (!is.null(stream_cb)) stream_cb(delta$text)
      } else if (identical(delta$type, "input_json_delta")) {
        idx <- data$index + 1L
        if (is.null(tool_blocks[[idx]])) tool_blocks[[idx]] <<- list(id = NA_character_, name = NA_character_, args = "")
        tool_blocks[[idx]]$args <<- paste0(tool_blocks[[idx]]$args, delta$partial_json)
      }
    }
  }

  acc <- .rchat_sse_accumulator(on_event)
  resp <- tryCatch(httr2::req_perform_stream(req, acc), error = function(e) e)
  if (inherits(resp, "error")) .rchat_http_error("claude", resolved, resp)

  tool_calls <- lapply(seq_along(tool_blocks), function(i) {
    b <- tool_blocks[[i]]
    args <- if (nzchar(b$args)) tryCatch(jsonlite::fromJSON(b$args), error = function(e) list()) else list()
    list(id = b$id, name = b$name, arguments = args)
  })
  if (!length(tool_calls)) tool_calls <- NULL

  list(role = "assistant", content = text, tool_calls = tool_calls)
}

# Enrich and log an httr2 error, then stop with a helpful message.
.rchat_http_error <- function(provider, resolved, e) {
  status <- e$status %||% "?"
  body_txt <- tryCatch(rawToChar(e$body), error = function(x) "?")
  .rchat_log("HTTP error [", provider, "] ", resolved$base_url, " status=", status,
             " body=", substr(body_txt, 1, 500), level = "error")
  detail <- if (nzchar(body_txt)) paste0(" (", substr(body_txt, 1, 300), ")") else ""
  stop(sprintf("%s request failed: %s%s", provider, conditionMessage(e), detail), call. = FALSE)
}

.rchat_openai_chat <- function(cfg, resolved, messages, tools, stream_cb) {
  body <- list(
    model = resolved$model,
    stream = TRUE,
    messages = messages$content,
    tools = .rchat_tools_openai(tools)
  )

  req <- httr2::request(resolved$base_url) |>
    httr2::req_method("POST") |>
    httr2::req_headers(!!!.rchat_llm_headers("openai", resolved$api_key)) |>
    httr2::req_body_json(body)

  text <- ""
  tool_calls <- list()

  on_event <- function(ev, data) {
    choices <- data$choices
    if (!is.list(choices) || !length(choices)) return(invisible())
    ch <- choices[[1]]
    delta <- ch$delta
    if (is.null(delta)) return(invisible())
    if (!is.null(delta$content)) {
      d <- delta$content
      if (is.character(d)) {
        if (nzchar(d)) {
          text <<- paste0(text, d)
          if (!is.null(stream_cb)) stream_cb(d)
        }
      } else if (length(d)) {
        for (part in d) {
          if (is.character(part)) {
            text <<- paste0(text, part)
            if (!is.null(stream_cb)) stream_cb(part)
          } else if (!is.null(part$text)) {
            text <<- paste0(text, part$text)
            if (!is.null(stream_cb)) stream_cb(part$text)
          }
        }
      }
    }
    if (!is.null(delta$tool_calls)) {
      for (tc in delta$tool_calls) {
        idx <- tc$index + 1L
        if (length(tool_calls) < idx || is.null(tool_calls[[idx]])) {
          tool_calls[[idx]] <<- list(id = NULL, name = "", args = "")
        }
        if (!is.null(tc$id)) tool_calls[[idx]]$id <<- tc$id
        fn <- tc[["function"]]
        if (!is.null(fn)) {
          if (nzchar(fn$name %||% "")) tool_calls[[idx]]$name <<- fn$name
          if (!is.null(fn$arguments)) tool_calls[[idx]]$args <<- paste0(tool_calls[[idx]]$args, fn$arguments)
        }
      }
    }
  }

  acc <- .rchat_sse_accumulator(on_event)
  resp <- tryCatch(httr2::req_perform_stream(req, acc), error = function(e) e)
  if (inherits(resp, "error")) .rchat_http_error("openai", resolved, resp)

  parsed <- lapply(seq_along(tool_calls), function(i) {
    b <- tool_calls[[i]]
    args <- if (nzchar(b$args)) tryCatch(jsonlite::fromJSON(b$args), error = function(e) list()) else list()
    list(id = b$id %||% paste0("call_", i), name = b$name, arguments = args)
  })
  if (!length(parsed)) parsed <- NULL

  list(role = "assistant", content = text, tool_calls = parsed)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# Public entry point. messages: list(system=..., content=...)  tools: normalized.
rchat_llm_chat <- function(messages, tools, stream_cb = NULL) {
  cfg <- rchat_config()
  resolved <- .rchat_llm_resolve(cfg)
  if (is.null(resolved$api_key)) {
    .rchat_log("No API key set (RCHAT_API_KEY)", level = "error")
    stop("No API key set (RCHAT_API_KEY).", call. = FALSE)
  }
  .rchat_log("LLM call: provider=", cfg$provider, " model=", resolved$model, " url=", resolved$base_url)
  switch(
    cfg$provider,
    claude = .rchat_claude_chat(cfg, resolved, messages, tools, stream_cb),
    openai = .rchat_openai_chat(cfg, resolved, messages, tools, stream_cb)
  )
}
