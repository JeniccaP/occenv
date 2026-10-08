.temporal_mean <- function(r, na_rm) {
  if (terra::nlyr(r) == 1L) return(r)
  # terra processes large file-backed rasters in blocks.
  ans <- terra::app(r, "mean", na.rm = na_rm)
  terra::ifel(is.nan(ans), NA, ans)
}

.project_cells <- function(d, r) {
  cells <- rep(NA_real_, nrow(d))
  good <- which(!grepl("^excluded", d$status))
  if (length(good)) {
    p <- terra::vect(d[good, c("longitude", "latitude")],
      geom = c("longitude", "latitude"), crs = "EPSG:4326")
    p <- terra::project(p, terra::crs(r))
    cells[good] <- terra::cellFromXY(r, terra::crds(p))
  }
  cells
}

.extract_cells <- function(r, cells) {
  if (!length(cells)) return(numeric())
  as.numeric(terra::extract(r, cells)[, 1L])
}

.species_variable <- function(d, r, months, shared_mean, background,
                              occurrence_rule, na_rm) {
  d$cell <- .project_cells(d, r)
  d$value <- NA_real_; d$selected <- FALSE
  eligible <- !grepl("^excluded", d$status)
  d$status[eligible & is.na(d$cell)] <- "excluded_outside_extent"
  eligible <- which(!grepl("^excluded", d$status))
  for (month in unique(stats::na.omit(d$used_month[eligible]))) {
    idx <- eligible[!is.na(d$used_month[eligible]) & d$used_month[eligible] == month]
    d$value[idx] <- .extract_cells(r[[match(month, months)]], d$cell[idx])
  }
  missing_idx <- eligible[d$status[eligible] == "period_mean"]
  d$value[missing_idx] <- .extract_cells(shared_mean, d$cell[missing_idx])
  result <- background
  groups <- split(eligible, d$cell[eligible])
  cell_values <- rep(NA_real_, length(groups))
  g <- 0L
  for (idx in groups) {
    chosen <- idx
    dated <- idx[!is.na(d$occurrence_month[idx])]
    if (occurrence_rule == "latest" && length(dated)) {
      latest <- max(d$occurrence_month[dated])
      chosen <- dated[d$occurrence_month[dated] == latest]
    }
    # Repeated sightings and repeated fallback months do not increase weights.
    key <- ifelse(d$status[chosen] == "period_mean", "period_mean", d$used_month[chosen])
    chosen <- chosen[!duplicated(key)]
    d$selected[chosen] <- TRUE
    value <- mean(d$value[chosen], na.rm = na_rm)
    if (is.nan(value)) value <- NA_real_
    g <- g + 1L
    cell_values[g] <- value
  }
  if (length(groups)) result[as.numeric(names(groups))] <- cell_values
  d$value_missing <- !grepl("^excluded", d$status) & is.na(d$value)
  list(raster = result, records = d)
}

