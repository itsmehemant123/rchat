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
      "/config" = httpuv::excludeStaticPath()
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
  if (identical(req$PATH_INFO, "/config")) {
    return(list(status = 200L, headers = list("Content-Type" = "application/json"),
                body = jsonlite::toJSON(rchat_config(), auto_unbox = TRUE, null = "null")))
  }
  list(status = 404L, headers = list("Content-Type" = "text/plain"), body = "Not found")
}

.rchat_ws_open <- function(ws) {
  ws$onMessage(function(binary, raw) {
    text <- if (binary) rawToChar(raw) else raw
    msg <- tryCatch(jsonlite::fromJSON(text, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(msg)) {
      .rchat_ws_send(ws, list(type = "error", message = "Invalid JSON payload"))
      return(invisible())
    }
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
    }
  })
}

.rchat_ws_send <- function(ws, payload) {
  ws$send(jsonlite::toJSON(payload, auto_unbox = TRUE, force = TRUE, null = "null"))
}

.rchat_handle_chat <- function(ws, msg) {
  msgs <- msg$messages
  if (is.null(msgs) || !length(msgs)) {
    .rchat_ws_send(ws, list(type = "error", message = "No messages provided"))
    return(invisible())
  }
  text <- tryCatch(
    rchat_agent_respond(msgs, stream_cb = function(delta) {
      .rchat_ws_send(ws, list(type = "delta", text = delta))
    }),
    error = function(e) {
      .rchat_ws_send(ws, list(type = "error", message = conditionMessage(e)))
      return(invisible())
    }
  )
  .rchat_ws_send(ws, list(type = "done", text = text))
  invisible()
}
