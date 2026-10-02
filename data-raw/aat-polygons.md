# aatgrid coastline fixture: run sheet

## 0. Pin decisions first
- [ ] PIXELS_PER_TILE -> 720 in aatgrid (NEWS entry, version bump).
      Ids keep their format but now mean 720-px tiles.
- [ ] Record the scheme (px, origin, source versions) in every output's
      metadata, so ids stay interpretable without the package version.
- [ ] Classes: land, ice_shelf, ice_tongue, rumple, ocean.
- [ ] Zone policy for classification: each zone's 6-degree band, plus an
      overlap margin (decide width). Keep an in_zone flag per tile.
- [ ] Resolutions to classify: 10, 20, 60 (720 px -> 7.2, 14.4, 43.2 km).

## 1. Acquire sources (data-raw/)
- [ ] ADD high-res polygons v7.10 (GeoPackage, EPSG:3031, CC BY 4.0).
      Record DOI, version, date and sha256 in data-raw/SOURCES.md.
- [ ] ADD medium-res polygons, for overview comparison only.
- [ ] Sub-Antarctic coastlines for Heard/McDonald and Macquarie
      (not in ADD, which stops at 60S). Same provenance record.

## 2. Coverage (cvr)
- [ ] coverage validate on ADD; write gaps/overlaps to a report.
- [ ] Fix or document the invalid edges. Never silently drop them.
- [ ] Check that class boundaries (grounding line, shelf/tongue edges)
      are shared edges, not near-duplicates.

## 3. Arcs + ranks
- [ ] Build the arc table.
      arcs:  arc_id, n, x, y (EPSG:3031)
      faces: face_id, class, ring_id, arc_id, reversed, seq
- [ ] Round-trip test: rebuild polygons from arcs == input
      (per face: area and vertex count equal).
- [ ] Ranks from a coverage-simplify tolerance ladder: a vertex's rank is
      the largest tolerance at which it survives. Node vertices get Inf.
      This inherits the coverage guarantee (no cross-arc intersections),
      which per-arc VW ranks would not.
- [ ] Check at a few rank cutoffs that the coverage is still valid.

## 4. LOD tiers
- [ ] Choose rank cutoffs: tier 0 = whole-AAT overview, target < 2 MB.
- [ ] Chunk higher tiers by aatgrid tile (e.g. R0060) using arc bbox.
      Arcs stay whole; the index maps tile -> arc_ids.
- [ ] Quantise coordinates (e.g. 1 m) and write Parquet to the bucket.

## 5. Tile classification (exact, full resolution)
- [ ] For each zone touching AAT, plus 43S Heard and 57S Macquarie:
      enumerate candidate tiles per res from the coastline bbox (+ pad).
- [ ] Transform tile rectangles to 3031, densified (project_extent logic),
      rather than the coastline to UTM.
- [ ] Per tile: area fraction of each class, with areas measured in the
      zone UTM (transform the clipped pieces back) to avoid 3031 scale error.
- [ ] Derive touches_<class> and margin_class
      (inland / coastal / ocean_only).
- [ ] Write registry/tile_surface.parquet:
      tile_id, zone_id, res, col, row, px, frac_land, frac_ice_shelf,
      frac_ice_tongue, frac_rumple, frac_ocean, touches_*, margin_class,
      in_zone, source, source_version
- [ ] Invariant tests (these are cheap and catch most bugs):
      parent frac == mean of its children's fracs (exact nesting);
      parent touches_X == any child touches_X;
      fracs sum to 1.

## 6. Fixture in aatgrid
- [ ] Pick a small region inside ADD (e.g. Mawson/Auster, ~60 x 60 km;
      Heard is not in ADD).
- [ ] inst/extdata/: fixture arcs + ranks + classification rows for
      10/20/60. Use rds or csv, not parquet, to keep deps minimal.
- [ ] data-raw/make_fixture.R regenerates everything from the sources.
- [ ] Tests: classification recomputed from fixture arcs == fixture rows;
      id round-trip; the invariants from step 5.
- [ ] README: update the grid table (36 km -> 43.2 km etc.) and add
      ADD attribution.

## 7. Hand-off to the explorer
- [ ] Tier 0 + tier index + a registry snapshot, each < 16 MB.
      Then the explorer swaps the Natural Earth strips for arcs and reads
      classes from the registry instead of its screen mask.
