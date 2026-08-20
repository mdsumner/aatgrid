# Tests for aatgrid core grid arithmetic.
# Invariant tests first, then the Heard/McDonald integration case with
# authoritative expectations derived from the AADC himi_coastline_py extent
# (wk_bbox: 72.57784 -53.19276 73.70948 -52.91414, EPSG:4326).
#
# The grid is parametric: an origin (GRID_ORIGIN), a fixed pixel count per
# tile (PIXELS_PER_TILE = 600), and a resolution. Tile size is always
# derived: tile_size(res) = 600 * res. "L1"/"L2" are just named instances
# at 60 m / 10 m, kept as convenience aliases (see LEVEL_RESOLUTIONS) and
# as a parse-time alias for old ids -- they are not independent parameters.

test_that("grid spec constants are self-consistent", {
  ## tile size is derived from resolution, not chosen independently
  expect_equal(tile_size(60), 600 * 60)
  expect_equal(tile_size(10), 600 * 10)
  ## L1/L2 nesting is exact 6x6 because it's a resolution ratio, not a
  ## tile-size ratio picked separately
  expect_equal(tile_size(60) / tile_size(10), 6)
  ## the whole S2-friendly resolution ladder nests exactly: every step's
  ## ratio must divide 600 (so a coarse pixel always covers an exact
  ## block of fine pixels)
  ladder <- c(10, 20, 60, 120, 360)
  for (i in seq_len(length(ladder) - 1)) {
    f <- ladder[i + 1] / ladder[i]
    expect_equal(f, round(f))
    expect_equal(600 %% f, 0)
  }
  ## every tile edge lies on the absolute 10 m lattice (Sentinel-2 native)
  zones <- define_utm_zones()
  expect_true(all(zones$origin_x %% 10 == 0))
  expect_true(all(zones$origin_y %% 10 == 0))
  ## single origin across zones (assumed by tile arithmetic; enforce it)
  expect_identical(length(unique(zones$origin_x)), 1L)
  expect_identical(length(unique(zones$origin_y)), 1L)
})

test_that("utm_to_tile_index and tile_index_to_extent are inverse", {
  set.seed(43)
  x <- runif(50, 200000, 700000)
  y <- runif(50, 3900000, 4300000)
  for (res in c(60, 10)) {
    idx <- utm_to_tile_index(x, y, res)
    ext <- tile_index_to_extent(idx$col, idx$row, res)
    ## the point that produced the index falls inside the extent
    expect_true(all(x >= ext$xmin & x < ext$xmax))
    expect_true(all(y >= ext$ymin & y < ext$ymax))
    ## extent corners map back to the same index (xmin/ymin corner is
    ## inclusive; the max corner belongs to the next tile)
    idx2 <- utm_to_tile_index(ext$xmin, ext$ymin, res)
    expect_identical(idx2$col, idx$col)
    expect_identical(idx2$row, idx$row)
  }
})

test_that("legacy level names resolve identically to their resolution", {
  expect_identical(utm_to_tile_index(400000, 4100000, "L1"),
                    utm_to_tile_index(400000, 4100000, 60))
  expect_identical(utm_to_tile_index(400000, 4100000, "L2"),
                    utm_to_tile_index(400000, 4100000, 10))
})

test_that("an L1 tile (60m) is exactly tiled by its 36 L2 (10m) children", {
  ch <- get_child_tiles(6, 113, res_parent = 60, res_child = 10)
  expect_identical(nrow(ch), 36L)
  parent <- tile_index_to_extent(6, 113, 60)
  kids <- tile_index_to_extent(ch$col, ch$row, 10)
  expect_identical(min(kids$xmin), parent$xmin)
  expect_identical(max(kids$xmax), parent$xmax)
  expect_identical(min(kids$ymin), parent$ymin)
  expect_identical(max(kids$ymax), parent$ymax)
  ## children partition the parent: total area matches, no duplicates
  expect_identical(nrow(unique(ch[c("col", "row")])), 36L)
  ## and the default arguments match the old L1->L2 call
  expect_identical(get_child_tiles(6, 113), ch)
})

test_that("nesting_factor rejects a non-integer ratio", {
  ## 65 m doesn't divide into anything on the S2-friendly ladder
  expect_error(get_child_tiles(6, 113, res_parent = 60, res_child = 65))
})

test_that("make_tile_id refuses ambiguous recycling", {
  ## scalars recycle against vectors: fine
  expect_length(make_tile_id("43S", 60, 5:7, 113L), 3L)
  ## equal-length vectors zip elementwise: fine
  expect_length(make_tile_id("43S", 60, 5:7, c(113L, 113L, 114L)), 3L)
  ## mismatched non-scalar lengths must ERROR, not recycle.
  ## Regression: make_tile_id("43S", "L1", 5:7, 113:114) once returned
  ## three ids, silently omitting 0006_0113 (the Atlas Cove tile).
  expect_error(make_tile_id("43S", 60, 5:7, 113:114))
})

