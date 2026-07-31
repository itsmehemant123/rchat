\name{rchat_start}
\alias{rchat_start}
\alias{rchat_stop}
\title{Start and stop the chat server}
\usage{
rchat_start(port = NULL, launch = TRUE)

rchat_stop()
}
\arguments{
\item{port}{Port to listen on. Defaults to \code{getOption("rstudiochat.port", 9011)}.}

\item{launch}{Whether to open the panel in the RStudio Viewer.}
}
\value{
\code{rchat_start} returns a list with \code{port} and \code{server}. \code{rchat_stop}
returns \code{TRUE} invisibly if a server was stopped.
}
\description{
Starts an \pkg{httpuv} server on localhost serving the chat UI and its WebSocket
endpoint, and opens the panel in the RStudio Viewer (when RStudio is available).
}
\examples{
\dontrun{
rchat_start()
rchat_stop()
}
}
