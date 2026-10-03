# Tests for the raster-based tile identification path.
#
# The zone raster is a WINDOW onto the tile lattice: each cell is a
# tile, but the raster's first column is not necessarily tile column 0
# and terra rows run north-to-south while tile rows count up from the
# origin. Regression: cells_to_tile_indices() once returned raster
# row/col numbers directly, so fast_identify_tiles() placed Heard at
# (col 16, row 2) instead of (col 4, row 94). These tests pin the
# raster path to the arithmetic path (tiles_for_extent2 / tile_range).

zones <- define_utm_zones()
heard_bb <- c(72.57784, 73.70948, -53.19276, -52.91414)

extent_polygon <- function(ex, crs = "EPSG:4326") {
  terra::vect(matrix(c(ex[1], ex[3], ex[2], ex[3], ex[2], ex[4],
                       ex[1], ex[4], ex[1], ex[3]),
                     ncol = 2, byrow = TRUE),
              type = "polygons", crs = crs)
}

test_that("create_zone_raster is a tile-aligned specification", {
  for (res in list(60, 10, "L1", "L2")) {
    r <- create_zone_raster("43S", res, zones)
    ts <- tile_size(res)
    expect_equal(terra::res(r), c(ts, ts))
    ex <- as.vector(terra::ext(r))
    ## every edge sits on the origin lattice
    expect_equal((ex[["xmin"]] - GRID_ORIGIN[["x"]]) %% ts, 0)
    expect_equal((ex[["xmax"]] - GRID_ORIGIN[["x"]]) %% ts, 0)
    expect_equal((ex[["ymin"]] - GRID_ORIGIN[["y"]]) %% ts, 0)
    expect_equal((ex[["ymax"]] - GRID_ORIGIN[["y"]]) %% ts, 0)
    ## starts at the origin: no negative tile indices are representable
    expect_gte(ex[["xmin"]], GRID_ORIGIN[["x"]])
    expect_gte(ex[["ymin"]], GRID_ORIGIN[["y"]])
    ## dimension is exact (no fractional cells)
    expect_equal(terra::ncol(r) * ts, ex[["xmax"]] - ex[["xmin"]])
    expect_equal(terra::nrow(r) * ts, ex[["ymax"]] - ex[["ymin"]])
    expect_equal(terra::crs(r, describe = TRUE)$code, "32743")
  }
  ## names encode the numeric resolution regardless of alias used
  expect_identical(names(create_zone_raster("43S", "L1", zones)),
                   names(create_zone_raster("43S", 60, zones)))
})

test_that("create_zone_raster snaps a custom extent outward to tile edges", {
  r <- create_zone_raster("43S", 60, zones,
                          zone_extent = c(337612, 413675, 4103547, 4136501))
  tr <- tile_range(c(337612, 413675, 4103547, 4136501), 60)
  expect_equal(as.vector(terra::ext(r)), tr$extent, ignore_attr = TRUE)
  expect_equal(terra::ncol(r), diff(tr$col) + 1)
  expect_equal(terra::nrow(r), diff(tr$row) + 1)
})

test_that("create_zone_raster refuses extents below the origin", {
  expect_error(create_zone_raster("43S", 60, zones,
                                  zone_extent = c(100000, 300000, 4e6, 4.1e6)),
               "below the grid origin")
  expect_error(create_zone_raster("43S", 60, zones, zone_extent = 1:3),
               "xmin, xmax, ymin, ymax")
})

test_that("cells_to_tile_indices recovers lattice indices, not raster indices", {
  ## a window that does NOT start at tile column 0 / row 0
  r <- create_zone_raster("43S", 60, zones,
                          zone_extent = c(300000, 500000, 4000000, 4200000))
  cells <- seq_len(terra::ncell(r))
  idx <- cells_to_tile_indices(r, cells)
  ## cross-check every cell centre against the point query
  xy <- terra::xyFromCell(r, cells)
  ref <- utm_to_tile_index(xy[, 1], xy[, 2], 60)
  expect_equal(idx$col, ref$col)
  expect_equal(idx$row, ref$row)
  ## terra's top row is the NORTHERNMOST tile row, i.e. the largest index
  top_left <- cells_to_tile_indices(r, 1)
  bottom_left <- cells_to_tile_indices(r, terra::cellFromRowCol(r, terra::nrow(r), 1))
  expect_gt(top_left$row, bottom_left$row)
  expect_identical(top_left$col, bottom_left$col)
  ## and the first raster column is not column 0 here
  expect_gt(top_left$col, 0L)
  expect_type(idx$col, "integer")
})

