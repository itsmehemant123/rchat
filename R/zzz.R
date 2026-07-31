.rchat_env <- new.env(parent = emptyenv())

.onLoad <- function(libname, pkgname) {
  .rchat_env$.server <- NULL
  .rchat_env$.port <- NULL
  .rchat_env$.config <- NULL
  .rchat_env$.conversation <- NULL
  .rchat_log_init()
  invisible()
}

.onUnload <- function(libpath) {
  rchat_stop()
  invisible()
}

rchat_addin <- function() {
  rchat_start()
  invisible()
}
