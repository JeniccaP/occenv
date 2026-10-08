\name{build_species_layers}
\alias{build_species_layers}
\title{Build Species Environmental Layers}
\usage{
build_species_layers(rasters, occurrences, dates = NULL,
  columns = list(), occurrence_rule = c("latest", "mean"),
  background = c("full_period", "latest_year", "latest_month"),
  outside_period = c("exclude", "nearest_same_month"),
  missing_date = c("exclude", "period_mean"), na_rm = FALSE,
  output_dir = NULL, overwrite = FALSE)
}
\arguments{
\item{rasters}{Named list of raster paths or SpatRaster objects, or the result of \code{prepare_environment}.}
\item{occurrences}{Named list of CSV paths or data frames. CSV paths use UTF-8; semicolon headers without commas select semicolon parsing and accept decimal commas. For other encodings, import a data frame yourself. Each entry is processed as one species or group. IDs need not be unique; source row numbers identify records.}
\item{dates}{Optional date mapping passed to \code{prepare_environment}.}
\item{columns}{Mapping with \code{id}, \code{longitude}, \code{latitude}, and either \code{date} or both \code{year} and \code{month}. Supply one mapping for all tables, or a named list of mappings by species. Common column names are detected; ambiguous coordinates or dates require a mapping.}
\item{occurrence_rule}{\code{latest} uses the most recent original occurrence month in each cell; \code{mean} averages distinct matched months equally.}
\item{background}{\code{full_period} averages all shared months; \code{latest_year} averages the latest complete shared calendar year; \code{latest_month} uses the latest shared month.}
\item{outside_period}{\code{exclude} excludes dates unavailable in any variable; \code{nearest_same_month} uses the nearest shared year with the same calendar month. Applies to internal date gaps too. Ties use the earlier year.}
\item{missing_date}{\code{exclude} excludes blank or incomplete dates; \code{period_mean} uses the mean over all shared months. Malformed dates are always excluded.}
\item{na_rm}{Whether temporal and occurrence means may ignore missing raster values. Default FALSE preserves missing values. With TRUE, an entirely missing series still returns NA.}
\item{output_dir}{Optional output directory. Writes rasters and three audit CSVs. No input data are copied.}
\item{overwrite}{Whether existing output files may be replaced. Default FALSE.}
}
\description{Extracts environmental values using occurrence coordinates and monthly dates, combines values within occurrence cells, and fills remaining cells with background values.}
\details{Coordinates must be WGS84 longitude and latitude in decimal degrees. Points are transformed to each raster's coordinate system; rasters retain their native grids. Matching grids produce one stack per species; different grids produce separate single-layer rasters. All dated extraction uses months shared by every variable. No interpolation or resampling is performed.

Missing IDs, invalid coordinates, malformed dates and points outside a variable's extent are excluded and reported. Range-valid coordinates are not proof of accurate locations. Blank year or month is an incomplete date. The latest rule uses monthly precision; days within a month do not change selection. If any dated records exist in a cell, undated records are not selected by the latest rule. For the mean rule, each distinct substituted or matched month is counted once; the period mean is one additional contribution if undated records are retained.

All valid raster cells are background unless occupied by an eligible occurrence. Occurrence cells with missing extracted values remain missing rather than falling back to background. Masks are inherited from the supplied rasters. Outputs combine dates and therefore have no single layer date. The audit files retain the dates used. Source files are never changed.}
\value{An \code{occenv_result} list: \code{layers} contains outputs by species; \code{records} is a long audit table by species, variable and source row; \code{environment} maps layers to dates; \code{settings} records all time windows and options. The selected column identifies rows contributing to the output.}
\examples{
library(terra)
r <- rast(nrows = 2, ncols = 2, nlyrs = 2,
          xmin = 0, xmax = 2, ymin = 0, ymax = 2, crs = "EPSG:4326")
values(r) <- cbind(rep(10, 4), rep(20, 4))
time(r) <- as.Date(c("2000-01-01", "2000-02-01"))
points <- data.frame(id = "one", longitude = 0.5, latitude = 1.5,
                     year = 2000, month = 1)
result <- build_species_layers(list(temperature = r), list(example = points))
values(result$layers$example)
}
