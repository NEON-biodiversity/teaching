# All the raw R code from 'Graduate lab: Testing macroecological predictions with NEON'
# author: qdr
# date: June 13, 2018


#############################################################################################################################

# R functions for pulling NEON data from the server

## Function to display what data are available

# This function takes a NEON product code `productCode` as an argument, gets a list of the files that are available, and displays a representative set of file names from one site-month combination.

display_neon_filenames <- function(productCode) {
  require(httr)
  require(jsonlite)
  req <- GET(paste0("http://data.neonscience.org/api/v0/products/", productCode))
  avail <- fromJSON(content(req, as = 'text'), simplifyDataFrame = TRUE, flatten = TRUE)
  urls <- unlist(avail$data$siteCodes$availableDataUrls)
  get_filenames <- function(x) fromJSON(content(GET(x), as = 'text'))$data$files$name
  files_test <- sapply(urls, get_filenames, simplify = FALSE)
  files_test[[which.max(sapply(files_test,length))]]
}

## Function to pull all data for a given data product

# The first argument, `productCode` is a NEON product code, and the second, `nametag`, is an identifying string that tells the function which CSV to download for each site-month combination. There are usually a lot of metadata files that we aren't interested in for now that go along with the main data file for each site-month combination, and the `nametag` argument tells the function which file is the one that really has the data we want (details below). The `pkg` argument defaults to download the "basic" data package which is usually all we would want. Finally, the `bind` argument defaults to `TRUE` which means return a single data frame, not a list of data frames.

# There are two steps to what the function does: first it queries the API to get a list of URLs of the CSV files available for all site-month combinations for the desired data product. Second it loops through the subset of those URLs that match the `nametag` argument and tries to download them all. If one gives an error, there is a `try()` function built in so that the function will just skip that file instead of quitting.

pull_all_neon_data <- function(productCode, nametag, pkg = 'basic', bind = TRUE) {
  require(httr)
  require(jsonlite)
  require(dplyr)
  
  # Get list of URLs for all site - month combinations for that data product.
  req <- GET(paste0("http://data.neonscience.org/api/v0/products/", productCode))
  avail <- fromJSON(content(req, as = 'text'), simplifyDataFrame = TRUE, flatten = TRUE)
  urls <- unlist(avail$data$siteCodes$availableDataUrls)
  
  # Loop through and get the data from each URL.
  res <- list()
  
  pb <- txtProgressBar(min=0, max=length(urls), style=3)
  count <- 0
  
  for (i in urls) {
    count <- count + 1
    setTxtProgressBar(pb, count)
    # Get the URLs for the site-month combination
    req_i <- GET(i)
    files_i <- fromJSON(content(req_i, as = 'text'))
    urls_i <- files_i$data$files$url
    # Read data from the URLs given by the API, skipping URLs that return an error.
    data_i <- try(read.delim(
      grep(paste0('(.*',nametag,'.*', pkg, '.*)'), urls_i, value = TRUE), 
      sep = ',', stringsAsFactors = FALSE), TRUE)
    if (!inherits(data_i, 'try-error')) res[[length(res) + 1]] <- data_i
  }
  
  close(pb)
  
  # Return as a single data frame or as a list of data frames, 
  # depending on what option was selected.
  if (bind) {
    do.call(rbind, res)
  } else {
    res
  }
}

## Function to get spatial information (coordinates) for a site or plot

# The spatial locations and metadata for sites and plots are stored in a different location on NEON's API from the actual data. This function should be called for a single site at a time (`siteID` argument). The second argument, `what`, is a string. The default is `"site"` which will return a single row of a data frame with spatial location for the entire site as a single point. If `what` is set to another string such as `"bird"` it will go through the spatial location data URLs, find all that have `"bird"` in the name, pull the spatial information from them, and return a data frame with one row per bird plot. In either case the data frame has 19 columns (the number of location attributes NEON has listed for each site or plot).

get_site_locations <- function(siteID, what = 'site') {
  require(httr)
  require(jsonlite)
  require(purrr)
  # URLs of all spatial information about the site
  req <- GET(paste0("http://data.neonscience.org/api/v0/locations/", siteID))
  site_loc <- fromJSON(content(req, as = 'text'), simplifyDataFrame = TRUE, flatten = TRUE)
  
  if (what == 'site') {
    # If only coordinates of the entire site are needed, return them
    return(data.frame(site_loc$data[1:19]))
  } else {
    # If "what" is some type of plot, find all URLs for that plot type
    urls <- grep(what, site_loc$data$locationChildrenUrls, value = TRUE)
    # Get the coordinates for each of those plots from each URL and return them
    loc_info <- map_dfr(urls, function(url) {
      req <- GET(url)
      loc <- fromJSON(content(req, as = 'text'), simplifyDataFrame = TRUE, flatten = TRUE)
      loc[[1]][1:19]
    })
    return(loc_info)
  }
}

