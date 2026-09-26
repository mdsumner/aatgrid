# aatgrid 0.2.0

## New features

* Added a Sentinel-2 MGRS bridge (`R/mgrs.R`), connecting aatgrid tiles
  to the MGRS scene vocabulary used by starc's acquisition `tile` field:
  * `mgrs_extent()` — scene extent for a 5-character MGRS code, derived
    from `geographiclib::mgrs_rev()` plus the reverse-engineered S2
    scene-snapping rule (60 m lattice, hemisphere-dependent northing
    offset, 109800 m scene size). Verified to 0 m residual against 132
    archive MGRS codes across 55 UTM zones and both hemispheres.
  * `tiles_to_mgrs()` — maps a single-zone block of aatgrid tiles to
    intersecting MGRS scenes, same-zone by interval arithmetic and
    cross-zone via densified extent reprojection (`utm_extent_to_lonlat()`,
    internal).
* `geographiclib` and `PROJ` added as optional (`Suggests`) dependencies
  for this MGRS functionality only; both are now checked with
  `requireNamespace()` and fail with an informative message if missing
  (`PROJ` also gains a `Remotes: hypertidy/PROJ` entry, matching the
  existing `hypertidy/sds`).

# aatgrid 0.1.0

* Initial parametric grid: `GRID_ORIGIN`, `PIXELS_PER_TILE`, and
  resolution-derived tile sizing replace the old fixed L1/L2 level
  tables (kept as aliases). UTM zone definitions, tile indexing,
  raster-based tile identification, and extent-aligned tile
  materialization (`tiles_for_extent2()`, `tile_range()`, `tile_gt()`).
