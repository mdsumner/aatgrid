# Tests for extent_boundary() and the densified project_extent() it
# backs. extent_boundary is the anti-corner-trap primitive: every other
# "transform an extent" rule in the package reduces to it.

test_that("extent_boundary walks the four edges anticlockwise from SW", {
  ex <- c(0, 10, 100, 120)
  b <- extent_boundary(ex, n = 3)
  expect_true(is.matrix(b))
  expect_identical(dim(b), c(12L, 2L))
  expect_type(b, "double")
  ## south edge: y fixed at ymin, x from xmin to xmax
  expect_equal(b[1:3, ], cbind(c(0, 5, 10), 100), ignore_attr = TRUE)
  ## east edge: x fixed at xmax, y from ymin to ymax
  expect_equal(b[4:6, ], cbind(10, c(100, 110, 120)), ignore_attr = TRUE)
  ## north edge: y fixed at ymax, x from xmax back to xmin
  expect_equal(b[7:9, ], cbind(c(10, 5, 0), 120), ignore_attr = TRUE)
  ## west edge: x fixed at xmin, y from ymax back to ymin
  expect_equal(b[10:12, ], cbind(0, c(120, 110, 100)), ignore_attr = TRUE)
  ## every vertex lies on the boundary and the bbox is recovered exactly
  on_edge <- b[, 1] == 0 | b[, 1] == 10 | b[, 2] == 100 | b[, 2] == 120
  expect_true(all(on_edge))
  expect_equal(c(range(b[, 1]), range(b[, 2])), ex)
})

test_that("extent_boundary has 4n rows and the default is 21 per edge", {
  for (n in c(2, 5, 21, 64)) {
    expect_identical(nrow(extent_boundary(c(72, 74, -54, -52), n = n)), 4L * as.integer(n))
  }
  expect_identical(nrow(extent_boundary(c(72, 74, -54, -52))), 84L)
})

test_that("extent_boundary validates its input", {
  expect_error(extent_boundary(c(0, 1, 2)), "xmin, xmax, ymin, ymax")
  expect_error(extent_boundary(c(0, 1, 2, NA)), "no NA")
  ## sf-style ordering (xmin, ymin, xmax, ymax) is the classic mistake
  expect_error(extent_boundary(c(72, -54, 74, -52)), "ordering")
  expect_error(extent_boundary(c(0, 10, 100, 120), n = 1), "at least 2")
})

test_that("extent_boundary of a degenerate extent is well-formed", {
  ## a point extent: all vertices identical
  b <- extent_boundary(c(5, 5, 7, 7), n = 4)
  expect_true(all(b[, 1] == 5) && all(b[, 2] == 7))
  ## a zero-width (seam) extent
  b2 <- extent_boundary(c(5, 5, 0, 10), n = 4)
  expect_true(all(b2[, 1] == 5))
  expect_equal(range(b2[, 2]), c(0, 10))
})

test_that("project_extent is the bbox of the transformed densified boundary", {
  bb <- c(72.57784, 73.70948, -53.19276, -52.91414)
  ex <- project_extent(bb, "EPSG:32743", n = 21)
  b <- extent_boundary(bb, n = 21)
  xy <- reproj::reproj_xy(b, "EPSG:32743", source = "EPSG:4326")
  expect_equal(unname(ex), c(min(xy[, 1]), max(xy[, 1]), min(xy[, 2]), max(xy[, 2])),
               tolerance = 1e-6)
  ## and it strictly contains the corner-only bbox where curvature bites
  corners <- reproj::reproj_xy(cbind(bb[c(1, 2, 1, 2)], bb[c(3, 3, 4, 4)]),
                               "EPSG:32743", source = "EPSG:4326")
  expect_gte(ex[4], max(corners[, 2]))
  expect_lte(ex[1], min(corners[, 1]))
})

test_that("project_extent beats the corner-only bbox where the CM is inside", {
  bb <- c(74.0, 76.0, -53.19276, -52.91414)   # CM 75E inside the lon range
  corners <- reproj::reproj_xy(cbind(bb[c(1, 2, 1, 2)], bb[c(3, 3, 4, 4)]),
                               "EPSG:32743", source = "EPSG:4326")
  e_corner <- c(range(corners[, 1]), range(corners[, 2]))
  e21 <- project_extent(bb, "EPSG:32743", n = 21)
  e64 <- project_extent(bb, "EPSG:32743", n = 64)
  ## densified bounds contain the corner bbox ...
  expect_gte(e21[4], e_corner[4])
  expect_lte(e21[3], e_corner[3])
  ## ... and more points only widen, never shrink
  expect_gte(e64[4], e21[4])
  expect_lte(e64[3], e21[3])
  ## the corner-only result genuinely misses the northern edge maximum
  ## (a parallel's max northing is at the CM, not at a corner)
  expect_gt(e21[4] - e_corner[4], 100)
})