#############################################################################################################################

# Downloading mammal and bird data

# You can look in the data product catalog and manually figure out what the product codes are for small mammal trap data and for bird point count data, but I've provided them here. The `DP1` in the code indicates that this is Level 1 data. For Level 1 data, quality controls were run (Level 0 would be `DP0` meaning completely raw data) but the actual values are still raw values measured in the field, not some kind of calculated quantity (Level 2 and higher would be derived values).

mammal_code <- 'DP1.10072.001'
bird_code <- 'DP1.10003.001'

## Mammal download

# Let's take a look at what files are available for NEON small mammal trapping data for a given site-month combination. Running this takes a minute or two and requires an internet connection because we are querying the API.

display_neon_filenames(mammal_code)

# You can see that there are a lot of files available for one site. However the one we are interested in is the file containing the mammals caught per trap per night in the basic data package (expanded data package contains other variables that might be needed for quality control but that we are not interested in here). Let's pull that CSV file for all site-month combinations and combine it into one huge data frame that we can run analysis on. We specify we want everything belonging to the mammal code that contains the string `pertrapnight` in the file name, and by default only get the basic data package. Running this code on your own machine will take quite a few minutes since it has to download a lot of data, but you should get a progress bar showing how much time is remaining.

mammal_data <- pull_all_neon_data(productCode = mammal_code, 
                                  nametag = 'pertrapnight')

# Now let's take a look at what is in that data frame . . . 

str(mammal_data)

## Bird data

# Next, let's look at what data are available for birds.

display_neon_filenames(bird_code)

# Since the string `count` is in the name of the data file that we want for each site-month combination (the raw point count data for birds), we use that to pull point count data for each month and stick it all into one big data frame.

bird_data <- pull_all_neon_data(productCode = bird_code, 
                                nametag = 'count')

# Let's see what is in that data frame . . . 

str(bird_data)

#############################################################################################################################

# Making maps with NEON data

## Map within a single site

# First, let's make a map of bird species richness within one of the NEON sites. There are multiple bird survey grids at a site. As an example, we will use the Oak Ridge National Laboratory (ORNL) site. First, let's find the species richness at each bird plot at that site by taking the subset of the bird data from ORNL, grouping by plot, and counting the number of unique taxon IDs.

library(ggplot2)

(bird_ornl <- bird_data %>% 
  filter(siteID %in% 'ORNL') %>%
  group_by(plotID) %>%
  summarize(richness = length(unique(taxonID))))

# We have 13 plots with varying species richness. Unfortunately, the coordinates of the plots are not included in the bird data. The plot metadata must be pulled separately from the API for each site. Here, I get the locations for all bird survey grids at Oak Ridge, then join them with the richness data.

bird_ornl_locations <- get_site_locations(siteID = 'ORNL', what = 'bird')

# The location names are given as a long string so we need to extract the substring before the first period to join the locations with the richness values. We are using the base R function `strsplit()` to split the string on each period, and the `map_chr()` function from the package `purrr` to pull the first item out of each list element returned by `strsplit()`. Since `strsplit()` returns a list, `map_chr()` helps us transform the result of splitting the string back into a vector that becomes a data frame column.

bird_ornl_locations$locationName[1:3]

library(purrr)

bird_ornl <- bird_ornl_locations %>%
  mutate(locationName = map_chr(strsplit(locationName, '\\.'), 1)) %>%
  rename(plotID = locationName) %>%
  right_join(bird_ornl)

dim(bird_ornl)
names(bird_ornl)

# There are now a lot of useful spatial columns along with richness for each of the bird plots at Oak Ridge. Let's make a map with each plot represented by a point colored by the bird species richness there, and labeled with the elevation rounded to the nearest meter for good measure. 

ggplot(bird_ornl, 
       aes(x = locationUtmEasting, y = locationUtmNorthing)) +
  geom_point(aes(color = richness), size = 3) +
  # The vjust argument below moves the text down slightly.
  geom_text(aes(label = paste(round(locationElevation), 'm')), vjust = 1.2) +
  scale_color_gradient(low = 'blue', high = 'red') +
  theme_bw()

