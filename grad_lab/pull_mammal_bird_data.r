# Pull neon mammal and bird data from API
# QDR 11 May 2018

# Source functions to pull data
source('~/GitHub/NEON/code/data_extraction/datapull_neonapi_fns.r')

# Codes for mammal and bird data
mammal_code <- 'DP1.10072.001'
bird_code <- 'DP1.10003.001'

# Pull all mammal data
mammal_data <- pull_all_neon_data(productCode = mammal_code, nametag = 'pertrapnight')

# Pull all bird data
bird_data <- pull_all_neon_data(productCode = bird_code, nametag = 'count')