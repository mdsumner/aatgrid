# Tests for the zone table, longitude-to-zone arithmetic, zone boundary
# lines, and lonlat_to_utm.

test_that("define_utm_zones is a complete, consistent southern table", {
  zones <- define_utm_zones()
  expect_identical(nrow(zones), 60L)
  expect_identical(zones$zone_number, 1:60)
  expect_true(all(zones$hemisphere == "S"))
  ## ids are zero-padded and unique
  expect_identical(zones$zone_id[1], "01S")
  expect_identical(zones$zone_id[43], "43S")
  expect_identical(zones$zone_id[60], "60S")
  expect_true(all(nchar(zones$zone_id) == 3L))
  expect_identical(anyDuplicated(zones$zone_id), 0L)
  ## epsg strings, never bare numbers
  expect_identical(zones$epsg[1], "EPSG:32701")
  expect_identical(zones$epsg[43], "EPSG:32743")
  expect_true(all(grepl("^EPSG:327[0-9]{2}$", zones$epsg)))
  ## central meridians
  expect_identical(zones$central_meridian[1], -177)
  expect_identical(zones$central_meridian[43], 75)
  expect_identical(zones$central_meridian[60], 177)
  ## origin columns mirror GRID_ORIGIN exactly
  expect_true(all(zones$origin_x == GRID_ORIGIN[["x"]]))
  expect_true(all(zones$origin_y == GRID_ORIGIN[["y"]]))
})

test_that("lon_to_zone_id matches the zone table", {
  zones <- define_utm_zones()
  ## the central meridian of every zone maps back to that zone
  expect_identical(lon_to_zone_id(zones$central_meridian), zones$zone_id)
  ## western edges belong to the zone they open; eastern edge of 60 is 60
  expect_identical(lon_to_zone_id(-180), "01S")
  expect_identical(lon_to_zone_id(72), "43S")
  expect_identical(lon_to_zone_id(71.999), "42S")
  expect_identical(lon_to_zone_id(180), "60S")
  ## AAT islands
  expect_identical(lon_to_zone_id(73.5), "43S")    # Heard
  expect_identical(lon_to_zone_id(158.9), "57S")   # Macquarie
  expect_error(lon_to_zone_id(181), "-180, 180")
})

test_that("tiles_for_extent2 default zone works below zone 10 (padding)", {
  ## Regression: the centroid zone was built with paste0(n, "S") -> "1S",
  ## which is not a zone_id in the table.
  t1 <- tiles_for_extent2(c(-177, -176, -60, -59), 60)
  expect_identical(unique(t1$zone_id), "01S")
  expect_true(all(startsWith(t1$tile_id, "01S_R0060_")))
  ## explicit zone override is honoured
  t2 <- tiles_for_extent2(c(72.6, 73.7, -53.2, -52.9), 60, zone = "42S")
  expect_identical(unique(t2$zone_id), "42S")
  expect_false(any(t2$tile_id %in% tiles_for_extent2(c(72.6, 73.7, -53.2, -52.9), 60)$tile_id))
  expect_error(tiles_for_extent2(c(72.6, 73.7, -53.2, -52.9), 60, zone = "99S"),
               "zone not in table")
})

test_that("generate_utm_zone_boundaries draws one meridian per zone", {
  b <- generate_utm_zone_boundaries(42:58, lat_range = c(-70, -50), n_points = 11)
  expect_s4_class(b, "SpatVector")
  expect_identical(terra::geomtype(b), "lines")
  expect_equal(nrow(b), 17)
  expect_equal(terra::crs(b, describe = TRUE)$code, "4326")
  v <- terra::values(b)
  expect_identical(v$zone_west, 42:58)
  expect_equal(v$zone_east, 43:59)
  expect_equal(v$longitude, 66 + 6 * (0:16))
  expect_identical(v$label[1], "42/43")
  ## geometry: each line is vertical at its longitude over the lat range
  g <- terra::geom(b)
  expect_equal(range(g[g[, "geom"] == 1, "x"]), c(66, 66))
  expect_equal(range(g[g[, "geom"] == 1, "y"]), c(-70, -50))
  expect_identical(sum(g[, "geom"] == 1), 11L)
})

test_that("generate_utm_zone_boundaries defaults to the full table and validates", {
  b <- generate_utm_zone_boundaries()
  expect_equal(nrow(b), 60)
  ## zone 60's eastern neighbour wraps to 1
  expect_identical(terra::values(b)$zone_east[60], 1)
  expect_error(generate_utm_zone_boundaries(0), "1:60")
  expect_error(generate_utm_zone_boundaries(43, n_points = 1), "at least 2")
})

test_that("lonlat_to_utm projects into the named zone and rejects unknown zones", {
  xy <- lonlat_to_utm(75, -53, "43S")   # on the 43S central meridian
  expect_equal(xy$x, 500000, tolerance = 1e-6)
  expect_lt(xy$y, 1e7)
  ## vectorised
  xy2 <- lonlat_to_utm(c(73, 74), c(-53, -53), "43S")
  expect_identical(nrow(xy2), 2L)
  expect_lt(xy2$x[1], xy2$x[2])
  expect_error(lonlat_to_utm(75, -53, "43X"), "unknown zone")
  ## round trip through terra against PROJ-based reproj agrees
  rp <- reproj::reproj_xy(cbind(75, -53), "EPSG:32743", source = "EPSG:4326")
  expect_equal(unname(unlist(xy)), unname(as.numeric(rp[1, 1:2])), tolerance = 1e-3)
})
