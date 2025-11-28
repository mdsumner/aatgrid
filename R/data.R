# Package data and constants

#' Grid Specification Parameters
#'
#' Defines the two-level hierarchical grid system used for the Antarctic
#' Territory Grid System.
#'
#' @format A list with two levels:
#' \describe{
#'   \item{L1}{Coarse grid specifications:
#'     \itemize{
#'       \item tile_size: 36000 meters (36 km)
#'       \item resolution: 60 meters per pixel
#'       \item pixels: 600 x 600 pixels per tile
#'     }
#'   }
#'   \item{L2}{Fine grid specifications:
#'     \itemize{
#'       \item tile_size: 6000 meters (6 km)
#'       \item resolution: 10 meters per pixel
#'       \item pixels: 600 x 600 pixels per tile
#'     }
#'   }
#'   \item{nesting_factor}{6 - each L1 tile contains 6x6 L2 tiles}
#' }
#' @export
GRID_SPEC <- list(
  # Level 1: Coarse grid
  L1 = list(
    tile_size = 36000,      # meters (36 km)
    resolution = 60,        # meters per pixel
    pixels = 600            # 600 x 600 pixels
  ),
  
  # Level 2: Fine grid  
  L2 = list(
    tile_size = 6000,       # meters (6 km)
    resolution = 10,        # meters per pixel
    pixels = 600            # 600 x 600 pixels
  ),
  
  # Nesting relationship
  nesting_factor = 6        # 6x6 L2 tiles per L1 tile
)
