#' A function to add high tide data to position data; also calculates the
#' time of each position since high tide.
#'
#' @param df A data frame which is the output of the clean data function \code{wat_clean_data}.
#' @param tide_data A data frame of high tide times which has the following columns: 1. time (as a posixct object), 2. waterlevel, 3. tide_number.
#'
#' @return A datatable class object (extends data.frame) which has the additional columns tide_number and time (in mins) since high tide.
#' @export
#'
wat_add_tide <- function(df,
				tide_data){

  time <- ts <- tide_number <- tidaltime <- x <- NULL

	# check correct argument types and data exists
	{
		assertthat::assert_that("data.frame" %in% class(df),
			msg = "wat_add_tide: df not a dataframe")
		assertthat::assert_that(is.character(tide_data),
			msg = "wat_add_tide: tide_data not a filename")
		assertthat::assert_that(file.exists(tide_data),
			msg = "wat_add_tide: tide_data not found")
	}

  # id input is not a data.table set it so
  if(!data.table::is.data.table(df)){
    setDT(df)
  }

	# include asserts checking for correct columns and data type
	{
	  # check position data frame
	  dfnames <- colnames(df)
      namesReq <- c("time", "ts")
      purrr::walk (namesReq, function(fr) {
        assertthat::assert_that(fr %in% dfnames,
          msg = glue::glue('wat_add_tide: {fr} is
                         required but missing from data!'))
      })

      # check for time in order
      min_time_diff <- min(as.numeric(diff(df$time)))
      if(min_time_diff < 0){
      	warning("wat_add_tide: time not ordered, re-ordering")
      }
      data.table::setorder(df, time)
      assertthat::assert_that("POSIXct" %in% class(df$ts))

      # check tide data
      # tide_df_names <- colnames(tide_data)
      namesReq <- c("time", "tide", "tide_number")
      # read in tide data
      tide_data <- data.table::fread(tide_data)[,time:=fasttime::fastPOSIXct(time)]

      purrr::walk (namesReq, function(nr) {
        assertthat::assert_that(nr %in% colnames(tide_data),
          msg = glue::glue('wat_add_tide: {nr} is
                         required but missing from tide data!'))
      })
	}

	# merge with tide data and order on high tide
	{
		temp_data <- data.table::merge.data.table(df, tide_data, by.x = "ts", by.y = "time",
                     all = TRUE)
    data.table::setorder(temp_data, ts)

    # get tide_number and time since high tide
    temp_data[, tide_number := data.table::nafill(tide_number, "locf")]
    temp_data[, tidaltime := as.numeric(difftime(ts, ts[1], units = "mins")),
             by = tide_number]

    # remove bad rows and columns
    temp_data <- temp_data[stats::complete.cases(x),]
    temp_data[,`:=`(tide = NULL, level = NULL)]
	}
  message(glue::glue('tag {unique(temp_data$id)} added time since high tide'))

  return(temp_data)
}