test_that("tile ids round-trip through parse", {
  id <- make_tile_id("43S", 60, 6L, 113L)
  expect_identical(id, "43S_R0060_0006_0113")
  p <- parse_tile_id(id)
  expect_identical(p$zone_id, "43S")
  expect_identical(p$res, 60L)
  expect_identical(p$col, 6L)
  expect_identical(p$row, 113L)
})

test_that("legacy level-named ids still parse (nothing already written orphans)", {
  p <- parse_tile_id("43S_L1_0006_0113")
  expect_identical(p$res, 60)
  p2 <- parse_tile_id("43S_L2_0006_0113")
  expect_identical(p2$res, 10)
})
test_that("zone identifiers are padded", {
expect_identical(parse_tile_id("1S_R0060_0005_0113")$zone_id, "01S")
expect_identical(
  with(parse_tile_id("01S_R0060_0005_0113"),
       make_tile_id(zone_id, res, col, row)),
  "01S_R0060_0005_0113")
})

## ---------------------------------------------------------------------------
## Heard / McDonald integration case (zone 43S, EPSG:32743)
##
## Anchor coordinates projected with PROJ from EPSG:4326. Tolerances are
## loose (10 m) so any conforming PROJ version passes; the tile answers
## are exact integers and must not drift.
## ---------------------------------------------------------------------------

heard_anchors <- data.frame(
  name = c("atlas_cove", "big_ben", "spit_bay",
           "mcdonald", "coast_bbox_ne_islet"),
  lon  = c(73.3868, 73.5167, 73.7189, 72.5773, 73.58),
  lat  = c(-53.0243, -53.1000, -53.1141, -53.0380, -52.91414),
  ## expected L1/60m (col, row) under origin 140000/20000, tile 36000
  col  = c(6L, 7L, 7L, 5L, 7L),
  row  = c(113L, 113L, 113L, 113L, 114L)
)

test_that("Heard anchors land in the documented L1 (60m) tiles", {
  xy <- lonlat_to_utm(heard_anchors$lon, heard_anchors$lat, zone = "43S")
  idx <- utm_to_tile_index(xy$x, xy$y, 60)
  ## col/row are doubles (floor() of a numeric); compare by value
  expect_equal(idx$col, heard_anchors$col)
  expect_equal(idx$row, heard_anchors$row)
})

test_that("the HIMI coastline bbox is contained by the 3x2 L1 (60m) block", {
  ## wk_bbox of Mapping:himi_coastline_py, retrieved 2026-08
  bb <- c(xmin = 72.57784, ymin = -53.19276,
          xmax = 73.70948, ymax = -52.91414)
  corners <- lonlat_to_utm(
    lon = bb[c("xmin", "xmax", "xmin", "xmax")],
    lat = bb[c("ymin", "ymin", "ymax", "ymax")],
    zone = "43S"
  )
  idx <- utm_to_tile_index(corners$x, corners$y, 60)
  expect_true(all(idx$col >= 5L & idx$col <= 7L))
  expect_true(all(idx$row >= 113L & idx$row <= 114L))
})

test_that("Atlas Cove sits at a four-corner point (seam regression)", {
  ## The station-adjacent site is ~200 m from BOTH an L1 column seam
  ## (E 392000) and an L1 row seam (N 4124000). This is a documented
  ## property of the grid, not a bug: sites read windows, never tiles.
  ## If the origin ever changes, this test forces the change to be
  ## deliberate.
  xy <- lonlat_to_utm(73.3868, -53.0243, zone = "43S")
  ## explicit seam distances against the known lattice
  col_seam <- 140000 + ceiling((xy$x - 140000) / 36000) * 36000
  row_seam <- 20000 + ceiling((xy$y - 20000) / 36000) * 36000
  expect_lt(abs(col_seam - xy$x), 500)   # ~198 m
  expect_lt(abs(row_seam - xy$y), 500)   # ~191 m
})

test_that("generate_tiles_for_bbox is a working legacy alias", {
  ## Regression: this pre-rename name is still called internally by
  ## generate_tiles_for_feature() but had no definition in R/.
  heard_bbox <- c(72.57784, 73.70948, -53.19276, -52.91414)
  via_bbox <- generate_tiles_for_bbox(heard_bbox, 60, define_utm_zones())
  via_extent <- generate_tiles_for_extent(heard_bbox, 60, define_utm_zones())
  expect_identical(values(via_bbox), values(via_extent))
})

test_that("generate_tiles_for_extent covers the Heard bbox", {
  ## Regression for the utm_to_tile_index signature drift: this call
  ## errored with "unused arguments" when the caller passed origins.
  heard_bbox <- c(72.57784, 73.70948, -53.19276, -52.91414)
  hl1 <- generate_tiles_for_extent(heard_bbox, 60, define_utm_zones())
  ids <- make_tile_id(hl1$zone_id, 60, hl1$col, hl1$row)
  need <- with(expand.grid(col = 5:7, row = 113:114),
               make_tile_id("43S", 60, col, row))
  expect_true(all(need %in% ids))
})
