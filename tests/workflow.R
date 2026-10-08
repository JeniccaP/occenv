library(occenv)
library(terra)

equal <- function(x, y) stopifnot(isTRUE(all.equal(x, y, check.attributes = FALSE)))
fails <- function(expr, pattern) {
  error <- tryCatch({ force(expr); NULL }, error = function(e) conditionMessage(e))
  stopifnot(!is.null(error), grepl(pattern, error))
}
fixture <- function(ncols = 2L, crs = "EPSG:4326") {
  r <- rast(nrows = 2, ncols = ncols, nlyrs = 24,
    xmin = 0, xmax = 2, ymin = 0, ymax = 2, crs = crs)
  values(r) <- matrix(rep(seq_len(24), each = ncell(r)), ncol = 24)
  time(r) <- seq(as.Date("2000-01-01"), by = "month", length.out = 24)
  r
}
points <- function(months = c(1, 7, 7), years = rep(2000, length(months))) {
  data.frame(id = seq_along(months), longitude = 0.5, latitude = 1.5,
    year = years, month = months)
}
run <- function(r = list(temperature = fixture()), p = list(species = points()), ...)
  build_species_layers(r, p, ...)

# Latest, duplicate-free means, background windows, and source immutability.
r <- fixture()
latest <- run(list(temperature = r), occurrence_rule = "latest")
equal(values(latest$layers$species)[1], 7)
equal(values(latest$layers$species)[2], 12.5)
stopifnot(sum(latest$records$selected) == 1)
average <- run(list(temperature = r), occurrence_rule = "mean")
equal(values(average$layers$species)[1], 4)
equal(values(r)[1, ], 1:24)
equal(values(latest$layers$species)[1], 7)
equal(values(run(background = "latest_year")$layers$species)[2], 18.5)
equal(values(run(background = "latest_month")$layers$species)[2], 24)

# Shared dates govern all variables, including fallbacks and backgrounds.
r2 <- r[[7:24]] * 10
time(r2) <- time(r)[7:24]
env <- prepare_environment(list(temperature = r, rain = r2))
stopifnot(env$same_grid, length(env$shared_dates) == 18)
old <- points(6, 1920)
substitute <- run(list(temperature = r, rain = r2), list(species = old),
  outside_period = "nearest_same_month")
stopifnot(all(substitute$records$used_month == "2001-06"))
equal(values(substitute$layers$species)[1, ], c(18, 180))
excluded <- run(p = list(species = old))
stopifnot(all(excluded$records$status == "excluded_unavailable_month"))
future <- run(p = list(species = points(6, 2020)), outside_period = "nearest_same_month")
stopifnot(future$records$used_month == "2001-06")
undated <- run(p = list(species = points(NA, NA)), missing_date = "period_mean")
equal(values(undated$layers$species)[1], 12.5)
stopifnot(undated$records$status == "period_mean")
mixed <- run(p = list(species = points(c(1, NA), c(2000, NA))),
  occurrence_rule = "mean", missing_date = "period_mean")
equal(values(mixed$layers$species)[1], (1 + 12.5) / 2)
mixed_latest <- run(p = list(species = points(c(1, NA), c(2000, NA))),
  missing_date = "period_mean")
equal(values(mixed_latest$layers$species)[1], 1)

# No same month, internal gaps, and deterministic same-month year ties.
sparse <- r[[c(1, 13)]]
no_month <- run(list(temperature = sparse), list(species = points(6, 1990)),
  outside_period = "nearest_same_month")
stopifnot(no_month$records$status == "excluded_no_same_month")
tie <- r[[c(1, 13)]]
time(tie) <- as.Date(c("2000-01-01", "2002-01-01"))
tied <- run(list(temperature = tie), list(species = points(1, 2001)),
  outside_period = "nearest_same_month")
stopifnot(tied$records$used_month == "2000-01")
fails(run(list(temperature = sparse), background = "latest_year"), "complete calendar year")

# Date metadata, layer names, explicit overrides, malformed and incomplete dates.
named <- r; time(named) <- NULL
names(named) <- paste0("temp_", format(time(r), "%Y_%m"))
stopifnot(all(prepare_environment(list(temp = named))$dates$temp == format(time(r), "%Y-%m")))
names(named) <- paste0("layer", 1:24)
fails(prepare_environment(list(temp = named)), "Cannot identify")
explicit <- prepare_environment(list(temp = named), dates = list(temp = time(r)))
stopifnot(all(explicit$manifest$date_source == "supplied"))
fails(prepare_environment(list(temp = named), dates = list(temp = rep("2000-01", 24))), "Duplicate")
bad <- data.frame(id = 1:3, longitude = 0.5, latitude = 1.5,
  date = c("2000-02-30", "2000-01-15", ""))
