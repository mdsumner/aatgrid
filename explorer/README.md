# aatgrid explorer

A static page that draws the aatgrid tile lattice on UTM south zones over the
Australian Antarctic Territory coast. Published by `.github/workflows/pages.yml`
to `https://mdsumner.github.io/aatgrid/explorer/`.

Files:

- `index.html`: page and styles.
- `app.js`: grid arithmetic (mirrors `R/antarctic_grid_system.R` and
  `R/bounds_materialize.R`), rendering, imagery and interaction.
- `utm.js`: UTM south forward/inverse (Kruger n-series, Karney 2011); agrees
  with PROJ to under 0.1 mm, including 48 degrees off the central meridian.
- `coast/`: land (geoBoundaries CGAZ ADM0, unsimplified) and ice shelves
  (Natural Earth 10m) south of 45S, as 2-degree strips in 10-degree sector
  files with an `index.json`. The page fetches only the sectors the current
  zone can show. Rebuild with `data-raw/explorer_coast.py`, which records the
  pinned inputs.

What each zone shows: everything south of 45S, within 90 degrees of the
zone's central meridian, where the zone's transverse Mercator scale factor
stays under a chosen limit (5, 10, 20 or 40 percent). Scale factor is about
1 / sqrt(1 - B^2) with B = cos(lat) sin(dlon), so the view is a narrow band
at 45S that opens to half the continent near the pole. At 20 percent, zone
46S shows the whole AAT coast plus Heard and Macquarie.

Imagery: Esri World Imagery or OpenStreetMap tiles are drawn with WebGL. Each
Web Mercator tile becomes a 16 x 16 mesh whose vertices are projected into the
current UTM zone, so the imagery is reprojected on the GPU rather than
resampled. Tiles south of 85.05S do not exist in Web Mercator. Attribution is
shown on the map while a tile source is on.

Grid defaults are origin 140000 / 20000, 720 px tiles and resolutions 10, 20,
60. The page lets you switch tile size and origin, so it can show both the
v0.2.0 (600 px) and the 720 px scheme.

Run locally: `python3 -m http.server -d explorer` and open
http://localhost:8000. Opening `index.html` as a file will not load the
coastline.
