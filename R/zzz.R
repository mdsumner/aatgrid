# Package hooks

.onLoad <- function(libname, pkgname) {
  # Memoise the coastline/bathymetry context fetcher. This must happen
  # in .onLoad (namespace still unsealed) and must rebind the namespace
  # object with <<-; a local assignment here would be a silent no-op.
  get_map <<- memoise::memoise(get_map)
  invisible()
}

.onAttach <- function(libname, pkgname) {
  packageStartupMessage("aatgrid: Antarctic Territory Grid System")
  packageStartupMessage(
    "Parametric grid: origin ", GRID_ORIGIN[["x"]], "/", GRID_ORIGIN[["y"]],
    " + ", PIXELS_PER_TILE, "px tiles + resolution (L1=60m, L2=10m aliases)"
  )
}
