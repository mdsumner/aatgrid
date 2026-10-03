# Tests for aatgrid core grid arithmetic.
# Invariant tests first, then the Heard/McDonald integration case with
# authoritative expectations derived from the AADC himi_coastline_py extent
# (wk_bbox: 72.57784 -53.19276 73.70948 -52.91414, EPSG:4326).
#
# The grid is parametric: an origin (GRID_ORIGIN), a fixed pixel count per
# tile (PIXELS_PER_TILE = 720), and a resolution. Tile size is always
# derived: tile_size(res) = 720 * res. "L1"/"L2" are just named instances
# at 60 m / 10 m, kept as convenience aliases (see LEVEL_RESOLUTIONS) and
# as a parse-time alias for old ids -- they are not independent parameters.

test_that("grid spec constants are self-consistent", {
  ## tile size is derived from resolution, not chosen independently
  expect_equal(tile_size(60), 720 * 60)
  expect_equal(tile_size(10), 720 * 10)
  ## L1/L2 nesting is exact 6x6 because it's a resolution ratio, not a
  ## tile-size ratio picked separately
  expect_equal(tile_size(60) / tile_size(10), 6)
  ## the whole S2-friendly resolution ladder nests exactly: every step's
  ## ratio must divide 720 (so a coarse pixel always covers an exact
  ## block of fine pixels)
  ladder <- c(10, 20, 60, 120, 360)
  for (i in seq_len(length(ladder) - 1)) {
    f <- ladder[i + 1] / ladder[i]
    expect_equal(f, round(f))
    expect_equal(720 %% f, 0)
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
  expect_equal(p$res, 60)
  p2 <- parse_tile_id("43S_L2_0006_0113")
  expect_equal(p2$res, 10)
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
  ## expected L1/60m (col, row) under origin 140000/20000, tile 43200
  col  = c(5L, 6L, 6L, 4L, 6L),
  row  = c(94L, 94L, 94L, 94L, 95L)
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
  expect_true(all(idx$col >= 4L & idx$col <= 6L))
  expect_true(all(idx$row >= 94L & idx$row <= 95L))
})

test_that("Atlas Cove hugs the L1 row seam (seam regression)", {
  ## On the 720px lattice (tile 43200 m) the station-adjacent site is
  ## ~191 m south of the L1 row seam at N 4124000 (a seam both the old
  ## 36000 m and new 43200 m lattices share), while the nearest column
  ## seam is now ~7.4 km away -- the 600px-era four-corner coincidence
  ## is gone. This is a documented property of the grid, not a bug:
  ## sites read windows, never tiles. If the origin or tile size ever
  ## changes, this test forces the change to be deliberate.
  ts <- tile_size(60)
  xy <- lonlat_to_utm(73.3868, -53.0243, zone = "43S")
  ## explicit seam distances against the known lattice
  col_seam <- 140000 + ceiling((xy$x - 140000) / ts) * ts
  row_seam <- 20000 + ceiling((xy$y - 20000) / ts) * ts
  expect_identical(row_seam, 4124000)
  expect_lt(abs(row_seam - xy$y), 500)    # ~191 m
  expect_gt(abs(col_seam - xy$x), 5000)   # ~7398 m: not four-corner
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
  need <- with(expand.grid(col = 4:6, row = 94:95),
               make_tile_id("43S", 60, col, row))
  expect_true(all(need %in% ids))
})

## ---------------------------------------------------------------------------
## Additional coverage: vectorised ids, nesting symmetry, templates,
## polygon/catalog path, regions.
## ---------------------------------------------------------------------------

test_that("parse_tile_id is vectorised and always returns integer res", {
  ids <- c("43S_R0060_0006_0113", "55S_L2_0001_0002", "1S_L1_0000_0000")
  p <- parse_tile_id(ids)
  expect_identical(p$zone_id, c("43S", "55S", "01S"))
  expect_identical(p$res, c(60L, 10L, 60L))
  expect_type(p$res, "integer")
  expect_identical(p$col, c(6L, 1L, 0L))
  expect_identical(p$row, c(113L, 2L, 0L))
  expect_identical(p$zone_number, c(43L, 55L, 1L))
  expect_identical(p$hemisphere, c("S", "S", "S"))
  ## make/parse round trip over a batch
  g <- expand.grid(col = 0:3, row = 90:92)
  made <- make_tile_id("43S", 60, g$col, g$row)
  back <- parse_tile_id(made)
  expect_identical(make_tile_id(back$zone_id, back$res, back$col, back$row), made)
  ## 5-digit indices are not truncated by the %04d formatting
  big <- make_tile_id("43S", 10, 12345L, 7L)
  expect_identical(big, "43S_R0010_12345_0007")
  expect_identical(parse_tile_id(big)$col, 12345L)
})

test_that("parse_tile_id rejects malformed ids", {
  expect_error(parse_tile_id("43S_R0060_0006"), "malformed")
  expect_error(parse_tile_id("43S_X60_0006_0113"), "unrecognized")
  expect_error(parse_tile_id("43S_R0060_abcd_0113"), "non-integer")
  expect_error(parse_tile_id(42), "character")
})

test_that("make_tile_id resolves aliases and pads zones", {
  expect_identical(make_tile_id("43S", "L1", 6L, 113L), "43S_R0060_0006_0113")
  expect_identical(make_tile_id("43S", "L2", 6L, 113L), "43S_R0010_0006_0113")
  expect_identical(make_tile_id(c("1S", "43S"), 60, 0L, 0L),
                   c("01S_R0060_0000_0000", "43S_R0060_0000_0000"))
  expect_error(make_tile_id("43S", "L9", 0L, 0L), "unknown resolution")
})

test_that("get_parent_tile inverts get_child_tiles for every child", {
  ch <- get_child_tiles(6, 113, res_parent = 60, res_child = 10)
  par <- get_parent_tile(ch$col, ch$row, res_child = 10, res_parent = 60)
  expect_true(all(par$col == 6))
  expect_true(all(par$row == 113))
  ## three-level ladder: 10 -> 20 -> 60 composes
  ch20 <- get_child_tiles(6, 113, res_parent = 60, res_child = 20)   # 3x3
  expect_identical(nrow(ch20), 9L)
  ch10_via_20 <- do.call(rbind, lapply(seq_len(nrow(ch20)), function(i) {
    get_child_tiles(ch20$col[i], ch20$row[i], res_parent = 20, res_child = 10)
  }))
  direct <- get_child_tiles(6, 113, res_parent = 60, res_child = 10)
  expect_setequal(paste(ch10_via_20$col, ch10_via_20$row),
                  paste(direct$col, direct$row))
  ## parent of a parent is the parent (a tile is its own 1x1 child)
  expect_identical(nrow(get_child_tiles(6, 113, res_parent = 60, res_child = 60)), 1L)
  expect_error(get_child_tiles(6, 113, res_parent = 10, res_child = 60), "positive integer")
})

test_that("tile_index_to_extent and utm_to_tile_index are vectorised and typed", {
  ex <- tile_index_to_extent(0:2, 0L, 60)
  expect_identical(nrow(ex), 3L)
  expect_identical(ex$xmin, GRID_ORIGIN[["x"]] + (0:2) * 43200)
  expect_identical(ex$ymin, rep(GRID_ORIGIN[["y"]], 3))
  ## the origin itself is tile (0, 0); just below it is negative
  expect_identical(unlist(utm_to_tile_index(140000, 20000, 60)), c(col = 0, row = 0))
  expect_identical(unlist(utm_to_tile_index(139999, 19999, 60)), c(col = -1, row = -1))
})

test_that("create_tile_template, _extent and _polygon agree", {
  zones <- define_utm_zones()
  r <- create_tile_template("43S", 60, 6L, 113L, zones)
  expect_s4_class(r, "SpatRaster")
  expect_equal(dim(r)[1:2], c(PIXELS_PER_TILE, PIXELS_PER_TILE))
  expect_equal(terra::res(r), c(60, 60))
  expect_identical(names(r), "43S_R0060_0006_0113")
  expect_equal(terra::crs(r, describe = TRUE)$code, "32743")
  e <- create_tile_extent("43S", 60, 6L, 113L, zones)
  expect_s4_class(e, "SpatExtent")
  expect_equal(as.vector(terra::ext(r)), as.vector(e))
  p <- create_tile_polygon("43S", 60, 6L, 113L, zones)
  expect_s4_class(p, "SpatVector")
  expect_equal(as.vector(terra::ext(p)), as.vector(e))
  v <- terra::values(p)
  expect_identical(v$tile_id, "43S_R0060_0006_0113")
  expect_identical(v$res, 60)
  ## 10 m template has the same pixel count but a 6x smaller footprint
  r10 <- create_tile_template("43S", 10, 36L, 678L, zones)
  expect_equal(dim(r10)[1:2], c(PIXELS_PER_TILE, PIXELS_PER_TILE))
  expect_equal(terra::res(r10), c(10, 10))
  expect_equal(as.vector(terra::ext(r10))[["xmin"]], as.vector(e)[["xmin"]])
})

test_that("create_tile_catalog and export_tile_catalog describe the polygon set", {
  zones <- define_utm_zones()
  bb <- c(72.57784, 73.70948, -53.19276, -52.91414)
  tiles <- generate_tiles_for_extent(bb, 60, zones)
  cat_df <- create_tile_catalog(tiles)
  expect_equal(nrow(cat_df), nrow(tiles))
  expect_true(all(c("tile_id", "zone_id", "res", "col", "row", "tile_size_m",
                    "resolution_m", "pixels", "xmin", "xmax", "ymin", "ymax") %in% names(cat_df)))
  expect_true(all(cat_df$tile_size_m == 43200))
  expect_true(all(cat_df$resolution_m == 60))
  expect_true(all(cat_df$pixels == PIXELS_PER_TILE))
  expect_equal(cat_df$xmax - cat_df$xmin, rep(43200, nrow(cat_df)))
  ## the polygon set covers the same ids as the arithmetic path
  expect_setequal(cat_df$tile_id, tiles_for_extent2(bb, 60)$tile_id)
  f <- tempfile(fileext = ".csv")
  expect_message(export_tile_catalog(tiles, f), "exported")
  back <- utils::read.csv(f, stringsAsFactors = FALSE)
  expect_identical(nrow(back), nrow(cat_df))
  expect_setequal(back$tile_id, cat_df$tile_id)
  unlink(f)
})

test_that("generate_tiles_for_feature filters to intersecting tiles only", {
  zones <- define_utm_zones()
  ## a small polygon well inside one tile
  sq <- terra::vect(matrix(c(73.30, -53.05, 73.32, -53.05, 73.32, -53.04,
                             73.30, -53.04, 73.30, -53.05), ncol = 2, byrow = TRUE),
                    type = "polygons", crs = "EPSG:4326")
  t60 <- generate_tiles_for_feature(sq, 60, zones)
  expect_equal(nrow(t60), 1)
  expect_identical(terra::values(t60)$tile_id, "43S_R0060_0005_0094")
  ## hierarchy: L2 tiles are children of L1 tiles
  h <- generate_tile_hierarchy(sq, zones)
  l1 <- terra::values(h$L1)
  l2 <- terra::values(h$L2)
  par <- get_parent_tile(l2$col, l2$row)
  expect_true(all(paste(par$col, par$row) %in% paste(l1$col, l1$row)))
  expect_true(all(l2$res == 10))
})

test_that("get_aat_regions are terra-ordered lonlat extents in sensible zones", {
  reg <- get_aat_regions()
  expect_named(reg, c("heard_mcdonald", "macquarie", "aat_mainland", "aat_extended"))
  for (r in reg) {
    expect_length(r, 4L)
    expect_lt(r[[1]], r[[2]])   # xmin < xmax
    expect_lt(r[[3]], r[[4]])   # ymin < ymax
    expect_true(all(r[1:2] >= -180 & r[1:2] <= 180))
    expect_true(all(r[3:4] >= -90 & r[3:4] <= 0))
  }
  expect_identical(lon_to_zone_id(mean(reg$heard_mcdonald[1:2])), "43S")
  expect_identical(lon_to_zone_id(mean(reg$macquarie[1:2])), "57S")
})