# So we've made a map of how bird richness varies spatially within the boundaries of the Oak Ridge study site. As an exercise, subset the bird data for a different site and make a map of a different variable such as the total number of individual birds observed at each survey grid in a particular year.

## Map of all sites in the contiguous USA

# It might also be interesting to plot bird richness across the United States. While before we used the projected coordinates provided by NEON, here we can use the latitudes and longitudes, then use the mapping capability of `ggplot2` to draw a map with our preferred projection.

# First, find the species richness at each site by counting the number of unique taxa.

bird_richness <- bird_data %>%
  group_by(siteID) %>%
  summarize(richness = length(unique(taxonID)))

# Next we need to pull the site centroids in lat-long for all the sites in the bird richness dataset. We do this by accessing the API again. A function from `purrr` called `map_dfr()` helps us loop through all the sites, get the overall location info, and tidily store it in a single data frame that we can easily join with the richness data frame.

site_coordinates <- map_dfr(bird_richness$siteID, get_site_locations, what = 'site')

bird_richness <- site_coordinates %>%
  rename(siteID = locationName) %>%
  right_join(bird_richness)

# Alaska and Puerto Rico are included here; we can get rid of them by filtering on latitude. *This simplifies making the map for now, since including insets for Alaska, etc. adds a lot of nuisance steps to making the map. But never fear, it can be done! If there is interest we can add that step to a future version of this tutorial.*

bird_richness <- bird_richness %>%
  filter(between(locationDecimalLatitude, 25, 50))

# Create a map using the built-in US state borders, with site points colored by bird species richness. Use the `coord_map()` function to specify a projection. The Albers equal-area projection with arguments `lat0 = 23` and `lat1 = 30` is ideal for mapping the continental USA. We also use `coord_map()` to specify the range of latitude and longitude to plot.  The `borders('state')` and `borders('world')` elements add the state borders and the borders of Canada and Mexico, respectively.

ggplot(bird_richness, 
       aes(x = locationDecimalLongitude, y = locationDecimalLatitude, fill = richness)) +
  borders('state') +
  borders('world') +
  geom_point(pch = 21, size = 3) +
  scale_fill_gradient(low = 'blue', high = 'red') +
  theme_bw() +
  coord_map(projection = 'albers', 
            lat0 = 23, 
            lat1 = 30, 
            xlim = c(-127, -65), 
            ylim = c(25,50))

# As an exercise, do the same for mammal richness and for elevation.

#############################################################################################################################

# Using NEON data to test hypotheses

## Bergmann's Rule

# Bergmann's rule is a famous macroecological pattern stating that average body sizes of (warm-blooded) animals should increase with increasing latitude. Bergmann, a physiologist working in the 19th century, speculated that animals living in colder areas further from the equator tend to be larger so that they have a smaller surface area to volume ratio and can more effectively retain heat. Later, people proposed additional mechanisms for why the pattern might exist. Also, some people even debated whether the pattern exists at all! **add more background material here**. Here, we tackle this question using the NEON small mammal dataset.

# NEON's mammal and bird data have latitudes for all the sites included in the data. Only the mammal data is suitable for testing Bergmann's rule because only the mammals are captured and weighed. 

### Processing data

# We should first find the mean body mass for each species at each site, along with their latitudes. We will use functions from the R package `dplyr` to quickly manipulate the data frame.

# The mammal data frame is huge, with over 600K rows. Most of the rows record trap-nights where no mammal was captured. Let's get rid of those.

library(dplyr)
nrow(mammal_data)
table(mammal_data$trapStatus)

# You can see that only status 4 and 5 correspond to one or more mammals caught in the trap. Filter the data frame to only keep those rows. We use the function `grepl()` which matches a regular expression to a vector of strings and returns `TRUE` if they match. The regular expression `"4|5"` means any string with the numerals 4 or 5 in it.

mammal_data <- mammal_data %>%
  filter(grepl('4|5', trapStatus))

nrow(mammal_data)

# We are down to ~70K rows where mammals were captured. Many of the mammals were not weighed so keep only the rows with a non-NA value for weight.

mammal_data <- mammal_data %>%
  filter(!is.na(weight))

nrow(mammal_data)

# We are down below 60K rows. Next, many records are for mammals where the same individual was captured multiple times. Keep only the rows where the recapture status is "N" for not a recapture.

mammal_data <- mammal_data %>%
  filter(recapture %in% 'N')

nrow(mammal_data)

# We are now at ~25K rows. Let's take the mean value of each species at each site, as well as the number of individuals used to calculate the mean, then get rid of any species-site combination with less than 5 individuals to ensure that we have a good estimate of the mean for all the species-site combinations.

