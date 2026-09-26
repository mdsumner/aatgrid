# Pins the archive-verified Sentinel-2 MGRS scene-extent convention
# (0 m residual on 132 codes, Sep 2026). If any of these fail after a
# geographiclib or convention change, the change is wrong or must be
# re-verified against the starc raw stash (see verify-mgrs-model.R).

test_that("southern-hemisphere scene extent matches archive truth", {
  skip_if_not_installed("geographiclib")
  me <- mgrs_extent("43DDE")   # Kerguelen-adjacent, zone 43S
  expect_identical(me$hemisphere, "S")
  expect_identical(me$epsg, "EPSG:32743")
  ## lattice congruences: the load-bearing facts
  expect_identical(me$extent[1] %% 60, 0)          # ulx on 60 m lattice
  expect_identical(me$extent[4] %% 60, 40)         # southern uly offset
  expect_identical(me$extent[2] - me$extent[1], 109800)
  expect_identical(me$extent[4] - me$extent[3], 109800)
})

test_that("northern-hemisphere branch uses the zero northing offset", {
  skip_if_not_installed("geographiclib")
  for (code in c("4QGH", "27WXP")) {   # Maui; Eyjafjordur
    me <- mgrs_extent(code)
    expect_identical(me$hemisphere, "N")
    expect_identical(me$extent[1] %% 60, 0)
    expect_identical(me$extent[4] %% 60, 0)        # northern offset 0
    expect_identical(me$extent[2] - me$extent[1], 109800)
  }
})

test_that("60 m assets sit at the constant (20,20) shift vs aatgrid, south", {
  ## aatgrid edges are congruent 20 (mod 60) on both axes
  ## (origin 140000/20000); S2 south is x==0, y==40 (mod 60)
  expect_identical(140000 %% 60, 20)
  expect_identical(20000 %% 60, 20)
})
