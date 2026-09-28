test_that("live Geonorge discovery works for every registered series", {
  skip_if(Sys.getenv("KARTDATA_INTEGRATION") != "true", "opt-in metadata integration test")
  for (series in n_products()$series) {
    result <- discover(selection(series, "0000", 25833, "auto"))
    expect_identical(result$series, series)
    expect_identical(result$format, "FGDB")
    expect_match(result$url, "[.]zip$")
  }
})

test_that("live N1000 returns an sf road layer from user cache", {
  skip_if(Sys.getenv("KARTDATA_DOWNLOAD_TEST") != "true", "opt-in map download")
  expect_true("Veglenke" %in% n_layers("N1000", refresh = "check"))
  veg <- n_get("Veglenke", 1000)
  expect_s3_class(veg, "sf")
  expect_gt(nrow(veg), 0)
})
