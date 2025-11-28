# Antarctic Grid System - Demonstration
# This script demonstrates the complete workflow using terra

library(terra)

source("antarctic_grid_system.R")
source("generate_tile_grids.R")

# ==============================================================================
# SETUP
# ==============================================================================

cat("Antarctic Territory Grid System\n")
cat("================================\n\n")

# Initialize the grid specification
zones <- define_utm_zones()
cat("Defined", nrow(zones), "UTM zones covering AAT\n")
cat("Zone range:", min(zones$zone_number), "to", max(zones$zone_number), "\n\n")

# Display grid parameters
cat("Grid Parameters:\n")
cat("  Level 1 (Coarse):\n")
cat("    - Tile size:", GRID_SPEC$L1$tile_size, "m\n")
cat("    - Resolution:", GRID_SPEC$L1$resolution, "m/pixel\n")
cat("    - Dimensions:", GRID_SPEC$L1$pixels, "x", GRID_SPEC$L1$pixels, "pixels\n\n")

cat("  Level 2 (Fine):\n")
cat("    - Tile size:", GRID_SPEC$L2$tile_size, "m\n")
cat("    - Resolution:", GRID_SPEC$L2$resolution, "m/pixel\n")
cat("    - Dimensions:", GRID_SPEC$L2$pixels, "x", GRID_SPEC$L2$pixels, "pixels\n\n")

cat("  Nesting:", GRID_SPEC$nesting_factor, "x", GRID_SPEC$nesting_factor, 
    "=", GRID_SPEC$nesting_factor^2, "L2 tiles per L1 tile\n\n")

# ==============================================================================
# EXAMPLE 1: TILE INDEXING
# ==============================================================================

cat("Example 1: Tile Indexing\n")
cat("------------------------\n")

# Example coordinates (Heard Island approximate center)
example_lon <- 73.5
example_lat <- -53.0
cat("Location:", example_lon, "°E,", example_lat, "°S\n")

# Determine UTM zone
zone_num <- floor((example_lon + 180) / 6) + 1
example_zone <- zones[zones$zone_number == zone_num, ]
cat("UTM Zone:", example_zone$zone_id, "(", example_zone$epsg, ")\n")

# Convert to UTM
point_lonlat <- st_sfc(st_point(c(example_lon, example_lat)), crs = 4326)
point_utm <- st_transform(point_lonlat, example_zone$epsg)
coords_utm <- st_coordinates(point_utm)

cat("UTM coordinates:", round(coords_utm[1]), "E,", round(coords_utm[2]), "N\n")

# Get tile indices
l1_idx <- utm_to_tile_index(coords_utm[1], coords_utm[2], "L1",
                            example_zone$origin_x, example_zone$origin_y)
l2_idx <- utm_to_tile_index(coords_utm[1], coords_utm[2], "L2",
                            example_zone$origin_x, example_zone$origin_y)

cat("L1 tile index: col =", l1_idx$col, ", row =", l1_idx$row, "\n")
cat("L2 tile index: col =", l2_idx$col, ", row =", l2_idx$row, "\n")

# Create tile IDs
l1_id <- make_tile_id(example_zone$zone_id, "L1", l1_idx$col, l1_idx$row)
l2_id <- make_tile_id(example_zone$zone_id, "L2", l2_idx$col, l2_idx$row)

cat("L1 tile ID:", l1_id, "\n")
cat("L2 tile ID:", l2_id, "\n\n")

# ==============================================================================
# EXAMPLE 2: NESTING RELATIONSHIPS
# ==============================================================================

cat("Example 2: Tile Nesting\n")
cat("-----------------------\n")

# Get parent of L2 tile
parent <- get_parent_tile(l2_idx$col, l2_idx$row)
cat("Parent of", l2_id, "is:\n")
parent_id <- make_tile_id(example_zone$zone_id, "L1", parent$col, parent$row)
cat(" ", parent_id, "\n")

# Verify it matches
if (parent$col == l1_idx$col && parent$row == l1_idx$row) {
  cat("  ✓ Matches the L1 tile containing our point\n")
}

# Get all children of this L1 tile
children <- get_child_tiles(l1_idx$col, l1_idx$row)
cat("\nChildren of", l1_id, ":\n")
cat("  Total:", nrow(children), "tiles (6x6 grid)\n")
cat("  Column range:", min(children$col), "to", max(children$col), "\n")
cat("  Row range:", min(children$row), "to", max(children$row), "\n\n")

