#' A function to clean data accessed from the NIOZ WATLAS server. Allows filtering on standard deviation, and the number of receivers that detected the tag. Applies a moving-window median filter, whose size can be specified.
#'
#' @param somedata A dataframe object returned by getData. Must contain the columns "X", "Y", "SD", "NBS", "TAG", "TIME"; these are the X coordinate, Y coordinate, standard deviation in measurement, number of ATLAS towers that received the signal, the tag number, and the numeric time, in milliseconds from 1970-01-01.
#' @param sd_threshold A threshold value above which rows are removed.
#' @param nbs_min The minimum number of base stations (ATLAS towers) that received tag signal.
#' @param moving_window The size of the moving window for the running median calculation.
#' @param speed_cutoff The maximum speed in kilometres per hour allowed in the raw data. Points with straight line displacement speeds calculated as above this are removed.
#' @param filter_speed Logical specifiying whether to use the speed filter or not.
#'
#' @return A datatable class object (extends data.frame) which has the additional columns posID and ts, which is TIME converted to human readable POSIXct format.
#' @export
#'
wat_clean_data <- function(somedata,
                           moving_window=3,
                           nbs_min=0,
                           sd_threshold=2000,
                           filter_speed=TRUE,
                           speed_cutoff = 150){

  SD <- NBS <- TIME <- TAG <- X <- Y <- NULL
  posID <- ts <- X_raw <- Y_raw <- VARX <- VARY <- COVXY <- NULL
  sld <- sld_speed <- NULL

  # check parameter types and assumptions
  {
    assertthat::assert_that("data.frame" %in% class(somedata),
                            msg = "cleanData: not a dataframe object!")

    # ensure dataframe only contains one individual, otherwise wrapper function should be used.
    assertthat::assert_that(length(unique(somedata$TAG)) == 1,
                            msg = "cleanData: cannot be used in dataframes with multiple individuals!")

    # include asserts checking for required columns
    {
      dfnames <- colnames(somedata)
      namesReq <- c("X", "Y", "SD", "NBS", "TAG", "TIME", "VARX", "VARY", "COVXY")
      purrr::walk (namesReq, function(nr) {
        assertthat::assert_that(nr %in% dfnames,
                                msg = glue::glue('cleanData: {nr} is
                         required but missing from data!'))
      })
    }

    # check args positive
    assertthat::assert_that(min(c(moving_window)) > 1,
                            msg = "cleanData: moving window not > 1")
    assertthat::assert_that(min(c(nbs_min)) >= 0,
                            msg = "cleanData: NBS min not positive")
    assertthat::assert_that(min(c(speed_cutoff)) >= 0,
                            msg = "cleanData: speed cutoff not positive")
  }

  # convert to data.table
  {
    # convert both to DT if not
    if(data.table::is.data.table(somedata) != TRUE) {data.table::setDT(somedata)}
  }

  # delete positions with approximated standard deviations above SD_threshold,
  # and below minimum number of base stations (NBS_min)
  somedata <- somedata[SD < sd_threshold & NBS >= nbs_min,]

  prefix_num <- 31001000000

  # begin processing if there is data
  if(nrow(somedata) > 1)
  {
    # add position id and change time to seconds
    somedata[,`:=`(posID = 1:nrow(somedata),
                   TIME = as.numeric(TIME)/1e3,
                   TAG = as.numeric(TAG) - prefix_num,
                   X_raw = X,
                   Y_raw = Y)]

    if(filter_speed == TRUE){
      # filter for insane speeds if asked
      somedata[,sld := wat_simple_dist(somedata, "X", "Y")]
      somedata[,sld_speed := sld/c(NA, as.numeric(diff(TIME)))]
      somedata <- somedata[sld_speed <= (speed_cutoff / 3.6), ]
      somedata[ ,`:=`(sld = NULL, sld_speed = NULL)]
    }

    # make separate timestamp col
    somedata[,ts := as.POSIXct(TIME, tz = "CET", origin = "1970-01-01")]

    # median filter
    #includes reversed smoothing to get rid of a possible phase shift
    somedata[,lapply(.SD,
                     function(z){
                       stats::runmed(rev(stats::runmed(z, moving_window)),
                                     moving_window)}),
             .SDcols = c("X", "Y")]

    ## postprocess (clean) data
    somedata <- somedata[,.(TAG, posID, TIME, ts, X_raw, Y_raw, NBS, VARX, VARY, COVXY, X, Y, SD)]

    # rename x,y,time to lower case
    setnames(somedata, old = c("X","Y","TAG","TIME"),
             new = c("x","y","id","time"))

  }else{

    somedata <- data.table::data.table(matrix(NA, nrow = 0, ncol = 12))
    setnames(somedata, c("id", "posID", "time", "ts", "X_raw",
                            "Y_raw", "NBS", "VARX", "VARY", "COVXY", "x", "y"))
  }

  assertthat::assert_that("data.frame" %in% class(somedata),
                          msg = "cleanData: cleanded data is not a dataframe object!")

  return(somedata)
}

# ends here
