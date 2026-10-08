\name{prepare_environment}
\alias{prepare_environment}
\title{Validate Monthly Environmental Stacks}
\usage{prepare_environment(rasters, dates = NULL)}
\arguments{
\item{rasters}{Named list of continuous numeric \code{terra::SpatRaster} objects or raster file paths. One variable per entry, one layer per month. Names must start with a letter and contain only letters, digits or underscores.}
\item{dates}{Optional named list of date vectors, one per variable, in layer order. Use Date objects, YYYY-MM or YYYY-MM-DD strings. Explicit dates override metadata and names.}
}
\description{Reads monthly dates from explicit mappings, Date or POSIX time metadata, or unambiguous YYYY-MM, YYYY_MM, YYYY.MM or YYYYMM layer names. Validates coordinate reference systems and finds shared months.}
\details{Numeric annual or month-only metadata cannot identify month and year and requires an explicit mapping. Duplicate month-year layers are rejected. Grids are compared but never resampled. Daily, categorical, annual and submonthly input are not supported.}
\value{An \code{occenv_environment} list containing rasters, dates, shared dates, a same-grid flag and a layer manifest.}
\examples{
library(terra)
r <- rast(nrows = 2, ncols = 2, nlyrs = 2,
          xmin = 0, xmax = 2, ymin = 0, ymax = 2, crs = "EPSG:4326")
values(r) <- cbind(1:4, 5:8)
time(r) <- as.Date(c("2000-01-01", "2000-02-01"))
env <- prepare_environment(list(temperature = r))
env$shared_dates
}
