# aatgrid

R package for working with grids in the Australian Antarctic region.

https://github.com/mdsumner/aatgrid

## Development
- Use the content here in R/ and examples throughout purely as a visible benchmark, I want to reuse facilities that are already here when they match
the guidelines, but otherwise we can ignore other content. 

## Structure
- R/ contains all functions relevant to our benchmark. 
- ignore creating tests for now, we will work in a single script that uses other packages (see Style) and any helpers we deem fit to exist here. 

## Style
- snake_case for functions
- Use dplyr idioms but with package-safe practices (use of globalVariables, or rlang::.data)
- Use gdalraster, hypertidy/geographiclib, hypertidy/vaster in favour of other spatial packages. 
- Always use indexing-first tricks, rather than explicit spatial files or structures. I.e. a raster domain is extent+dimension+crs, and a structure
for plotting a raster grid is a matrix or data frame of xmin,xmax,ymin,ymax plotted with vaster::plot_extent or rect()
- Use do.call(cbind, maps::map(plot = F)[1:2]) to obtain raw coastline data to be projected or just maps(add = TRUE) to add context to a longlat map

## workplan 

We will discuss and implement a series of grid and map projection examples to describe use of projections in the Australian Antarctic domain. 


