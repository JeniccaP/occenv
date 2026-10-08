.find_column <- function(d, provided, alternatives, required = TRUE) {
  if (!is.null(provided)) {
    if (length(provided) != 1L || !provided %in% names(d))
      .fail("Mapped column not found: ", paste(provided, collapse = ", "))
    return(provided)
  }
  hits <- names(d)[tolower(names(d)) %in% alternatives]
  if (length(hits) > 1L) .fail("Ambiguous columns: ", paste(hits, collapse = ", "), ". Supply columns explicitly.")
  if (!length(hits)) {
    if (required) .fail("Required column missing. Expected one of: ", paste(alternatives, collapse = ", "))
    return(NULL)
  }
  hits
}

.read_occurrences <- function(x, columns) {
  decimal_comma <- FALSE
  if (is.data.frame(x)) {
    d <- x
  } else {
    if (!is.character(x) || length(x) != 1L || !file.exists(x))
      .fail("Each occurrence entry must be a data frame or an existing CSV path.")
    header <- readLines(x, n = 1L, warn = FALSE, encoding = "UTF-8")
    sep <- if (length(header) && grepl(";", header) && !grepl(",", header)) ";" else ","
    decimal_comma <- sep == ";"
    d <- tryCatch(withCallingHandlers(utils::read.csv(x, sep = sep, colClasses = "character",
      check.names = FALSE, na.strings = c("", "NA"), fileEncoding = "UTF-8-BOM"),
      warning = function(w) stop(conditionMessage(w), call. = FALSE)),
      error = function(e) .fail("Cannot read CSV '", basename(x),
        "'. Read it with read.csv using its separator and encoding, then pass the data frame. ",
        conditionMessage(e)))
  }
  if (!nrow(d)) .fail("Occurrence tables must contain at least one row.")
  if (anyDuplicated(names(d))) .fail("Occurrence column names must be unique.")
  if (!is.list(columns)) .fail("columns must be a list.")
  if (any(!names(columns) %in% c("id", "longitude", "latitude", "date", "year", "month")))
    .fail("Unknown column mapping; use id, longitude, latitude, date, year or month.")
  id_candidates <- c("id", "gbif_id", "gbifid", "outbreak_id", "outbreakid",
    "occurrence_id", "occurrenceid", "species")
  id_auto <- names(d)[match(id_candidates, tolower(names(d)), nomatch = 0L)]
  id <- .find_column(d, if (!is.null(columns$id)) columns$id else utils::head(id_auto, 1L), id_candidates)
  lon <- .find_column(d, columns$longitude, c("longitude", "long", "lon", "decimallongitude"))
  lat <- .find_column(d, columns$latitude, c("latitude", "lat", "decimallatitude"))
  # Explicit year/month takes priority over automatic date discovery.
  date <- if (!is.null(columns$year) || !is.null(columns$month)) NULL else
    .find_column(d, columns$date, c("date", "event_date", "eventdate"), FALSE)
  year <- month <- NULL
  if (is.null(date)) {
    year <- .find_column(d, columns$year, "year", FALSE)
    month <- .find_column(d, columns$month, "month", FALSE)
  }
  original <- rep(NA_character_, nrow(d)); missing <- rep(TRUE, nrow(d))
  if (!is.null(date)) {
    original <- trimws(as.character(d[[date]]))
    missing <- is.na(original) | !nzchar(original)
    parsed <- .month_dates(original)
  } else if (!is.null(year) && !is.null(month)) {
    y <- trimws(as.character(d[[year]])); m <- trimws(as.character(d[[month]]))
    missing <- is.na(y) | is.na(m) | !nzchar(y) | !nzchar(m)
    good <- !missing & grepl("^[0-9]{4}$", y) & grepl("^[0-9]{1,2}$", m)
    original <- paste(y, m, sep = "-")
    formatted <- rep(NA_character_, nrow(d))
    formatted[good] <- sprintf("%s-%02d", y[good], as.integer(m[good]))
    parsed <- .month_dates(formatted)
  } else {
    .fail("Supply a date column or both year and month columns. Blank dates are allowed; absent date columns are not.")
  }
  raw_lon <- as.character(d[[lon]]); raw_lat <- as.character(d[[lat]])
  coordinate <- function(x) {
    if (decimal_comma) x <- gsub(",", ".", x, fixed = TRUE)
    suppressWarnings(as.numeric(x))
  }
  longitude <- coordinate(raw_lon)
  latitude <- coordinate(raw_lat)
  ids <- trimws(as.character(d[[id]]))
  status <- rep("pending", nrow(d))
  status[is.na(ids) | !nzchar(ids)] <- "excluded_missing_id"
  bad_coord <- !is.finite(longitude) | !is.finite(latitude) |
    longitude < -180 | longitude > 180 | latitude < -90 | latitude > 90
  status[status == "pending" & bad_coord] <- "excluded_invalid_coordinates"
  status[status == "pending" & !missing & is.na(parsed)] <- "excluded_invalid_date"
  data.frame(row = seq_len(nrow(d)), id = ids, longitude = longitude,
    latitude = latitude, original_longitude = raw_lon, original_latitude = raw_lat,
    original_date = original,
    occurrence_month = format(parsed, "%Y-%m"), missing_date = missing,
    status = status, stringsAsFactors = FALSE)
}

.resolve_dates <- function(d, shared, outside_period, missing_date) {
  d$used_month <- NA_character_
  for (i in which(d$status == "pending")) {
    if (d$missing_date[i]) {
      d$status[i] <- if (missing_date == "exclude") "excluded_missing_date" else "period_mean"
    } else if (d$occurrence_month[i] %in% shared) {
      d$used_month[i] <- d$occurrence_month[i]; d$status[i] <- "matched"
    } else if (outside_period == "exclude") {
      d$status[i] <- "excluded_unavailable_month"
    } else {
      candidates <- shared[substr(shared, 6, 7) == substr(d$occurrence_month[i], 6, 7)]
      if (!length(candidates)) {
        d$status[i] <- "excluded_no_same_month"
      } else {
        delta <- abs(as.integer(substr(candidates, 1, 4)) - as.integer(substr(d$occurrence_month[i], 1, 4)))
        d$used_month[i] <- candidates[which.min(delta)]
        d$status[i] <- "nearest_same_month"
      }
    }
  }
  d
}
