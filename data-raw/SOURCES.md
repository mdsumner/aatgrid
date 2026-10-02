# Data sources

External data used to build aatgrid fixtures. Large files are not in git;
they are mirrored as GitHub release assets and fetched by scripts in
`data-raw/`. Each entry records where the file came from, exactly which
bytes we hold, and how to get them again.

## SCAR Antarctic Digital Database: high resolution coastline polygons

| Field            | Value |
|------------------|-------|
| Dataset          | High resolution vector polygons of the Antarctic coastline |
| Version          | 7.10 |
| Publisher        | British Antarctic Survey, for SCAR (Antarctic Digital Database) |
| Landing page     | https://data.bas.ac.uk/items/4ecd795d-e038-412f-b430-251b33fc880e/ |
| DOI              | FILL: copy from the landing page citation |
| Citation         | FILL: copy the landing page citation verbatim |
| Licence          | CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/) |
| Published        | 2024-11-12 (per landing page) |
| Accessed         | 2026-09-29, downloaded by hand (the catalogue uses keyed download URLs) |
| Original file    | FILL: file name exactly as downloaded |
| Format           | GeoPackage |
| CRS              | EPSG:3031 |
| Coverage         | Land and ice shelves south of 60S. Does not include Heard/McDonald or Macquarie. |
| Size (bytes)     | FILL |
| sha256           | FILL |
| md5              | FILL (verified by `data-raw/fetch_add.R`, base R only) |
| Mirror tag       | `add-v7.10` |
| Mirror URL       | https://github.com/mdsumner/aatgrid/releases/download/add-v7.10/FILL_FILENAME |

Contents (from `ogrinfo -so`, recorded at mirror time):

```
FILL: paste layer name(s), feature count, geometry type, field list
```

Notes:

- The mirror is byte-identical to the download. We do not modify, reproject
  or rename the file. Derived products (arcs, ranks, tile classification)
  are built from it and carry `source = "ADD"`, `source_version = "7.10"`.
- Attribution required by CC BY 4.0: any product derived from this file
  cites the dataset above and states that changes were made.


sha256sum add_coastline_high_res_polygon_v7_10.gpkg
cebee398d4df4a8646946c8c881a1807a141ab0caedf604897fea0424dd72f67  add_coastline_high_res_polygon_v7_10.gpkg
md5sum add_coastline_high_res_polygon_v7_10.gpkg
20609e485621015cf247326445f408dc  add_coastline_high_res_polygon_v7_10.gpkg
stat -c %s add_coastline_high_res_polygon_v7_10.gpkg
143675392
ogrinfo -so -al add_coastline_high_res_polygon_v7_10.gpkg | head -40
INFO: Open of `add_coastline_high_res_polygon_v7_10.gpkg'
      using driver `GPKG' successful.

Layer name: add_coastline_high_res_polygon_v7_10
Metadata:
  GPKG_METADATA_ITEM_1=<!DOCTYPE qgis PUBLIC 'http://mrcc.com/qgis.dtd' 'SYSTEM'>
<qgis version="3.34.7-Prizren">
  <identifier>add_coastline_high_res_polygon_v7_10</identifier>
  <parentidentifier></parentidentifier>
  <language>ENG</language>
  <type>dataset</type>
  <title>add_coastline_high_res_polygon_v7_10</title>
  <abstract></abstract>
  <links/>
  <dates/>
  <fees></fees>
  <encoding></encoding>
  <crs>
    <spatialrefsys nativeFormat="Wkt">
      <wkt>PROJCRS["WGS 84 / Antarctic Polar Stereographic",BASEGEOGCRS["WGS 84",ENSEMBLE["World Geodetic System 1984 ensemble",MEMBER["World Geodetic System 1984 (Transit)"],MEMBER["World Geodetic System 1984 (G730)"],MEMBER["World Geodetic System 1984 (G873)"],MEMBER["World Geodetic System 1984 (G1150)"],MEMBER["World Geodetic System 1984 (G1674)"],MEMBER["World Geodetic System 1984 (G1762)"],MEMBER["World Geodetic System 1984 (G2139)"],ELLIPSOID["WGS 84",6378137,298.257223563,LENGTHUNIT["metre",1]],ENSEMBLEACCURACY[2.0]],PRIMEM["Greenwich",0,ANGLEUNIT["degree",0.0174532925199433]],ID["EPSG",4326]],CONVERSION["Antarctic Polar Stereographic",METHOD["Polar Stereographic (variant B)",ID["EPSG",9829]],PARAMETER["Latitude of standard parallel",-71,ANGLEUNIT["degree",0.0174532925199433],ID["EPSG",8832]],PARAMETER["Longitude of origin",0,ANGLEUNIT["degree",0.0174532925199433],ID["EPSG",8833]],PARAMETER["False easting",0,LENGTHUNIT["metre",1],ID["EPSG",8806]],PARAMETER["False northing",0,LENGTHUNIT["metre",1],ID["EPSG",8807]]],CS[Cartesian,2],AXIS["(E)",north,MERIDIAN[90,ANGLEUNIT["degree",0.0174532925199433]],ORDER[1],LENGTHUNIT["metre",1]],AXIS["(N)",north,MERIDIAN[0,ANGLEUNIT["degree",0.0174532925199433]],ORDER[2],LENGTHUNIT["metre",1]],USAGE[SCOPE["Antarctic Digital Database and small scale topographic mapping."],AREA["Antarctica."],BBOX[-90,-180,-60,180]],ID["EPSG",3031]]</wkt>
      <proj4>+proj=stere +lat_0=-90 +lat_ts=-71 +lon_0=0 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs</proj4>
      <srsid>996</srsid>
      <srid>3031</srid>
      <authid>EPSG:3031</authid>
      <description>WGS 84 / Antarctic Polar Stereographic</description>
      <projectionacronym>stere</projectionacronym>
      <ellipsoidacronym>EPSG:7030</ellipsoidacronym>
      <geographicflag>false</geographicflag>
    </spatialrefsys>
  </crs>
  <extent/>
</qgis>

Geometry: Multi Polygon
Feature Count: 17716
Extent: (-2662876.092600, -2494398.475000) - (2750744.405400, 2327576.127219)
Layer SRS WKT:
PROJCRS["WGS 84 / Antarctic Polar Stereographic",
    BASEGEOGCRS["WGS 84",
        ENSEMBLE["World Geodetic System 1984 ensemble",

#sha256sum add_coastline_high_res_polygon_v7_10.gpkg > SHA256SUMS
