# List or read topographic layers

Original archives are cached outside the project. The first call
downloads the selected archive (potentially large for detailed series).
Only the requested layer is loaded as an sf object. Original names,
attributes, dates, identifiers and coordinate reference system are
preserved as read by GDAL. Layer indexes and loaded objects are reused
in this R session, with a shared approximate 128 MiB LRU limit. Set
`options(kartdata.memory_cache_size = 0)` to disable all memory caching,
or supply another limit in bytes. Objects larger than the limit are
returned without being retained. Updating or clearing the disk cache
invalidates its memory entries. Progress is shown by default in
interactive R sessions. Set `options(kartdata.progress = FALSE)` to
silence it, or TRUE to enable it in scripts. Downloads and FGDB layer
discovery show progress indicators; unpacking and GDAL reads show stage
messages without estimated percentages. Memory cache hits produce no
read or layer discovery messages.

## Usage

``` r
n_layers(
  series = "N1000",
  area = "0000",
  epsg = 25833,
  format = c("auto", "FGDB", "GML"),
  refresh = c("never", "check", "force"),
  cache_dir = tools::R_user_dir("kartdata", "cache")
)

n_get(
  layer,
  series = "N1000",
  area = "0000",
  epsg = 25833,
  format = c("auto", "FGDB", "GML"),
  refresh = c("never", "check", "force"),
  cache_dir = tools::R_user_dir("kartdata", "cache"),
  memory_cache = TRUE
)
```

## Arguments

- series:

  N-series, such as `"N1000"` or `1000`.

- area:

  Character area code; `"0000"` selects nationwide data.

- epsg:

  EPSG code of the published file, default 25833. This selects a
  download; it does not reproject data.

- format:

  `"auto"` prefers FGDB when available and locally readable, otherwise
  GML. Can also be `"FGDB"` or `"GML"`. FGDB object types are exposed as
  logical layers using GDAL SQL on the original `objtype` field;
  original physical layer names are also available.

- refresh:

  `"never"` reuses cache without network access (default), `"check"`
  checks ATOM URL and updated value, `"force"` downloads again. A
  missing cache is downloaded in every mode.

- cache_dir:

  Cache root; defaults to `tools::R_user_dir("kartdata", "cache")`.

- layer:

  Exact layer name returned by `n_layers()`.

- memory_cache:

  If TRUE (default), reuse and retain the layer and its index in session
  memory. FALSE bypasses both for this call.

## Value

`n_layers()` returns a character vector; `n_get()` an `sf` object.

## Examples

``` r
if (FALSE) { # \dontrun{
n_layers("N1000")
veg <- n_get("Veglenke", "N1000")
plot(sf::st_geometry(veg))
} # }
```
