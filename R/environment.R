.fail <- function(...) stop(..., call. = FALSE)

.named_list <- function(x, label) {
  if (!is.list(x) || !length(x) || is.null(names(x)) ||
      anyNA(names(x)) || any(!nzchar(names(x))) || anyDuplicated(names(x)))
    .fail(label, " must be a nonempty list with unique names.")
  if (any(!grepl("^[A-Za-z][A-Za-z0-9_]*$", names(x))))
    .fail(label, " names must start with a letter and contain letters, digits or underscores.")
}

.month_dates <- function(x) {
  if (inherits(x, "Date") || inherits(x, "POSIXt")) {
    return(as.Date(format(x, "%Y-%m-01")))
  }
  x <- trimws(as.character(x))
  valid <- grepl("^[0-9]{4}-(0[1-9]|1[0-2])(-[0-9]{2})?$", x)
  out <- rep(as.Date(NA), length(x))
  # Month-level input is intentional; a supplied day is validated separately.
  for (i in which(valid & !is.na(x))) {
    text <- if (nchar(x[i]) == 7L) paste0(x[i], "-01") else x[i]
    d <- suppressWarnings(as.Date(text, format = "%Y-%m-%d"))
    if (!is.na(d) && format(d, "%Y-%m-%d") == text)
      out[i] <- as.Date(format(d, "%Y-%m-01"))
  }
  out
}

.name_dates <- function(x) {
  # One unambiguous YYYY-MM, YYYY_MM, YYYY.MM or YYYYMM token per layer.
  pattern <- "(?<![0-9])[12][0-9]{3}[-_.]?(0[1-9]|1[0-2])(?![0-9])"
  hits <- regmatches(x, gregexpr(pattern, x, perl = TRUE))
  if (any(lengths(hits) != 1L)) return(NULL)
  tokens <- gsub("[-_.]", "", vapply(hits, `[`, character(1), 1L))
  .month_dates(paste0(substr(tokens, 1, 4), "-", substr(tokens, 5, 6)))
}

prepare_environment <- function(rasters, dates = NULL) {
  .named_list(rasters, "rasters")
  if (!is.null(dates) && (!is.list(dates) || is.null(names(dates)) ||
      anyDuplicated(names(dates)) || any(!names(dates) %in% names(rasters))))
    .fail("dates must be a named list keyed by environmental variable.")
  layers <- lapply(rasters, function(x) {
    r <- if (inherits(x, "SpatRaster")) x else terra::rast(x)
    if (!nzchar(terra::crs(r))) .fail("Every raster needs an explicit coordinate reference system.")
    if (!terra::hasValues(r)) .fail("Every raster must contain data.")
    if (any(terra::is.factor(r))) .fail("Only continuous numeric environmental variables are supported.")
    r
  })
  month_map <- vector("list", length(layers)); names(month_map) <- names(layers)
  sources <- character(length(layers))
  for (i in seq_along(layers)) {
    r <- layers[[i]]; variable <- names(layers)[i]
    explicit <- dates[[variable]]
    if (!is.null(explicit)) {
      d <- .month_dates(explicit); sources[i] <- "supplied"
    } else {
      t <- terra::time(r)
      d <- if (inherits(t, "Date") || inherits(t, "POSIXt")) .month_dates(t) else NULL
      sources[i] <- "metadata"
      if (is.null(d) || anyNA(d)) {
        d <- .name_dates(names(r)); sources[i] <- "layer_names"
      }
    }
    if (is.null(d) || length(d) != terra::nlyr(r) || anyNA(d))
      .fail("Cannot identify every layer's month and year for '", variable,
            "'. Supply dates = list(", variable, " = ...), in layer order.")
    if (anyDuplicated(d)) .fail("Duplicate month-year layers in '", variable,
                               "'. Supply one layer per month, not daily or annual data.")
    month_map[[i]] <- format(d, "%Y-%m")
  }
  shared <- sort(Reduce(intersect, month_map))
  if (!length(shared)) .fail("The environmental variables have no shared month-year dates.")
  same <- all(vapply(layers, function(r)
    terra::compareGeom(layers[[1]][[1]], r[[1]], stopOnError = FALSE), logical(1)))
  manifest <- do.call(rbind, lapply(seq_along(layers), function(i) data.frame(
    variable = names(layers)[i], layer = seq_len(terra::nlyr(layers[[i]])),
    layer_name = names(layers[[i]]), month = month_map[[i]],
    date_source = sources[i], shared = month_map[[i]] %in% shared,
    stringsAsFactors = FALSE)))
  structure(list(rasters = layers, dates = month_map, shared_dates = shared,
                 same_grid = same, manifest = manifest), class = "occenv_environment")
}

.background_dates <- function(shared, option) {
  if (option == "full_period") return(shared)
  if (option == "latest_month") return(utils::tail(shared, 1L))
  years <- sort(unique(substr(shared, 1, 4)), decreasing = TRUE)
  for (y in years) {
    months <- sprintf("%s-%02d", y, 1:12)
    if (all(months %in% shared)) return(months)
  }
  .fail("latest_year needs a complete calendar year shared by every variable.")
}