mammal_means <- mammal_data %>%
  group_by(siteID, taxonID) %>%
  summarize(mean_mass = mean(weight), n_individuals = n()) %>%
  filter(n_individuals >= 5)

# In addition, we need to get rid of the species that are found at 2 or fewer sites because it is not robust to try to infer a trend within species from so few data points.

mammal_means <- mammal_means %>%
  ungroup %>%
  group_by(taxonID) %>%
  mutate(n_sites = length(siteID)) %>%
  filter(n_sites >= 3)

mammal_means

# We are left with 177 species-site combinations.

### Visualizing data

# Now that we have the mean value of body mass for each species and each site, let's make a scatterplot to visualize the pattern. We need to get the mean latitude value for each site and join it with our mean mass data frame so that we can plot mass versus latitude. Since all the sites are in the northern hemisphere, all latitude values are positive in the NEON dataset.

latitudes <- mammal_data %>%
  group_by(siteID) %>%
  summarize(latitude = mean(decimalLatitude))

mammal_means <- left_join(mammal_means, latitudes)

library(ggplot2)

p <- ggplot(mammal_means, aes(x = latitude, y = mean_mass, color = taxonID)) +
  geom_point() +
  theme_bw()

p

# That's hard to see any pattern in, so let's try looking at the y-axis on a log scale.

p + 
  scale_y_log10(name = 'Mass (g)')

# Still hard to see a pattern so just for visualization purposes, plot a separate simple linear regression for each species on the scatterplot.

p +
  scale_y_log10(name = 'Mass (g)') +
  stat_smooth(method = 'lm', aes(group = taxonID), se = FALSE)

### Testing the hypothesis

# From the last plot we made, it looks like a number of species have positive trends where body size increases with latitude moving away from the equator as Bergmann predicted. However there are clearly some exceptions, and a lot of the positive trends are pretty weak. That gives us a rough visual test of the hypothesis: I would argue we can say that it probably isn't supported or might have weak support at best from this small mammal dataset, but other people might have a different opinion.

# A formal way to test the hypothesis that body mass increases with latitude is to use a mixed-effects model. Our model will fit a random intercept to each species (because each species has its own characteristic mass) and use latitude as the fixed effect (it estimates a single slope of body mass change versus latitude change across all species). 

# First, let's confirm that the log transformation is a good idea by looking at histograms of the untransformed mass values as well as the log-transformed values.

p_hist <- ggplot(mammal_means, aes(x = mean_mass)) +
  geom_histogram(bins = 20) + 
  theme_bw() +
  scale_y_continuous(expand = c(0,0))

p_hist + scale_x_continuous(name = 'Untransformed mass (g)')

p_hist + scale_x_log10(name = 'Log10 transformed mass (g)')

# The untransformed values are highly skewed, with many small species and a long tail of large-bodied species. It seems appropriate to fit the model with log-transformed data.

# We will use the `lmer` function from the R package `lme4` to fit the mixed model.

library(lme4)

randomintercept_fit <- lmer(log10(mean_mass) ~ latitude + (1|taxonID), data = mammal_means)

summary(randomintercept_fit)

# The default summary information shows that the coefficient on latitude is positive but close to zero. We can generate a confidence interval on that coefficient by fitting the model many times with bootstrapped resamples of the original dataset. This takes a few seconds.

confint(randomintercept_fit, method = 'boot', nsim = 999)

# The confidence interval of the slope coefficient on latitude overlaps zero, meaning we have no support for the statement that there is any relationship between small mammal body mass and latitude, whether positive or negative.

# Another summary statistic we might be interested in is the variation explained by the fixed effect (latitude). A method was recently developed to partition that variation from the total variation and get an R-squared for it.

library(r2glmm)

r2beta(randomintercept_fit, method = 'kr', partial = FALSE)

# The R-squared is essentially zero, further confirming our intuition that there is no relationship.

### Exercises

# There are other ways to fit the model. For instance you could fit both a random intercept and a random slope to each species. You could also ignore the variation due to species entirely. As an exercise, try out some of those alternative ways of fitting the model. Do they have any effect on our inference?

# You might have noticed that we have ignored any body mass variation within a single species at a single site. As an additional exercise, fit a model including this individual variation. Does it have any effect on our inference?

# As a conceptual exercise, do some research on tests of Bergmann's rule in different taxonomic groups. Is there any consensus about what we would expect for small mammals such as rodents in particular? Has Bergmann's Rule stood the test of time?

### Further reading

# *Add content here.*