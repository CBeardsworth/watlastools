#' A fast way to calculate euclidean distances between successive points.
#'
#' @param x A column name in a data.frame object that contains the numeric X or longitude coordinate for position data.
#' @param y A column name in a data.frame object that contains the numeric Y or latitude coordinate for position data.
#' @param df A dataframe object of or extending the class data.frame, which must contain at least two coordinate columns for the X and Y coordinates.
#'
#' @return Returns a vector of distances between consecutive points.
#' @export
#'
wat_simple_dist <- function(df, x = "x", y = "y"){
  #check for basic assumptions
  assertthat::assert_that(is.data.frame(df),
                          is.character(x),
                          is.character(y),
                          msg = "simpleDist: some df assumptions are not met")

  dist <- dplyr::case_when(nrow(df) > 1 ~
                             # cases where sufficient data
                             {
                               {
                                 x1 <- df[[x]][1:nrow(df)-1]
                                 x2 <- df[[x]][2:nrow(df)]
                               }
                               {
                                 y1 <- df[[y]][1:nrow(df)-1]
                                 y2 <- df[[y]][2:nrow(df)]
                               }

                               # get dist
                               c(NA, sqrt((x1 - x2)^2 + (y1 - y2)^2))
                             },
                           nrow(df) == 1 ~ {0.0},
                           TRUE ~ {as.numeric(NA)})

  return(dist)
}

#### a function for patch end to patch start distances ####