test_that("fast_identify_tiles is the true intersection; tiles_for_extent2 its bbox superset", {
  ## tiles_for_extent2 tiles the projected BBOX of the extent, so it is a
  ## superset of the tiles the projected polygon actually touches. At
  ## 60 m the two coincide for Heard; at 10 m the polygon's eastern edge
  ## (a meridian, curving toward the CM with latitude) reaches column 38
  ## only in the southern rows. The raster path must give exactly the
  ## touched set, checked independently with terra::relate.
  feat <- extent_polygon(heard_bb)
  feat_utm <- terra::project(terra::densify(feat, 500), "EPSG:32743")
  for (res in c(60, 10)) {
    fast <- fast_identify_tiles(feat, "43S", res, zones)
    arith <- tiles_for_extent2(heard_bb, res)
    expect_true(all(fast$tile_id %in% arith$tile_id))
    expect_identical(unique(fast$zone_id), "43S")
    expect_equal(unique(fast$res), res)
    ## independent truth: which bbox tiles really intersect the polygon
    ex <- tile_index_to_extent(arith$col, arith$row, res)
    polys <- do.call(rbind, lapply(seq_len(nrow(ex)), function(i) {
      terra::as.polygons(terra::ext(ex$xmin[i], ex$xmax[i], ex$ymin[i], ex$ymax[i]),
                         crs = "EPSG:32743")
    }))
    hit <- as.vector(terra::relate(polys, feat_utm, "intersects"))
    expect_setequal(fast$tile_id, arith$tile_id[hit])
  }
  ## and the 60 m case coincides with the bbox tiling entirely
  expect_setequal(fast_identify_tiles(feat, "43S", 60, zones)$tile_id,
                  tiles_for_extent2(heard_bb, 60)$tile_id)
  ## 10 m: the bbox superset is strictly larger here
  expect_lt(nrow(fast_identify_tiles(feat, "43S", 10, zones)),
            nrow(tiles_for_extent2(heard_bb, 10)))
  ## legacy alias gives numeric res in the output
  fl <- fast_identify_tiles(feat, "43S", "L1", zones)
  expect_equal(unique(fl$res), 60)
})

test_that("fast_identify_tiles honours a pre-built zone raster and checks it", {
  feat <- extent_polygon(heard_bb)
  zr <- create_zone_raster("43S", 60, zones)
  a <- fast_identify_tiles(feat, "43S", 60, zones)
  b <- fast_identify_tiles(feat, "43S", 60, zones, zone_raster = zr)
  expect_identical(a, b)
  ## a raster at the wrong resolution is rejected, not silently used
  zr10 <- create_zone_raster("43S", 10, zones)
  expect_error(fast_identify_tiles(feat, "43S", 60, zones, zone_raster = zr10),
               "does not match")
})

test_that("fast_identify_tiles works for features already in zone CRS", {
  ex <- project_extent(heard_bb, "EPSG:32743")
  feat_utm <- extent_polygon(ex, crs = "EPSG:32743")
  fast <- fast_identify_tiles(feat_utm, "43S", 60, zones)
  arith <- tiles_for_extent2(heard_bb, 60)
  expect_setequal(fast$tile_id, arith$tile_id)
})

test_that("points and lines are identified, and empty results have the schema", {
  ## a single point: exactly one tile
  pt <- terra::vect(cbind(73.3868, -53.0243), crs = "EPSG:4326")
  one <- fast_identify_tiles(pt, "43S", 60, zones)
  expect_identical(nrow(one), 1L)
  expect_identical(one$tile_id, "43S_R0060_0005_0094")
  ## a line crossing a seam: both tiles
  ln <- terra::vect(rbind(c(73.3, -53.03), c(73.6, -53.03)),
                    type = "lines", crs = "EPSG:4326")
  two <- fast_identify_tiles(ln, "43S", 60, zones)
  expect_true(all(c("43S_R0060_0005_0094", "43S_R0060_0006_0094") %in% two$tile_id))
  ## feature outside the raster window: empty with canonical columns
  far <- terra::vect(cbind(73, -30), crs = "EPSG:4326")
  none <- fast_identify_tiles(far, "43S", 60, zones)
  expect_identical(nrow(none), 0L)
  expect_named(none, c("tile_id", "zone_id", "res", "col", "row"))
  expect_type(none$res, "double")
})

