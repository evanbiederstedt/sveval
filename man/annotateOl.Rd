% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/annotateOl.R
\name{annotateOl}
\alias{annotateOl}
\title{Annotate SVs from overlap}
\usage{
annotateOl(ol.l, min.qual = 0)
}
\arguments{
\item{ol.l}{output of an overlap function (olInsertions or olRanges).}

\item{min.qual}{the minimum QUAL considered for the calls.}
}
\value{
an updated list with a *cov* column added to the calls and truth sets.
}
\description{
Annotate SVs from overlap
}
\author{
Jean Monlong
}
\keyword{internal}
