# Package startup

.onAttach <- function(libname, pkgname) {
  packageStartupMessage("aatgrid: Antarctic Territory Grid System")
  packageStartupMessage("Parametric grid: origin + 600px tiles + resolution (L1=60m, L2=10m aliases)")
  packageStartupMessage("Use define_utm_zones() to get started")

  get_map <- memoise::memoize(get_map)
}
