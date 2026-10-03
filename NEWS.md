# aatgrid 0.3.1

## Bug fixes

* `fast_identify_tiles()` (and everything built on `cells_to_tile_indices()`)
  returned raster row/column numbers instead of tile indices, so tiles were
  mislabelled whenever the zone raster window did not start at tile (0, 0)
  and rows were flipped north-for-south (Heard reported as col 16 / row 2
  instead of col 4 / row 94). Indices are now recovered from each cell's
  centre against `GRID_ORIGIN`.
* `create_zone_raster()` default extent began 500 km west of the origin,
  outside the lattice; it now starts at the origin and refuses extents
  below it.
* `tiles_for_extent2()` failed for zones 1-9 ("1S" is not a zone id); the
  centroid zone now goes through the new `lon_to_zone_id()`, which pads.
* `generate_tiles_for_feature()` built its lonlat extent in sf bbox order
  and handed it to a terra-ordered function, so no zones were ever found;
  it also tripped terra's `rbind()` by passing a named list.
* Lonlat lines/polygons are now densified (1 km) before projection in
  `identify_intersecting_tiles()` and `generate_tiles_for_extent()`, the
  polygon form of the corner trap handled by `project_extent()`.
* `get_map()` memoisation in `.onAttach()` was a no-op local assignment
  (and used a typo'd name); it is now applied in `.onLoad()`.
* `R/generate_utm_zone_boundaries.R` called `library(terra)` at package
  top level.

## New features / API

* `extent_boundary()` is now exported, validates its input (terra
  ordering, no NA, n >= 2) and is documented as the densification
  primitive behind `project_extent()`.
* `generate_utm_zone_boundaries()`, `lon_to_zone_id()` and
  `cells_to_tile_indices()` are exported.
* `parse_tile_id()` is vectorised, rejects malformed ids, and always
  returns integer `res` (ids encode whole metres).
* `get_tile_extents_from_df()` is vectorised; `zones` is no longer needed.
* `fast_identify_tiles()` returns numeric `res` even when called with a
  level alias, and checks that a supplied `zone_raster` matches `res`.

## Tests

* Test coverage grew from 98 to ~360 expectations, adding files for the
  raster identification path (pinned to the arithmetic path and to an
  independent `terra::relate()` truth), the zone table and boundary lines,
  and `extent_boundary()` / `project_extent()`.

## Documentation

* Removed stale references to 36 km / 6 km tiles, zones 42-58 only, and
  the old `aat-grid-system` repository name.

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