bad_result <- run(p = list(species = bad), missing_date = "period_mean")
stopifnot(identical(bad_result$records$status, c("excluded_invalid_date", "matched", "period_mean")))
fails(run(p = list(species = data.frame(id = 1, longitude = .5, latitude = 1.5))), "date column")

# Coordinate validation, outside extent and missing IDs do not alter sources.
invalid <- points(c(1, 1, 1, 1))
invalid$longitude <- c(181, NA, -10, .5)
invalid$id[4] <- NA
bad_result <- run(p = list(species = invalid))
stopifnot(identical(bad_result$records$status, c("excluded_invalid_coordinates",
  "excluded_invalid_coordinates", "excluded_outside_extent", "excluded_missing_id")))

# Different resolution or projection returns separate native-grid layers.
native <- run(list(temp = r, rain = fixture(4)))
stopifnot(is.list(native$layers$species), !native$settings$same_grid,
  ncol(native$layers$species$temp) == 2, ncol(native$layers$species$rain) == 4)
projected <- project(r, "EPSG:3857")
time(projected) <- time(r)
different_crs <- run(list(temp = r, rain = projected))
stopifnot(!different_crs$settings$same_grid)
equal(different_crs$records$value[different_crs$records$selected], c(7, 7))

# Missing values are not silently replaced by background or available months.
missing <- r
v <- values(missing); v[1, 1] <- NA; v[2, ] <- NA; values(missing) <- v
strict <- run(list(temp = missing), list(species = points(1)))
stopifnot(is.na(values(strict$layers$species)[1]), is.na(values(strict$layers$species)[2]))
stopifnot(strict$records$value_missing)
available <- run(list(temp = missing), list(species = points(c(1, 7))),
  occurrence_rule = "mean", na_rm = TRUE)
equal(values(available$layers$species)[1], 7)
stopifnot(is.na(values(available$layers$species)[2]))

# Multiple species, CSV schema mappings, ID priority, file-backed outputs.
folder <- tempfile("occenv-test-"); dir.create(folder)
csv <- file.path(folder, "records.csv")
tab <- data.frame(GBIF_ID = c("001", "002"), Species = "example", Long = .5,
  Lat = 1.5, Year = 2000, Month = c(1, 7), Event_date = "ambiguous date")
write.csv(tab, csv, row.names = FALSE)
multi <- run(p = list(a = csv, b = points(1)), columns = list(
  a = list(year = "Year", month = "Month"), b = list()))
stopifnot(identical(names(multi$layers), c("a", "b")), multi$records$id[1] == "001")
equal(values(multi$layers$a)[1], 7)
equal(values(multi$layers$b)[1], 1)
elsewhere <- points(1); elsewhere$longitude <- 1.5
independent <- run(p = list(a = points(7), b = elsewhere))
equal(values(independent$layers$b)[1], 12.5)
semi <- file.path(folder, "semicolon.csv")
write.table(tab, semi, sep = ";", row.names = FALSE)
semi_result <- run(p = list(species = semi), columns = list(year = "Year", month = "Month"))
equal(values(semi_result$layers$species)[1], 7)
comma_tab <- tab
comma_tab$Long <- "0,5"; comma_tab$Lat <- "1,5"
write.table(comma_tab, semi, sep = ";", row.names = FALSE)
comma_result <- run(p = list(species = semi), columns = list(year = "Year", month = "Month"))
equal(values(comma_result$layers$species)[1], 7)
stopifnot(comma_result$records$original_longitude[1] == "0,5")
out <- file.path(folder, "out")
written <- run(output_dir = out)
stopifnot(setequal(list.files(out), c("species.tif", "records.csv", "environment.csv", "settings.csv")))
equal(values(rast(file.path(out, "species.tif"))), values(written$layers$species))
fails(run(output_dir = out), "already exist")
separate <- file.path(folder, "separate")
invisible(run(list(temp = r, rain = fixture(4)), output_dir = separate))
stopifnot(all(c("species__temp.tif", "species__rain.tif") %in% list.files(separate)))
unlink(folder, recursive = TRUE)
cat("All occenv workflow tests passed.\n")
