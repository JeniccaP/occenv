# OccEnv

Build environmental rasters for species from dated occurrence records.

Give the package one monthly stack per environmental variable and one CSV per species or group. It selects environmental values at occurrence cells, fills other valid cells using your background rule, and returns one stack per species when grids match. Different grids produce separate layers without resampling.

## Install

```r
install.packages("terra")
# Until the repository is public, install from a local checkout:
install.packages("/path/to/occenv", repos = NULL, type = "source")
```

R 4.1 or later is required. The only package dependency is `terra`.

## Quick start

Replace these example paths and column names with your own. Supply any number of environmental variables and occurrence files.

```r
library(occenv)

rasters <- list(
  soil_temperature = "soil_temperature_monthly.tif",
  soil_moisture = "soil_moisture_monthly.tif"
)
occurrences <- list(oak = "oak.csv", frog = "frog.csv")

# Left: package field. Right: the actual column name in that CSV.
columns <- list(
  oak = list(id = "RecordCode", longitude = "East", latitude = "North",
             year = "Year", month = "Month"),
  frog = list(id = "sample_id", longitude = "lon", latitude = "lat",
              date = "observed_on")
)

result <- build_species_layers(
  rasters = rasters, occurrences = occurrences, columns = columns,
  occurrence_rule = "mean",
  background = "full_period",
  outside_period = "exclude",
  missing_date = "exclude",
  output_dir = "outputs"
)

# View one output layer; works with matching or different raster grids.
plot(result$layers$oak[["soil_temperature"]])
# Count records once, rather than once per environmental variable.
audit <- unique(result$records[c("species_file", "row", "status")])
with(audit, table(species_file, status))
```

Coordinates must be WGS84 longitude/latitude in decimal degrees, regardless of column names. The example date column uses `YYYY-MM` or `YYYY-MM-DD`; year/month columns are an alternative. Raster layers need readable month-year dates or an explicit mapping, described below.

Each named occurrence entry produces one output group. Split a CSV containing multiple species first if separate species outputs are wanted.

Optional ggplot preview (install `ggplot2` separately):

```r
library(ggplot2)
r <- result$layers$oak[["soil_temperature"]]
pixels <- as.data.frame(r, xy = TRUE, na.rm = TRUE)
names(pixels) <- c("x", "y", "value")
ggplot(pixels, aes(x, y, fill = value)) +
  geom_raster() + coord_equal() + scale_fill_viridis_c() +
  labs(title = "Oak: soil temperature", fill = "Source units") + theme_minimal()
```

## Options

| Argument | Choices |
|---|---|
| `occurrence_rule` | `"latest"` (default): latest original occurrence month per cell; `"mean"`: equal mean of distinct matched months |
| `background` | `"full_period"` (default): all shared months; `"latest_year"`: latest complete shared calendar year; `"latest_month"`: latest shared month |
| `outside_period` | `"exclude"` (default); `"nearest_same_month"`: nearest shared year with the same month |
| `missing_date` | `"exclude"` (default); `"period_mean"`: mean over all shared months |
| `na_rm` | `FALSE` (default): missing values remain missing; `TRUE`: means use available values |

All variables use the same shared dates, including fallback dates. June 1920 can use the earliest shared June if selected explicitly; this is a substitute, not a reconstruction of 1920. The nearest-month rule also covers dates after coverage and internal gaps. Ties use the earlier year. If no matching calendar month exists, the record is excluded.

Repeated records in a cell and month do not increase that month's weight. With `"latest"`, dated records take priority over undated records. With `"mean"`, retained undated records contribute the full-period mean once per cell, alongside distinct dated months. These rules are recorded in the audit table.

## Input checks

Occurrences need an ID, WGS84 longitude and latitude in decimal degrees, and either a date column or year and month columns. Dates use `YYYY-MM` or `YYYY-MM-DD`; blank dates are handled by `missing_date`. Malformed dates, missing IDs and out-of-range coordinates are excluded and reported. Plausible coordinate ranges do not establish that a location is correct. Source row numbers distinguish repeated IDs.

CSV paths use UTF-8 and comma separators, or semicolons when the header contains semicolons and no commas. Semicolon files accept decimal commas, following R's `read.csv2` convention. Original coordinate text is kept in the audit report. For other encodings or formats, read the table yourself with the correct encoding and pass a data frame. Import warnings stop processing to prevent silently truncated tables. If both a date and year/month columns exist, explicitly map the columns you want to use.

Raster inputs must be continuous numeric monthly layers with an explicit coordinate reference system. Dates are read from date metadata or unambiguous names such as `temperature_2000_06`. If dates are unclear, provide them in layer order:

```r
env <- prepare_environment(
  rasters,
  dates = list(soil_temperature = seq(as.Date("1980-01-01"), by = "month", length.out = 500))
)
env$same_grid
head(env$manifest)
```

Use `rasters = env` in the main function. Supply mappings for every variable whose dates cannot be read. Daily, annual, categorical and submonthly input are outside this version's scope. Units remain as supplied; the package does not infer or convert them.

Matching projection, resolution, alignment and extent produce a combined stack. Different grids remain separate; points are transformed to each grid. There is no automatic raster alignment, spatial interpolation, coordinate correction or unit conversion.

## Outputs

- One GeoTIFF stack per input species/group when grids match, or one single-layer GeoTIFF per species/group and variable when they differ.
- `records.csv`: original rows, coordinates, dates used, exclusions, values and whether each record contributed to an occurrence cell.
- `environment.csv`: source layer names, month-year dates and shared coverage.
- `settings.csv`: options, shared dates and background dates.

Background fills every valid raster cell outside eligible occurrence cells. Supply rasters already masked to your study area if needed. An occurrence cell with a missing environmental value stays missing; it is not silently replaced by background. There is no sampling of background points.

Outputs mix occurrence-specific dates with background summaries. They are not measurements from one common historical date. Check whether this design suits your modeling question before using them. With `na_rm = TRUE`, cells can average different subsets of the requested period where data are missing.

Input files stay unchanged. Existing outputs are protected unless `overwrite = TRUE`. Large raster summaries use `terra`'s block processing and temporary disk space. No source occurrence data or environmental rasters are stored in this repository.

## Development

```sh
R CMD build .
R CMD check --no-manual occenv_0.1.0.tar.gz
```

Tests use small generated rasters and base R. GitHub Actions runs the package check on Linux. License: GPL-3.
