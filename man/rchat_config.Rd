\name{rchat_config}
\alias{rchat_config}
\alias{rchat_set_config}
\title{Get or set the chat configuration}
\usage{
rchat_config()

rchat_set_config(
  provider = NULL,
  base_url = NULL,
  api_key = NULL,
  model = NULL,
  max_iterations = NULL
)
}
\arguments{
\item{provider}{Provider protocol: \code{"claude"} (default) or \code{"openai"}.}

\item{base_url}{Base URL of the API endpoint. Defaults per provider.}

\item{api_key}{API key. Defaults to the \code{RCHAT_API_KEY} environment variable.}

\item{model}{Model name. Defaults per provider.}

\item{max_iterations}{Maximum agent tool-use iterations (default 20).}
}
\value{
\code{rchat_config} returns the current configuration as a list. \code{rchat_set_config}
updates and returns it.
}
\description{
Provider and connection settings for the chat. Settings can also be configured via
environment variables \code{RCHAT_PROVIDER}, \code{RCHAT_BASE_URL}, \code{RCHAT_API_KEY},
\code{RCHAT_MODEL}, and \code{RCHAT_MAX_ITERATIONS} (e.g. in \file{.Renviron}).
}
\examples{
\dontrun{
rchat_set_config(provider = "openai", model = "gpt-4o")
rchat_config()
}
}
