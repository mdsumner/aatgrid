# Antarctic Grid System - Quick Reference

## Grid Specifications

| Parameter | Level 1 (L1) | Level 2 (L2) |
|-----------|-------------|--------------|
| Tile Size | 36 km × 36 km | 6 km × 6 km |
| Resolution | 60 m/pixel | 10 m/pixel |
| Image Size | 600 × 600 px | 600 × 600 px |
| Coverage per tile | ~1,300 km² | ~36 km² |

**Nesting**: 6 × 6 = 36 L2 tiles per L1 tile

## Coverage

- **Longitude**: 44°E to 160°E (Australian Antarctic Territory)
- **Latitude**: 50°S to 70°S (UTM applicable range)
- **UTM Zones**: 42S through 58S
- **Coordinate System**: WGS84 / UTM Southern Hemisphere
- **Grid Origin**: Aligned with Sentinel-2 (166021, 0) per zone

## Key Locations

| Location | Coordinates | UTM Zone | Example L1 Tile |
|----------|-------------|----------|-----------------|
| Heard Island | 73.5°E, 53.0°S | 43S | 43S_L1_0006_0114 |
| Macquarie Island | 158.85°E, 54.6°S | 57S | 57S_L1_0009_0109 |
| Davis Station | 77.97°E, 68.58°S | 43S | 43S_L1_0012_0066 |

## Tile ID Format

```
{zone}_{level}_{col}_{row}

Example: 43S_L1_0006_0114
         │   │   │     │
         │   │   │     └─ Row index (4 digits)
         │   │   └─────── Column index (4 digits)
         │   └─────────── Grid level (L1 or L2)
         └─────────────── UTM zone (number + S)
```

## Common Operations

### 1. Coordinate to Tile Index
```r
# Given UTM coordinates (x, y) and grid origin
col = floor((x - origin_x) / tile_size)
row = floor((y - origin_y) / tile_size)
```

### 2. Tile Index to Bounding Box
```r
# For tile at (col, row)
xmin = origin_x + (col × tile_size)
ymin = origin_y + (row × tile_size)
xmax = xmin + tile_size
ymax = ymin + tile_size
```

### 3. Child to Parent (L2 → L1)
```r
L1_col = floor(L2_col / 6)
L1_row = floor(L2_row / 6)
```

### 4. Parent to Children (L1 → L2)
```r
# All child tiles for L1 tile at (col, row)
L2_cols = col × 6 to col × 6 + 5
L2_rows = row × 6 to row × 6 + 5
# Total: 36 tiles
```

## R Code Examples

### Initialize System
```r
source("antarctic_grid_system.R")
zones <- define_utm_zones()
```

### Create Tile ID
```r
tile_id <- make_tile_id("43S", "L1", 6, 114)
# Result: "43S_L1_0006_0114"
```

### Get Parent Tile
```r
parent <- get_parent_tile(l2_col = 38, l2_row = 687)
# Result: col = 6, row = 114
```

### Get Child Tiles
```r
children <- get_child_tiles(l1_col = 6, l1_row = 114)
# Result: 36 rows with col and row indices
```

### Generate Tiles for Region
```r
source("generate_tile_grids.R")

# Define bounding box (lon/lat)
bbox <- c(xmin = 72.5, ymin = -53.5, xmax = 74.0, ymax = -52.5)

# Generate tiles
tiles_l1 <- generate_tiles_for_bbox(bbox, "L1", zones)
tiles_l2 <- generate_tiles_for_bbox(bbox, "L2", zones)
```

## File Locations

| File | Purpose |
|------|---------|
| `antarctic_grid_system.R` | Core grid definitions and indexing |
| `generate_tile_grids.R` | Tile generation for regions |
| `demo_standalone.R` | Demonstration (no dependencies) |
| `demo_grid_system.R` | Full demo (requires sf package) |
| `README.md` | Complete documentation |
| `visualize_grid.py` | Generate visualization diagrams |

## Grid Origin per Zone

All zones use **Sentinel-2 standard origin**:
- X (Easting): 166,021 m
- Y (Northing): 0 m (at equator, adjusted for southern hemisphere)

This ensures compatibility with existing Sentinel-2 tile references.

## Coordinate Reference Systems (EPSG Codes)

| Zone | EPSG Code | Central Meridian |
|------|-----------|------------------|
| 42S | EPSG:32742 | 69°E |
| 43S | EPSG:32743 | 75°E |
| 44S | EPSG:32744 | 81°E |
| 45S | EPSG:32745 | 87°E |
| 46S | EPSG:32746 | 93°E |
| 47S | EPSG:32747 | 99°E |
| ... | ... | ... |
| 57S | EPSG:32757 | 159°E |
| 58S | EPSG:32758 | 165°E |

Formula: `Central Meridian = -183 + (zone_number × 6)`

## Design Decisions Summary

1. **Tile Sizes (36km/6km)**
   - Clean 6:1 nesting ratio
   - Human-viewable 600×600 pixel images
   - Practical coverage areas

2. **Resolutions (60m/10m)**
   - Compatible with common satellite data
   - 6:1 ratio matches spatial nesting
   - Heard Island = convenient reference unit

3. **Sentinel-2 Alignment**
   - Established standard in remote sensing
   - Existing tool support
   - Easy data integration

4. **UTM vs Polar Projection**
   - UTM valid to ~70°S
   - Minimal distortion in target area
   - Future: consider polar stereographic for far south

## Performance Notes

- **Small regions** (<100 tiles): Instant
- **Heard Island region**: ~10 L1 tiles, ~360 L2 tiles
- **Full AAT**: Thousands of tiles (generate once, cache)

## Next Steps

1. ✅ Grid specification complete
2. ⏭️ Define land/ice masks
3. ⏭️ Generate complete AAT tile catalog
4. ⏭️ Develop imagery rendering pipeline
5. ⏭️ Integrate with data sources
6. ⏭️ Create web tile service

## Resources

- Full documentation: `README.md`
- Visual diagrams: `grid_system_overview.png`, `grid_nesting_detail.png`
- Demo script: `demo_standalone.R` (run with: `Rscript demo_standalone.R`)

---

**Version**: 1.0 | **Date**: November 2025
