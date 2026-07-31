rchat_default_config <- function() {
  list(
    provider = "claude",
    base_url = NULL,
    api_key = NULL,
    model = NULL,
    max_iterations = 20L,
    system_prompt = NULL
  )
}

rchat_config_env <- function() {
  cfg <- rchat_default_config()
  provider <- Sys.getenv("RCHAT_PROVIDER", unset = "")
  if (nzchar(provider)) cfg$provider <- provider
  base_url <- Sys.getenv("RCHAT_BASE_URL", unset = "")
  if (nzchar(base_url)) cfg$base_url <- base_url
  api_key <- Sys.getenv("RCHAT_API_KEY", unset = "")
  if (nzchar(api_key)) cfg$api_key <- api_key
  model <- Sys.getenv("RCHAT_MODEL", unset = "")
  if (nzchar(model)) cfg$model <- model
  max_iter <- Sys.getenv("RCHAT_MAX_ITERATIONS", unset = "")
  if (nzchar(max_iter)) cfg$max_iterations <- as.integer(max_iter)
  cfg
}

#' @export
rchat_config <- function() {
  if (!exists(".rchat_config", envir = .rchat_env)) {
    .rchat_env$.rchat_config <- rchat_config_env()
  }
  .rchat_env$.rchat_config
}

#' @export
rchat_set_config <- function(provider = NULL, base_url = NULL, api_key = NULL,
                             model = NULL, max_iterations = NULL) {
  cfg <- rchat_config()
  if (!is.null(provider)) cfg$provider <- provider
  if (!is.null(base_url)) cfg$base_url <- base_url
  if (!is.null(api_key)) cfg$api_key <- api_key
  if (!is.null(model)) cfg$model <- model
  if (!is.null(max_iterations)) cfg$max_iterations <- max_iterations
  .rchat_env$.rchat_config <- cfg
  cfg
}
