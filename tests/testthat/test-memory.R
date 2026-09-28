test_that("repeated reads reuse index and sf but respect bypass, updates and clearing", {
  state <- new.env(parent = emptyenv())
  state$entries <- list()
  local_mocked_bindings(.read_cache = state)
  archive <- small_archive()
  cache <- tempfile("kartdata-memory-")
  on.exit(unlink(c(cache, archive), recursive = TRUE))
  version <- "v1"
  reads <- indexes <- 0L
  original_read <- read_layer
  original_index <- layer_index
  local_mocked_bindings(
    discover = function(sel) c(sel[c("series", "area", "epsg")], list(format = "GML", feed = service_feed,
      url = "https://nedlasting.geonorge.no/fixture.zip", updated = version)),
    http_get = function(url, path) file.copy(archive, path),
    read_layer = function(...) { reads <<- reads + 1L; original_read(...) },
    layer_index = function(...) { indexes <<- indexes + 1L; original_index(...) })
  get <- function(...) n_get("Veglenke", format = "GML", cache_dir = cache, ...)
  first <- get()
  expect_identical(get(), first)
  n_layers(format = "GML", cache_dir = cache)
  expect_equal(c(reads, indexes), c(1, 1))
  expect_equal(n_cache_info(cache_dir = cache)$cached_layers, 1)
  expect_gt(n_cache_info(cache_dir = cache)$memory_bytes, 0)
  # R's copy-on-modify must keep caller edits out of the retained value.
  first$kommunenummer <- "9999"
  expect_false(any(get()$kommunenummer == "9999"))
  expect_s3_class(get(memory_cache = FALSE), "sf")
  expect_equal(c(reads, indexes), c(2, 2))
  get(refresh = "check")
  expect_equal(reads, 2)
  version <- "v2"
  get(refresh = "check")
  expect_equal(c(reads, indexes), c(3, 3))
  # Even identical source bytes must invalidate on force.
  get(refresh = "force")
  expect_equal(c(reads, indexes), c(4, 4))
  n_cache_clear("N50", cache, memory_only = TRUE)
  expect_equal(n_cache_info(cache_dir = cache)$cached_layers, 1)
  n_cache_clear("N1000", cache, memory_only = TRUE)
  expect_true(n_cache_info(cache_dir = cache)$valid)
  expect_equal(n_cache_info(cache_dir = cache)$memory_bytes, 0)
  get()
  expect_equal(reads, 5)
  n_cache_clear(cache_dir = cache)
  expect_length(state$entries, 0)
})

test_that("LRU has a bounded shared budget and skips oversized objects", {
  state <- new.env(parent = emptyenv())
  state$entries <- list()
  local_mocked_bindings(.read_cache = state, memory_version = function(...) "v1")
  value <- rep(1, 10)
  size <- as.numeric(object.size(value))
  old <- options(kartdata.memory_cache_size = 2 * size)
  on.exit(options(old), add = TRUE)
  a <- list(path = tempdir())
  compute <- function() value
  memory_fetch(a, "layer", "a", compute)
  memory_fetch(a, "layer", "b", compute)
  memory_fetch(a, "layer", "a", function() stop("must hit"))
  memory_fetch(a, "layer", "c", compute)
  expect_identical(vapply(state$entries, function(x) x$name, character(1)), c("a", "c"))
  expect_lte(sum(vapply(state$entries, function(x) x$bytes, numeric(1))), 2 * size)
  memory_fetch(a, "layer", "huge", function() rep(1, 1000))
  expect_length(state$entries, 2)
  options(kartdata.memory_cache_size = 0)
  expect_identical(memory_fetch(a, "layer", "a", function() "uncached"), "uncached")
  expect_length(state$entries, 0)
})

test_that("changed version and separate cache paths cannot return stale objects", {
  state <- new.env(parent = emptyenv())
  state$entries <- list()
  version <- "v1"
  local_mocked_bindings(.read_cache = state, memory_version = function(...) version)
  a <- list(path = file.path(tempdir(), "one"))
  b <- list(path = file.path(tempdir(), "two"))
  memory_fetch(a, "layer", "Veglenke", function() 1)
  expect_equal(memory_fetch(b, "layer", "Veglenke", function() 2), 2)
  version <- "v2"
  expect_equal(memory_fetch(a, "layer", "Veglenke", function() 3), 3)
  expect_length(state$entries, 2)
  old <- options(kartdata.memory_cache_size = NA_real_)
  on.exit(options(old), add = TRUE)
  expect_error(memory_trim(), "non-negative")
  expect_error(n_get("Veglenke", memory_cache = NA), "memory_cache")
  expect_error(n_cache_clear(memory_only = NA), "memory_only")
})
