# Inspect or clear the local map cache

Progress messages for network checks and checksum verification follow
`options(kartdata.progress)`, defaulting to
[`interactive()`](https://rdrr.io/r/base/interactive.html). Clearing
disk cache also removes area lookup tables for the selected series.
These small metadata tables are not listed by `n_cache_info()`.

## Usage

``` r
n_cache_info(
  series = NULL,
  cache_dir = tools::R_user_dir("kartdata", "cache"),
  check = FALSE,
  verify = FALSE
)

n_cache_clear(
  series = NULL,
  cache_dir = tools::R_user_dir("kartdata", "cache"),
  memory_only = FALSE
)
```

## Arguments

- series:

  Optional series filter; `NULL` selects all series.

- cache_dir:

  Cache root; defaults to the standard R user cache.

- check:

  If TRUE, contact Geonorge to compare each cached version with the
  current ATOM entry. Does not download map data. Network failures
  error.

- verify:

  If TRUE, also verify the original ZIP checksum. Otherwise check the
  presence and sizes of the ZIP and extracted files.

- memory_only:

  If TRUE, clear only the selected session memory entries; retain
  downloaded files. Default FALSE clears both memory and disk.

## Value

`n_cache_info()` returns a data frame with paths, version metadata,
sizes, integrity status and (when checked) whether updates are
available. `memory_bytes` counts approximate retained object sizes
(including the layer index); `cached_layers` counts retained sf layers
in this R session. `n_cache_clear()` invisibly returns the removed cache
paths.

## Examples

``` r
n_cache_info()
#>  [1] series           area             epsg             format          
#>  [5] updated          downloaded       bytes            valid           
#>  [9] update_available path             memory_bytes     cached_layers   
#> <0 rows> (or 0-length row.names)
if (FALSE) { # \dontrun{
n_cache_info(check = TRUE)
n_cache_clear("N1000")
} # }
```
