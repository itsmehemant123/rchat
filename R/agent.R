.rchat_system_prompt <- function() {
  paste(
    "You are RStudio Chat, an assistant embedded in the RStudio IDE.",
    "You help the user analyze data and write R code by acting as an agent.",
    "Use tools to run code, inspect the editor and filesystem, and iterate.",
    "When you propose code, you may run it and report results rather than only printing code.",
    "Prefer using tools over merely showing code, unless the user asks you not to."
  )
}

.rchat_provider_msg <- function(provider, role, content) {
  if (identical(role, "user") || identical(role, "assistant")) {
    if (provider == "claude") {
      return(list(role = role, content = list(list(type = "text", text = content))))
    }
    return(list(role = role, content = content))
  }
  stop("Unknown message role: ", role, call. = FALSE)
}

# encode an assistant message that may carry tool_calls
.rchat_encode_assistant <- function(provider, msg) {
  if (provider == "claude") {
    blocks <- list()
    if (nzchar(msg$content)) blocks[[1]] <- list(type = "text", text = msg$content)
    if (!is.null(msg$tool_calls)) {
      for (tc in msg$tool_calls) {
        blocks[[length(blocks) + 1L]] <- list(
          type = "tool_use", id = tc$id, name = tc$name, input = tc$arguments
        )
      }
    }
    return(list(role = "assistant", content = blocks))
  }
  m <- list(role = "assistant", content = if (nzchar(msg$content)) msg$content else NULL)
  if (!is.null(msg$tool_calls)) {
    m$tool_calls <- lapply(msg$tool_calls, function(tc) {
      list(id = tc$id, type = "function",
           `function` = list(name = tc$name, arguments = jsonlite::toJSON(tc$arguments, auto_unbox = TRUE)))
    })
  }
  m
}

.rchat_encode_tool_result <- function(provider, tc, result) {
  text <- jsonlite::toJSON(result, auto_unbox = TRUE, force = TRUE)
  if (provider == "claude") {
    list(role = "user", content = list(list(type = "tool_result", tool_use_id = tc$id, content = text)))
  } else {
    list(role = "tool", tool_call_id = tc$id, content = text)
  }
}

# frontend_messages: list of list(role=, content=); stream_cb receives text deltas.
rchat_agent_respond <- function(frontend_messages, stream_cb = NULL) {
  cfg <- rchat_config()
  provider <- cfg$provider
  tools <- .rchat_tools()

  messages <- lapply(frontend_messages, function(m) {
    .rchat_provider_msg(provider, m$role, m$content)
  })
  system <- .rchat_system_prompt()

  n_iter <- 0L
  final_text <- ""
  repeat {
    n_iter <- n_iter + 1L
    if (n_iter > cfg$max_iterations) {
      final_text <- paste0(final_text, "\n[stopped after max iterations]")
      break
    }
    assistant <- rchat_llm_chat(list(system = system, content = messages), tools, stream_cb)
    messages[[length(messages) + 1L]] <- .rchat_encode_assistant(provider, assistant)

    if (is.null(assistant$tool_calls)) {
      final_text <- assistant$content
      break
    }
    for (tc in assistant$tool_calls) {
      result <- tryCatch(.rchat_tool_exec(tc$name, tc$arguments), error = function(e) list(error = conditionMessage(e)))
      messages[[length(messages) + 1L]] <- .rchat_encode_tool_result(provider, tc, result)
    }
  }
  final_text
}
