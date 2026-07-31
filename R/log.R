.rchat_log_init <- function() {
  .rchat_env$.log <- list()
  .rchat_env$.log_max <- 1000L
}

.rchat_log <- function(..., level = "info") {
  if (is.null(.rchat_env$.log)) .rchat_log_init()
  msg <- paste0(...)
  entry <- list(time = format(Sys.time(), "%H:%M:%OS3"), level = level, msg = msg)
  .rchat_env$.log[[length(.rchat_env$.log) + 1L]] <- entry
  n <- length(.rchat_env$.log)
  if (n > .rchat_env$.log_max) {
    .rchat_env$.log <- .rchat_env$.log[(n - .rchat_env$.log_max + 1L):n]
  }
  invisible(entry)
}

.rchat_log_dump <- function() {
  if (is.null(.rchat_env$.log)) .rchat_log_init()
  .rchat_env$.log
}

.rchat_log_clear <- function() {
  .rchat_env$.log <- list()
  invisible()
}
