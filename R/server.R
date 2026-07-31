.rchat_www_dir <- function() {
  system.file("www", package = "rstudiochat")
}

.rchat_default_port <- function() {
  getOption("rstudiochat.port", 9011L)
}

.rchat_port_available <- function(port) {
  con <- tryCatch(suppressWarnings(socketConnection("127.0.0.1", port, open = "r", timeout = 0.2)),
                  error = function(e) NULL)
  if (!is.null(con)) {
    close(con)
    FALSE
  } else {
    TRUE
  }
}

.rchat_find_port <- function() {
  for (p in .rchat_default_port():(.rchat_default_port() + 100L)) {
    if (.rchat_port_available(p)) return(p)
  }
  .rchat_default_port()
}

#' Start the chat server and open the panel
#' @export
rchat_start <- function(port = NULL, launch = TRUE) {
  if (!requireNamespace("httpuv", quietly = TRUE)) {
    stop("The httpuv package is required. Install with: install.packages('httpuv')", call. = FALSE)
  }
  srv <- .rchat_env$.server
  if (!is.null(srv)) {
    port <- .rchat_env$.port
    if (launch) .rchat_open_viewer(port)
    return(invisible(list(port = port, server = srv)))
  }
  port <- port %||% .rchat_find_port()
  www <- .rchat_www_dir()
  app <- list(
    call = function(req) .rchat_router(req),
    onWSOpen = function(ws) .rchat_ws_open(ws),
    staticPaths = list(
      "/" = www,
      "/config" = httpuv::excludeStaticPath(),
      "/log" = httpuv::excludeStaticPath(),
      "/log/clear" = httpuv::excludeStaticPath()
    ),
    staticPathOptions = httpuv::staticPathOptions(indexhtml = TRUE)
  )
  srv <- httpuv::startServer("127.0.0.1", port, app)
  .rchat_env$.port <- port
  .rchat_env$.server <- srv
  if (launch) .rchat_open_viewer(port)
  invisible(list(port = port, server = srv))
}

.rchat_open_viewer <- function(port) {
  if (requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
    rstudioapi::viewer(paste0("http://127.0.0.1:", port, "/"))
  } else {
    message("RStudio Chat running at http://127.0.0.1:", port, "/")
  }
}

#' Stop the chat server
#' @export
rchat_stop <- function() {
  srv <- .rchat_env$.server
  if (is.null(srv)) return(invisible(FALSE))
  httpuv::stopServer(srv)
  .rchat_env$.server <- NULL
  invisible(TRUE)
}

.rchat_router <- function(req) {
  path <- req$PATH_INFO
  if (identical(path, "/config")) {
    return(list(status = 200L, headers = list("Content-Type" = "application/json"),
                body = jsonlite::toJSON(rchat_config(), auto_unbox = TRUE, null = "null")))
  }
  if (identical(path, "/log")) {
    .rchat_log("GET /log by client")
    return(list(status = 200L, headers = list("Content-Type" = "application/json"),
                body = jsonlite::toJSON(.rchat_log_dump(), auto_unbox = TRUE, null = "null")))
  }
  if (identical(path, "/log/clear")) {
    .rchat_log_clear()
    return(list(status = 200L, headers = list("Content-Type" = "application/json"),
                body = "[]"))
  }
  list(status = 404L, headers = list("Content-Type" = "text/plain"), body = "Not found")
}

.rchat_ws_open <- function(ws) {
  .rchat_log("WebSocket client connected")
  ws$onClose(function() .rchat_log("WebSocket client disconnected"))
  ws$onMessage(function(binary, raw) {
    text <- if (binary) rawToChar(raw) else raw
    msg <- tryCatch(jsonlite::fromJSON(text, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(msg)) {
      .rchat_log("WebSocket: invalid JSON payload: ", substr(text, 1, 200), level = "error")
      .rchat_ws_send(ws, list(type = "error", message = "Invalid JSON payload"))
      return(invisible())
    }
    .rchat_log("WebSocket message: type=", msg$type %||% "?")
    if (identical(msg$type, "chat")) {
      .rchat_handle_chat(ws, msg)
    } else if (identical(msg$type, "insert")) {
      res <- tryCatch(.rchat_tool_exec("insert_code", list(code = msg$code)),
                      error = function(e) list(error = conditionMessage(e)))
      .rchat_ws_send(ws, list(type = "tool_result", tool = "insert_code", result = res))
    } else if (identical(msg$type, "run")) {
      res <- tryCatch(.rchat_tool_exec("run_r_code", list(code = msg$code)),
                      error = function(e) list(error = conditionMessage(e)))
      .rchat_ws_send(ws, list(type = "tool_result", tool = "run_r_code", result = res))
    } else if (identical(msg$type, "config")) {
      .rchat_ws_send(ws, list(type = "config", config = rchat_config()))
    } else if (identical(msg$type, "ping")) {
      .rchat_ws_send(ws, list(type = "pong"))
    }
  })
}

.rchat_ws_send <- function(ws, payload) {
  ws$send(jsonlite::toJSON(payload, auto_unbox = TRUE, force = TRUE, null = "null"))
}

.rchat_handle_chat <- function(ws, msg) {
  msgs <- msg$messages
  if (is.null(msgs) || !length(msgs)) {
    .rchat_log("chat: no messages", level = "error")
    .rchat_ws_send(ws, list(type = "error", message = "No messages provided"))
    return(invisible())
  }
  .rchat_log("chat: agent starting with ", length(msgs), " messages")
  text <- tryCatch(
    rchat_agent_respond(msgs,
      stream_cb = function(delta) .rchat_ws_send(ws, list(type = "delta", text = delta)),
      think_cb = function(delta) .rchat_ws_send(ws, list(type = "thinking", text = delta))
    ),
    error = function(e) {
      .rchat_log("chat: agent error: ", conditionMessage(e), level = "error")
      .rchat_ws_send(ws, list(type = "error", message = conditionMessage(e)))
      return(invisible())
    }
  )
  .rchat_log("chat: agent done")
  .rchat_ws_send(ws, list(type = "done", text = text))
  invisible()
}
