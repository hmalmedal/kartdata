# Separate opt-in: these small downloads must not enable the national N1000 test.
for (series in c("N50", "N100", "N250")) {
  for (format in c("FGDB", "GML")) {
    test_that(paste("live Utsira layers and cache work for", series, format), {
      skip_if(Sys.getenv("KARTDATA_UTSIRA_TEST") != "true", "opt-in Utsira download")
      skip_if_not(format %in% readable_formats(), paste("Missing GDAL driver for", format))

      cache <- tempfile("kartdata-utsira-")
      on.exit(unlink(cache, recursive = TRUE), add = TRUE)
      state <- new.env(parent = emptyenv())
      state$entries <- list()
      offline <- FALSE
      reads <- 0L
      original_http <- http_get
      original_read <- read_layer
      local_mocked_bindings(
        .read_cache = state,
        http_get = function(...) {
          if (offline) stop("Unexpected network request during cache reuse")
          original_http(...)
        },
        read_layer = function(...) {
          reads <<- reads + 1L
          original_read(...)
        }
      )
      old <- options(kartdata.memory_cache_size = 128 * 1024^2,
                     kartdata.progress = FALSE)
      on.exit(options(old), add = TRUE)

      get <- function(layer, ...) n_get(layer, series, area = "1151",
                                        epsg = 25833, format = format,
                                        cache_dir = cache, ...)
      layers <- n_layers(series, area = "1151", epsg = 25833,
                         format = format, cache_dir = cache)
      expect_true(all(c("Veglenke", "Kommune", "Bygning") %in% layers))
      cached <- ensure_cache(selection(series, "1151", 25833, format), "never", cache)
      index <- cached_layer_index(cached)
      logical <- if (format == "FGDB") index[!is.na(index$filter), ] else index
      ambiguous <- unique(logical$layer[duplicated(logical$layer)])
      # Object types can span point and polygon layers (N50 Bygning, for example).
      # Discover these cases instead of hardcoding physical names or row counts.
      for (layer in ambiguous) {
        expect_error(get(layer), "Layer name is ambiguous.*Choose a physical layer")
      }
      targets <- unique(c(setdiff(logical$layer, ambiguous),
                          logical$physical[logical$layer %in% ambiguous]))
      offline <- TRUE
      geometry_types <- character()
      for (layer in targets) {
        x <- get(layer)
        expect_s3_class(x, "sf")
        expect_true(nrow(x) > 0, info = layer)
        expect_equal(sf::st_crs(x)$epsg, 25833, info = layer)
        expect_false(any(sf::st_is_empty(x)), info = layer)
        geometry_types <- union(geometry_types, as.character(sf::st_geometry_type(x)))
      }
      expect_true(any(geometry_types %in% c("POINT", "MULTIPOINT")))
      expect_true(any(geometry_types %in% c("LINESTRING", "MULTILINESTRING")))
      expect_true(any(geometry_types %in% c("POLYGON", "MULTIPOLYGON")))

      first <- get("Veglenke")
      before <- reads
      expect_identical(get("Veglenke"), first)
      expect_equal(reads, before) # An equal result alone would not prove a memory hit.
      info <- n_cache_info(cache_dir = cache, verify = TRUE)
      expect_true(all(info$valid))
      expect_gt(sum(info$cached_layers), 0)
      n_cache_clear(cache_dir = cache, memory_only = TRUE)
      expect_equal(sum(n_cache_info(cache_dir = cache)$memory_bytes), 0)
      before <- reads
      expect_identical(get("Veglenke"), first)
      expect_equal(reads, before + 1L) # Disk reread must succeed with HTTP blocked.
      expect_identical(n_cache_info(cache_dir = cache)$downloaded, info$downloaded)
    })
  }
}