test_that("buffer_m grows the tile set", {
  pt <- terra::vect(cbind(73.3868, -53.0243), crs = "EPSG:4326")
  ## Atlas Cove is ~191 m south of the row seam at N 4124000
  buffered <- fast_identify_tiles(pt, "43S", 60, zones, buffer_m = 500)
  expect_true("43S_R0060_0005_0095" %in% buffered$tile_id)
  expect_gt(nrow(buffered), 1L)
})

test_that("fast_identify_tiles_multizone filters zones by longitude", {
  feat <- extent_polygon(heard_bb)
  ## Heard is wholly in zone 43; asking for 42:44 returns only 43S tiles
  mz <- fast_identify_tiles_multizone(feat, c("42S", "43S", "44S"), 60, zones)
  expect_identical(unique(mz$zone_id), "43S")
  expect_setequal(mz$tile_id, tiles_for_extent2(heard_bb, 60)$tile_id)
  ## a zone list that excludes 43S yields nothing
  none <- fast_identify_tiles_multizone(feat, c("44S", "45S"), 60, zones)
  expect_identical(nrow(none), 0L)
  expect_named(none, c("tile_id", "zone_id", "res", "col", "row"))
  ## a feature straddling the 42/43 seam (72E) is reported in both zones
  straddle <- extent_polygon(c(71.9, 72.1, -53.1, -53.0))
  both <- fast_identify_tiles_multizone(straddle, c("42S", "43S"), 60, zones)
  expect_setequal(unique(both$zone_id), c("42S", "43S"))
})

test_that("get_tile_extents_from_df is vectorised and matches tile_index_to_extent", {
  feat <- extent_polygon(heard_bb)
  tiles <- fast_identify_tiles(feat, "43S", 60, zones)
  ex <- get_tile_extents_from_df(tiles)
  expect_identical(nrow(ex), nrow(tiles))
  expect_named(ex, c("tile_id", "xmin", "xmax", "ymin", "ymax"))
  ref <- tile_index_to_extent(tiles$col, tiles$row, 60)
  expect_equal(ex$xmin, ref$xmin)
  expect_equal(ex$ymax, ref$ymax)
  expect_type(ex$xmin, "double")
  ## empty in, empty (but shaped) out
  empty <- get_tile_extents_from_df(tiles[0, ])
  expect_identical(nrow(empty), 0L)
  expect_named(empty, c("tile_id", "xmin", "xmax", "ymin", "ymax"))
  ## mixed resolutions are refused
  mixed <- rbind(tiles[1, ], transform(tiles[1, ], res = 10))
  expect_error(get_tile_extents_from_df(mixed), "mixes resolutions")
})

test_that("create_tile_templates_from_df yields 720x720 rasters in the zone CRS", {
  feat <- extent_polygon(heard_bb)
  tiles <- fast_identify_tiles(feat, "43S", 60, zones)
  tmpl <- create_tile_templates_from_df(tiles[1:2, ], zones)
  expect_named(tmpl, tiles$tile_id[1:2])
  for (i in 1:2) {
    r <- tmpl[[i]]
    expect_equal(dim(r)[1:2], c(PIXELS_PER_TILE, PIXELS_PER_TILE))
    expect_equal(terra::res(r), c(60, 60))
    expect_equal(as.vector(terra::ext(r)),
                 unlist(tile_index_to_extent(tiles$col[i], tiles$row[i], 60))[c("xmin", "xmax", "ymin", "ymax")],
                 ignore_attr = TRUE)
    expect_equal(terra::crs(r, describe = TRUE)$code, "32743")
  }
})

test_that("create_all_zone_rasters returns one raster per requested zone", {
  rl <- create_all_zone_rasters(60, zones, zone_ids = c("42S", "43S"))
  expect_named(rl, c("42S", "43S"))
  expect_equal(terra::crs(rl[["42S"]], describe = TRUE)$code, "32742")
  expect_equal(terra::crs(rl[["43S"]], describe = TRUE)$code, "32743")
  ## same lattice window in every zone (origin is shared)
  expect_equal(as.vector(terra::ext(rl[["42S"]])), as.vector(terra::ext(rl[["43S"]])))
})