# ==============================================================================
# EXAMPLE 3: GENERATE TILES FOR A REGION
# ==============================================================================

cat("Example 3: Generate Tiles for Heard Island\n")
cat("-------------------------------------------\n")

regions <- get_aat_regions()
heard_bbox <- regions$heard_mcdonald

cat("Bounding box:", 
    heard_bbox["xmin"], "to", heard_bbox["xmax"], "°E,",
    heard_bbox["ymin"], "to", heard_bbox["ymax"], "°S\n")

# Generate tiles
cat("\nGenerating L1 tiles...\n")
heard_l1 <- generate_tiles_for_bbox(heard_bbox, "L1", zones)

cat("Generating L2 tiles...\n")
heard_l2 <- generate_tiles_for_bbox(heard_bbox, "L2", zones)

cat("\nResults:\n")
cat("  L1 tiles:", nrow(heard_l1), "\n")
cat("  L2 tiles:", nrow(heard_l2), "\n")
cat("  Ratio:", round(nrow(heard_l2) / nrow(heard_l1), 1), 
    "(expected: 36 if all fully nested)\n")

# Show some tile IDs
cat("\nFirst few L1 tiles:\n")
print(head(heard_l1$tile_id, 5))

cat("\nFirst few L2 tiles:\n")
print(head(heard_l2$tile_id, 5))

# ==============================================================================
# EXAMPLE 4: COVERAGE SUMMARY
# ==============================================================================

cat("\n")
cat("Example 4: Coverage Summary\n")
cat("---------------------------\n")

# Calculate area covered
l1_area_km2 <- nrow(heard_l1) * (GRID_SPEC$L1$tile_size / 1000)^2
l2_area_km2 <- nrow(heard_l2) * (GRID_SPEC$L2$tile_size / 1000)^2

cat("Area coverage:\n")
cat("  L1 grid:", round(l1_area_km2), "km² (", nrow(heard_l1), 
    "tiles ×", GRID_SPEC$L1$tile_size/1000, "km)\n")
cat("  L2 grid:", round(l2_area_km2), "km² (", nrow(heard_l2), 
    "tiles ×", GRID_SPEC$L2$tile_size/1000, "km)\n")

cat("\nTotal pixels if all tiles rendered:\n")
cat("  L1:", nrow(heard_l1) * GRID_SPEC$L1$pixels^2, "pixels\n")
cat("  L2:", nrow(heard_l2) * GRID_SPEC$L2$pixels^2, "pixels\n")

# ==============================================================================
# EXAMPLE 5: TILE METADATA
# ==============================================================================

cat("\n")
cat("Example 5: Tile Metadata\n")
cat("------------------------\n")

# Create a catalog for one tile
example_tile <- heard_l1[1, ]
cat("Tile:", example_tile$tile_id, "\n")
cat("Zone:", example_tile$zone_id, "\n")
cat("Index: col =", example_tile$col, ", row =", example_tile$row, "\n")

bbox <- st_bbox(example_tile)
cat("Bounding box (UTM):\n")
cat("  X:", round(bbox["xmin"]), "to", round(bbox["xmax"]), "\n")
cat("  Y:", round(bbox["ymin"]), "to", round(bbox["ymax"]), "\n")

# Transform to lon/lat
tile_lonlat <- st_transform(example_tile, 4326)
bbox_lonlat <- st_bbox(tile_lonlat)
cat("Bounding box (Lon/Lat):\n")
cat("  Lon:", round(bbox_lonlat["xmin"], 3), "to", 
    round(bbox_lonlat["xmax"], 3), "°E\n")
cat("  Lat:", round(bbox_lonlat["ymin"], 3), "to", 
    round(bbox_lonlat["ymax"], 3), "°S\n")

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("\n")
cat("System Summary\n")
cat("==============\n")
cat("The grid system is ready for:\n")
cat("  • Generating tile sets for any AOI\n")
cat("  • Converting between coordinates and tile IDs\n")
cat("  • Navigating parent-child relationships\n")
cat("  • Exporting to standard formats (GeoPackage, Shapefile, etc.)\n")
cat("  • Integration with imagery processing pipelines\n\n")

cat("Next steps:\n")
cat("  1. Define land/ice masks to filter tiles\n")
cat("  2. Generate complete tile sets for all AAT regions\n")
cat("  3. Create a tile catalog/index\n")
cat("  4. Develop imagery rendering workflow\n\n")
