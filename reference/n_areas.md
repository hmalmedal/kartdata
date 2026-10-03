# Find available download areas

Lists published areas and coordinate systems using Geonorge ATOM
metadata. No map archives are downloaded. A small UTF-8 table is cached
locally for offline name lookup. Use `refresh = TRUE` to update it after
area changes.

## Usage

``` r
n_areas(
  series = "N1000",
  refresh = FALSE,
  cache_dir = tools::R_user_dir("kartdata", "cache")
)
```

## Arguments

- series:

  N-series, such as `"N1000"` or `1000`.

- refresh:

  Logical; fetch current metadata instead of reusing the table.

- cache_dir:

  Cache root, as in
  [`n_get()`](https://hmalmedal.github.io/kartdata/reference/n_layers.md).

## Value

A data frame with `area` (character code), `name`, `epsg` and `format`.
Each row describes a published combination, independent of local GDAL
support. The table is not a complete municipality register.

## Examples

``` r
if (FALSE) { # \dontrun{
areas <- n_areas("N1000")
subset(areas, name == "Oslo")
veg <- n_get("Veglenke", "N1000", area = "Oslo")
} # }
```
