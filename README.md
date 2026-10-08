# OccEnv

Turn monthly environmental stacks and dated occurrence CSVs into one environmental stack per species. Different raster grids produce separate layers.

## Install

Download or clone this repository, then install from its local folder:

```r
install.packages("terra")
install.packages("/path/to/occenv", repos = NULL, type = "source")
```

## Example

Replace the paths and column names below. Use any number of environmental variables or species files.

```r
library(occenv)

rasters <- list(temperature = "temperature.tif", moisture = "moisture.tif")
occurrences <- list(oak = "oak.csv", frog = "frog.csv")

# Left = package field; right = column name in that CSV.
columns <- list(
  oak = list(id = "RecordID", longitude = "Long", latitude = "Lat",
             year = "Year", month = "Month"),
  frog = list(id = "sample_id", longitude = "lon", latitude = "lat",
              date = "date")
)

result <- build_species_layers(
  rasters, occurrences, columns = columns,
  occurrence_rule = "mean",     # Or "latest"
  background = "full_period",  # Or "latest_year", "latest_month"
  outside_period = "exclude",  # Or "nearest_same_month"
  missing_date = "exclude",    # Or "period_mean"
  output_dir = "outputs"
)

plot(result$layers$oak[["temperature"]])
```

Coordinates must be WGS84 longitude/latitude in decimal degrees. Dates use `YYYY-MM`, `YYYY-MM-DD`, or separate year/month columns. Raster layer dates are read automatically; the package asks for a mapping if they are missing.

## Optional ggplot

```r
library(ggplot2)  # Install separately if needed.
r <- result$layers$oak[["temperature"]]
d <- as.data.frame(r, xy = TRUE, na.rm = TRUE)
names(d) <- c("x", "y", "value")
ggplot(d, aes(x, y, fill = value)) +
  geom_raster() + coord_equal() + scale_fill_viridis_c() + theme_minimal()
```

## Outputs

- One stack per input group, or separate layers when grids differ.
- `records.csv`: extracted values, dates used, and exclusions, repeated by variable.
- `environment.csv` and `settings.csv`: layer dates and processing choices.

Inputs stay unchanged. Missing raster values remain missing by default; set `na_rm = TRUE` to average available values. Full option details: `?build_species_layers`.
