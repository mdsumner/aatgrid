# Tests for extent alignment, densified bounds, and materialization.

test_that("tile_range is idempotent on tile-aligned extents", {
  for (res in c(10, 60)) {
    tr <- tile_range(c(392000, 428000, 4124000, 4160000), res)
    tr2 <- tile_range(tr$extent, res)
    expect_identical(tr2$col, tr$col)
    expect_identical(tr2$row, tr$row)
    expect_identical(tr2$extent, tr$extent)
  }
})

test_that("tile_range edges land on the origin lattice", {
  tr <- tile_range(c(337612, 413675, 4103547, 4136501), 60)
  ts <- tile_size(60)
  expect_true(all((tr$extent[1:2] - GRID_ORIGIN[["x"]]) %% ts == 0))
  expect_true(all((tr$extent[3:4] - GRID_ORIGIN[["y"]]) %% ts == 0))
})

test_that("a seam-exact edge does not drag in the empty neighbour", {
  ## xmax exactly on the col-8 seam (E 428000): col 8 must NOT appear
  tr <- tile_range(c(400000, 428000, 4100000, 4123000), 60)
  expect_identical(tr$col[2], 7)
  ## reprojection fuzz just below the seam resolves to the seam
  trf <- tile_range(c(400000, 427999.9999997, 4100000, 4123000), 60)
  expect_identical(trf$col[2], 7)
})

test_that("negative tile indices are refused as out-of-domain", {
  expect_error(tile_range(c(100000, 130000, 4100000, 4123000), 60),
               "outside the grid domain")
})

test_that("project_extent beats corner-only transformation", {
  ## Heard regression: exact coastline bbox; corner-only western-top
  ## derivation missed the northern islet (N 4136337) by 337 m.
  bb <- c(72.57784, 73.70948, -53.19276, -52.91414)
  ex <- project_extent(bb, "EPSG:32743")
  expect_gte(ex[4], 4136500)   # at least the NE corner northing
  ## CM-inside-range case: no corner sees the true edge maximum
  bb2 <- c(74.0, 76.0, -53.19276, -52.91414)
  ex2 <- project_extent(bb2, "EPSG:32743")
  expect_gte(ex2[4], 4137280)  # edge max at the CM, 468 m above corners
})

test_that("tiles_for_extent2 covers the Heard scheme with the exact bbox", {
  bb <- c(72.57784, 73.70948, -53.19276, -52.91414)
  hl1 <- tiles_for_extent2(bb, 60)          # centroid zone -> 43S
  need <- make_tile_id("43S", 60, rep(5:7, 2), rep(113:114, each = 3))
  expect_true(all(need %in% hl1$tile_id))
  ## the islet's L2 tile is present at 10 m (this fails under any
  ## corner-only bounds scheme)
  hl2 <- tiles_for_extent2(bb, 10)
  expect_true(make_tile_id("43S", 10, 44, 686) %in% hl2$tile_id)
})

test_that("tiles_for_extent2 geometry is wk rct with the zone crs", {
  bb <- c(72.57784, 73.70948, -53.19276, -52.91414)
  hl1 <- tiles_for_extent2(bb, 60)
  expect_s3_class(hl1$geometry, "wk_rct")
  expect_identical(wk::wk_crs(hl1$geometry), "EPSG:32743")
  ## rct fields agree with tile_index_to_extent
  ex <- tile_index_to_extent(hl1$col, hl1$row, 60)
  rc <- unclass(hl1$geometry)
  expect_equal(rc$xmin, ex$xmin)
  expect_equal(rc$ymax, ex$ymax)
})

test_that("pad adds whole tile rings", {
  bb <- c(72.57784, 73.70948, -53.19276, -52.91414)
  t0 <- tiles_for_extent2(bb, 60, pad = 0)
  t1 <- tiles_for_extent2(bb, 60, pad = 1)
  expect_identical(nrow(t1),
                   (diff(range(t0$col)) + 3L) * (diff(range(t0$row)) + 3L))
  expect_true(all(t0$tile_id %in% t1$tile_id))
})

test_that("tile_gt is a valid warp target", {
  gt <- tile_gt(6, 113, 60)
  ex <- tile_index_to_extent(6, 113, 60)
  expect_equal(gt[1L, "xmin"], ex[["xmin"]], ignore_attr = TRUE)
  expect_equal(gt[1L, "ymax"], ex[["ymax"]], ignore_attr = TRUE)
  expect_equal(gt[1L, "xres"], 60, ignore_attr = TRUE)
  expect_equal(gt[1L, "yres"], -60, ignore_attr = TRUE)
  ## extent recovered from gt + PIXELS_PER_TILE round-trips
  expect_equal(gt[1L, "xmin"] + PIXELS_PER_TILE * gt[1L, "xres"], ex[["xmax"]], ignore_attr = TRUE)
  expect_equal(gt[1L, "ymax"] + PIXELS_PER_TILE * gt[1L, "yres"], ex[["ymin"]], ignore_attr = TRUE)
  ## vectorized
  gts <- tile_gt(5:7, c(113, 113, 114), 60)
  expect_identical(nrow(gts), 3L)
})