build_species_layers <- function(rasters, occurrences, dates = NULL,
    columns = list(), occurrence_rule = c("latest", "mean"),
    background = c("full_period", "latest_year", "latest_month"),
    outside_period = c("exclude", "nearest_same_month"),
    missing_date = c("exclude", "period_mean"), na_rm = FALSE,
    output_dir = NULL, overwrite = FALSE) {
  occurrence_rule <- match.arg(occurrence_rule)
  background <- match.arg(background)
  outside_period <- match.arg(outside_period)
  missing_date <- match.arg(missing_date)
  if (!is.logical(na_rm) || length(na_rm) != 1L || is.na(na_rm))
    .fail("na_rm must be TRUE or FALSE.")
  if (!is.logical(overwrite) || length(overwrite) != 1L || is.na(overwrite))
    .fail("overwrite must be TRUE or FALSE.")
  env <- if (inherits(rasters, "occenv_environment")) rasters else prepare_environment(rasters, dates)
  if (inherits(rasters, "occenv_environment") && !is.null(dates))
    .fail("Set dates in prepare_environment, not alongside a prepared environment.")
  .named_list(occurrences, "occurrences")
  # columns can be one mapping for all tables, or named mappings per table.
  per_species <- length(columns) && all(vapply(columns, is.list, logical(1)))
  if (per_species && (is.null(names(columns)) || any(!names(columns) %in% names(occurrences))))
    .fail("Per-species column mappings must use the occurrence list names.")
  data <- lapply(seq_along(occurrences), function(i) {
    mapping <- if (per_species) columns[[names(occurrences)[i]]] else columns
    if (is.null(mapping)) mapping <- list()
    .resolve_dates(.read_occurrences(occurrences[[i]], mapping), env$shared_dates,
      outside_period, missing_date)
  })
  names(data) <- names(occurrences)
  bg_dates <- .background_dates(env$shared_dates, background)
  if (!is.null(output_dir)) {
    if (!is.character(output_dir) || length(output_dir) != 1L || !nzchar(output_dir))
      .fail("output_dir must be one directory path.")
    paths <- if (env$same_grid) paste0(names(data), ".tif") else
      unlist(lapply(names(data), function(s) paste0(s, "__", names(env$rasters), ".tif")))
    targets <- file.path(output_dir, c(paths, "records.csv", "environment.csv", "settings.csv"))
    if (anyDuplicated(targets)) .fail("Output file names collide; rename species or variables.")
    if (!overwrite && any(file.exists(targets))) .fail("Output files already exist. Choose another directory or set overwrite = TRUE.")
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
    if (!dir.exists(output_dir)) .fail("Cannot create output directory.")
  }
  bg <- full <- vector("list", length(env$rasters))
  need_full <- any(vapply(data, function(d) any(d$status == "period_mean"), logical(1)))
  for (j in seq_along(env$rasters)) {
    r <- env$rasters[[j]]
    bg[[j]] <- .temporal_mean(r[[match(bg_dates, env$dates[[j]])]], na_rm)
    full[[j]] <- if (!need_full || identical(bg_dates, env$shared_dates)) bg[[j]] else
      .temporal_mean(r[[match(env$shared_dates, env$dates[[j]])]], na_rm)
  }
  outputs <- vector("list", length(data)); names(outputs) <- names(data)
  records <- list(); k <- 0L
  for (i in seq_along(data)) {
    layers <- vector("list", length(env$rasters)); names(layers) <- names(env$rasters)
    for (j in seq_along(env$rasters)) {
      ans <- .species_variable(data[[i]], env$rasters[[j]], env$dates[[j]],
        full[[j]], bg[[j]], occurrence_rule, na_rm)
      names(ans$raster) <- names(env$rasters)[j]
      # These layers combine different times, so no single time is valid.
      terra::time(ans$raster) <- NULL
      layers[[j]] <- ans$raster
      k <- k + 1L
      records[[k]] <- cbind(species_file = names(data)[i],
        variable = names(env$rasters)[j], ans$records)
    }
    outputs[[i]] <- if (env$same_grid) do.call(c, unname(layers)) else layers
    if (!is.null(output_dir)) {
      if (env$same_grid) {
        outputs[[i]] <- terra::writeRaster(outputs[[i]], file.path(output_dir,
          paste0(names(data)[i], ".tif")), overwrite = overwrite,
          wopt = list(gdal = c("COMPRESS=DEFLATE")))
      } else {
        for (j in seq_along(layers)) outputs[[i]][[j]] <- terra::writeRaster(layers[[j]],
          file.path(output_dir, paste0(names(data)[i], "__", names(layers)[j], ".tif")),
          overwrite = overwrite, wopt = list(gdal = c("COMPRESS=DEFLATE")))
      }
    }
  }
  report <- do.call(rbind, records); rownames(report) <- NULL
  settings <- list(occurrence_rule = occurrence_rule, background = background,
    outside_period = outside_period, missing_date = missing_date, na_rm = na_rm,
    same_grid = env$same_grid, background_dates = bg_dates,
    shared_dates = env$shared_dates, background_area = "all_valid_cells",
    package_version = as.character(utils::packageVersion("occenv")))
  if (!is.null(output_dir)) {
    utils::write.csv(report, file.path(output_dir, "records.csv"), row.names = FALSE, na = "")
    utils::write.csv(env$manifest, file.path(output_dir, "environment.csv"), row.names = FALSE)
    settings_table <- data.frame(setting = names(settings), value = vapply(settings,
      function(x) paste(x, collapse = ";"), character(1)))
    utils::write.csv(settings_table, file.path(output_dir, "settings.csv"), row.names = FALSE)
  }
  structure(list(layers = outputs, records = report, environment = env$manifest,
    settings = settings), class = "occenv_result")
}
