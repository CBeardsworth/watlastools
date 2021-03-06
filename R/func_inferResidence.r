#' Infer residence patches from gaps in the canonical data.
#'
#' @param df A dataframe of recurse analysis, or must include, in addition to x, y and time columns, a residence time column named resTime, id, and tide_number, a tidaltime column named tidaltime.
#' @param infPatchTimeDiff A numeric duration in minutes, of the minimum time difference between two points, above which, it is assumed worthwhile to examine whether there is a missing residence patch to be inferred.
#' @param infPatchSpatDiff A numeric distance in metres, of the maximum spatial distance between two points, below which it may be assumed few extreme movements took place between them.
#'
#' @return A data.frame extension object. This dataframe has additional inferred points, indicated by the additional column for empirical fixes ('real') or 'inferred'.
#' @export
#'

wat_infer_residence <- function(df,
                               infPatchTimeDiff = 30,
                               infPatchSpatDiff = 100){

  # handle global variable issues
  infPatch<-nfixes<-posId<-resPatch<-resTime<-resTimeBool<-rollResTime <- NULL
  spatdiff <- time <- timediff <- type <- x <- y <- npoints <- NULL
  data <- duration <- id <- nfixes <- patch <- patchSummary <- NULL
  tide_number <- tidaltime <- time_end <- time_start <- NULL
  waterlevel <- NULL
  # adding the inferPatches argument to prep for inferring
  # residence patches from missing data between travel segments

  # check if data frame
  assertthat::assert_that(is.data.frame(df),
        msg = glue::glue('inferResidence: input not a dataframe object,\\
        has class {stringr::str_flatten(class(df), collapse = " ")}!'))

  # read the file in
  {
    # convert both to DT if not
    if(is.data.table(df) != TRUE) {data.table::setDT(df)}

  }

  # convert argument units
  {
    infPatchTimeDiff = infPatchTimeDiff*60
  }

  # get names and numeric variables
  dfnames <- colnames(df)
  namesReq <- c("id", "tide_number", "x", "y", "time", "resTime")
  numvars <- c("x","y","TIME","resTime")

  # include asserts checking for required columns
  {
    purrr::walk (namesReq, function(nr) {
      assertthat::assert_that(nr %in% dfnames,
          msg = glue::glue('{nr} is required but missing from data!'))
    })
  }

  ## SET THE DF IN ORDER OF TIME ##
  data.table::setorder(df,time)

  # check this has worked
  {
    assertthat::assert_that(min(diff(df$time)) >= 0,
                            msg = "data for segmentation is not ordered by time")
  }

  # make a df with id, tide_number and time seq, with missing x and y
  # identify where there are missing segments more than 2 mins long
  # there, create a sequence of points with id, tide, and time in 3s intervals
  # merge with true df
  tempdf <- df[!is.na(time),]
  # get difference in time and space
  tempdf <- tempdf[,`:=`(timediff = c(diff(time), NA),
                         spatdiff = watlastools::wat_simple_dist(df = tempdf, x = "x", y = "y"))]

  # find missing patches if timediff is greater than specified (default 30 mins)
  # AND spatdiff is less than specified (100 m)
  tempdf[,infPatch := cumsum((timediff > infPatchTimeDiff) & (spatdiff < infPatchSpatDiff))]

  # subset the data to collect only the first two points of an inferred patch
  # these are the first and last points of a travel trajectory
  tempdf[,posId := seq(1, .N), by = "infPatch"]
  # remove NA patches
  tempdf <- tempdf[posId <= 2 & !is.na(infPatch),]
  # now count the max posId per patch, if less than 2, merge with next patch
  tempdf[,npoints := max(posId), by="infPatch"]
  tempdf[,infPatch := ifelse(npoints == 2, yes = infPatch, no = infPatch+1)]
  tempdf <- tempdf[npoints >= 2,]
  # recount the number of positions, each inferred patch must have minimum 2 pos
  {
    assertthat::assert_that(min(tempdf$npoints) > 1,
                            msg = "some inferred patches with only 1 position")
  }
  # remove unn columns
  data.table::set(tempdf, ,c("posId","npoints"), NULL)

  # add type to real data
  df[,type:="real"]

  # enter this step only if there are 2 or more rows of data between which to infer patches
  if(nrow(tempdf) >= 2)
  {
    # make list column of expected times with 3 second interval
    # assume coordinate is the mean between 'takeoff' and 'landing'
    infPatchDf <- tempdf[,nfixes:=length(seq(from = min(time, na.rm = T),
                                             to = max(time, na.rm = T), by = 3)),
                         by = c("id", "tide_number", "infPatch")]

    # an expectation of integer type is created in time
    infPatchDf <- infPatchDf[,.(time = mean(time),
                                x = mean(x),
                                y = mean(y),
                                resTime = mean(timediff)),
                             by = c("id", "tide_number", "infPatch","nfixes")]

    infPatchDf <- infPatchDf[infPatch > 0,]
    infPatchDf <- infPatchDf[,type:="inferred"]

    rm(tempdf); gc()

    # remove infPatch and nfixes
    data.table::set(infPatchDf, ,c("infPatch", "nfixes"), NULL)

    # merge inferred data to empirical data
    df <- data.table::merge.data.table(df, infPatchDf, by = intersect(names(df), 
                                        names(infPatchDf)), all = TRUE)
  }

  # sort by time
  data.table::setorder(df, time)
  # remove coordidx
  df[,`:=`(coordIdx = NULL, posID = NULL,
           fpt = NULL, revisits = NULL,
           temp_time = NULL)]

  # fill tidal time and waterlevel
  df[,`:=`(tidaltime = nafill(tidaltime, "locf"),
           waterlevel = nafill(waterlevel, "locf"))]

  # check this has worked
  {
    assertthat::assert_that(min(diff(df$time)) >= 0,
                            msg = "data for segmentation is not ordered by time")
  }

  return(df)

}

# ends here
