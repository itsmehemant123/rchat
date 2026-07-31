.rchat_tool_schema <- function(name, description, properties, required = character()) {
  list(
    name = name,
    description = description,
    parameters = list(
      type = "object",
      properties = properties,
      required = required
    )
  )
}

.rchat_tools <- function() {
  list(
    .rchat_tool_schema(
      "run_r_code",
      "Evaluate R code in the user's session and return its printed output and errors. State persists across calls (objects, loaded libraries).",
      list(code = list(type = "string", description = "R code to run")),
      required = "code"
    ),
    .rchat_tool_schema(
      "get_editor_context",
      "Return the active document path, cursor position, and selected text in the editor.",
      list()
    ),
    .rchat_tool_schema(
      "read_file",
      "Read a file from disk.",
      list(path = list(type = "string", description = "Absolute path to read"))
    ),
    .rchat_tool_schema(
      "write_file",
      "Write content to a file on disk.",
      list(path = list(type = "string", description = "Absolute path to write")),
      required = c("path", "content")
    ),
    .rchat_tool_schema(
      "list_files",
      "List files in a directory.",
      list(path = list(type = "string", description = "Directory to list (default current working directory)"))
    ),
    .rchat_tool_schema(
      "insert_code",
      "Insert code at the cursor position in the active editor document.",
      list(code = list(type = "string", description = "Code to insert"))
    ),
    .rchat_tool_schema(
      "set_ghost_text",
      "Show a gray ghost-text inline suggestion after the cursor (like Copilot).",
      list(code = list(type = "string", description = "Suggestion text"))
    ),
    .rchat_tool_schema(
      "clear_ghost_text",
      "Remove any ghost-text suggestion.",
      list()
    ),
    .rchat_tool_schema(
      "install_pkg",
      "Install an R package from CRAN.",
      list(pkg = list(type = "string", description = "Package name"))
    )
  )
}

.rchat_is_available <- function(fun) {
  requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable() &&
    rstudioapi::hasFun(fun)
}

.rchat_tool_exec <- function(name, args) {
  switch(
    name,
    run_r_code = .rchat_run_r_code(args$code %||% ""),
    get_editor_context = .rchat_editor_context(),
    read_file = .rchat_read_file(args$path),
    write_file = .rchat_write_file(args$path, args$content),
    list_files = .rchat_list_files(args$path %||% "."),
    insert_code = .rchat_insert_code(args$code),
    set_ghost_text = .rchat_set_ghost_text(args$code),
    clear_ghost_text = .rchat_clear_ghost_text(),
    install_pkg = .rchat_install_pkg(args$pkg),
    stop("Unknown tool: ", name, call. = FALSE)
  )
}

.rchat_run_r_code <- function(code) {
  if (!nzchar(trimws(code))) return(list(success = TRUE, output = ""))
  out <- tryCatch(
    {
      cap <- capture.output(
        withCallingHandlers(
          eval(parse(text = code), envir = globalenv()),
          message = function(m) cat(conditionMessage(m), file = stderr())
        ),
        type = "output"
      )
      list(success = TRUE, output = paste(cap, collapse = "\n"))
    },
    error = function(e) list(success = FALSE, output = conditionMessage(e))
  )
  out
}

.rchat_editor_context <- function() {
  if (!.rchat_is_available("getActiveDocumentContext")) {
    return(list(error = "rstudioapi editor context not available"))
  }
  ctx <- rstudioapi::getActiveDocumentContext()
  sel <- ""
  if (length(ctx$selection)) sel <- ctx$selection[[1]]$text
  list(
    document_path = ctx$path %||% "",
    document_id = ctx$id %||% "",
    selection = sel,
    cursor = list(
      row = ctx$selection[[1]]$range$start[[1]] - 1L,
      column = ctx$selection[[1]]$range$start[[2]] - 1L
    )
  )
}

.rchat_read_file <- function(path) {
  if (is.null(path) || !nzchar(path)) return(list(error = "No path provided"))
  if (!file.exists(path)) return(list(error = paste("File not found:", path)))
  tryCatch(
    list(content = paste(readLines(path, warn = FALSE), collapse = "\n")),
    error = function(e) list(error = conditionMessage(e))
  )
}

.rchat_write_file <- function(path, content) {
  if (is.null(path) || is.null(content)) return(list(error = "path and content required"))
  ok <- tryCatch({
    writeLines(content, path)
    TRUE
  }, error = function(e) {
    e$message
  })
  if (isTRUE(ok)) list(success = TRUE) else list(error = ok)
}

.rchat_list_files <- function(path) {
  if (!dir.exists(path)) return(list(error = paste("Not a directory:", path)))
  tryCatch(list(files = list.files(path, full.names = TRUE)), error = function(e) list(error = conditionMessage(e)))
}

.rchat_insert_code <- function(code) {
  if (!.rchat_is_available("insertText")) return(list(error = "rstudioapi insertText not available"))
  if (is.null(code) || !nzchar(code)) return(list(error = "No code provided"))
  rstudioapi::insertText(code)
  list(success = TRUE)
}

.rchat_set_ghost_text <- function(code) {
  if (!.rchat_is_available("setGhostText")) return(list(error = "rstudioapi setGhostText not available"))
  if (is.null(code) || !nzchar(code)) return(list(error = "No code provided"))
  rstudioapi::setGhostText(code)
  list(success = TRUE)
}

.rchat_clear_ghost_text <- function() {
  if (!.rchat_is_available("setGhostText")) return(list(error = "rstudioapi setGhostText not available"))
  rstudioapi::setGhostText("")
  list(success = TRUE)
}

.rchat_install_pkg <- function(pkg) {
  if (is.null(pkg) || !nzchar(pkg)) return(list(error = "No package provided"))
  tryCatch({
    utils::install.packages(pkg)
    list(success = TRUE)
  }, error = function(e) list(error = conditionMessage(e)))
}
