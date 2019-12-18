# server func
library(glue)
library(ggplot2)
library(data.table)
library(leaflet)
library(tmap)

server <- function(input, output) {

  #### general data handling ####
  dataOut <- eventReactive(input$go, {
    # reads in data
    somedata <- data.table::fread(input$datafile$datapath)

    # run the inference func
    inference_output <-
      funcInferResidence(
        df = somedata,
        infResTime = input$restIndepLimit,
        infPatchTimeDiff = input$infPatchTimeDiff,
        infPatchSpatDiff = input$infPatchSpatDiff)

    # run the classification func
    classified_output <-
      funcClassifyPath(
        somedata = inference_output,
        resTimeLimit = input$resTimeLimit
      )

    # run patch construction
    patch_output <-
      funcGetResPatch(
        somedata = classified_output,
        bufferSize = input$bufferSize,
        spatIndepLim = input$spatIndepLimit,
        tempIndepLim = input$tempIndepLimit,
        restIndepLim = input$restIndepLimit,
        minFixes = input$minfixes,
        tideLims = c(input$lim1, input$lim2)
      )

    return(patch_output)
  })

  #### raw data ####
  dataRaw <- eventReactive(input$go, {
    # reads in data
    somedata <- data.table::fread(input$datafile$datapath)
  })

  ### patch summary ####
  output$patchSummary <- renderTable(
    {
      patchSummary <- sf::st_drop_geometry(funcGetPatchData(resPatchData = dataOut(),
                                                            dataColumn = "data",
                                                            whichData = "spatial"))

      patchSummary <- dplyr::mutate(patchSummary, duration = duration/60)

      patchSummary <- dplyr::select(patchSummary,
                                    id, tidalcycle, patch,
                                    type,
                                    tidaltime_mean,
                                    duration,
                                    distInPatch,
                                    dispInPatch,
                                    distBwPatch,
                                    nfixes,
                                    area,
                                    circularity)
      return(patchSummary)
    })

  #### patches map plot ####
  output$this_map_label <- renderText(
    {paste("bird tag id = ", unique((dataOut())$id),
           "tidal cycle = ", unique((dataOut())$tidalcycle))}
  )

  output$patch_map <- renderLeaflet(
    {
      patchSummary <- funcGetPatchData(resPatchData = dataOut(),
                                                            dataColumn = "data",
                                                            whichData = "spatial")
      patchSummary <- dplyr::mutate(patchSummary, duration = duration/60)
      sf::st_crs(patchSummary) <- 32631
      # get trajectories
      {
        patchtraj <- funcPatchTraj(df = dataOut())
        # sf::st_crs(patchtraj) <- 32631
      }
      # get points
      {
        raw_pts <- dplyr::arrange((dataRaw()[,c("x","y","time","resTime")]), time)
        raw_pts <- sf::st_as_sf(raw_pts[,c("x","y","time","resTime")], coords=c("x","y"))
        sf::st_crs(raw_pts) <- 32631

        raw_pts <- dplyr::arrange(raw_pts, time)
        raw_lines <- sf::st_cast(sf::st_combine(raw_pts), "LINESTRING")
        sf::st_crs(raw_lines) <- 32631
      }
      # make plot
      {
        labels <- sprintf(
          "<strong>%s</strong><br/>%g area = m<sup>2</sup>",
          patchSummary$patch, patchSummary$area
        ) %>% lapply(htmltools::HTML)

        main_map <- tm_basemap(leaflet::providers$Esri.WorldImagery)+
          tm_shape(raw_lines)+
          tm_lines(lwd = 0.2, col = "black")+
          tm_shape(patchSummary)+
          tm_polygons(col="patch", palette = "Blues",
                      border.col = "black",
                      alpha = 0.6, style = "cat",
                      popup.vars = c("patch","duration","area","tidaltime_mean"))+
          tm_shape(raw_pts)+
          tm_symbols(size=0.005, col = "resTime", alpha = 0.3, border.col = NULL,
                     style = "cont", palette = viridis::plasma(10))

          tm_scale_bar()
      }

      return(tmap_leaflet(main_map))

    }
    )

  ### restime time plot ####
  output$resTime_time <- renderPlot(
    {
      # get patch points and join to raw data
      {
        patch_point_data <- (dataRaw())

        # patch_point_data <- dplyr::filter(patch_point_data, type != "inferred")

        # patch_point_data <- dplyr::arrange(patch_point_data, time)
      }
      # get patch summary for vert lines
      {
        # get patch outlines
        patchSummary <- funcGetPatchData(resPatchData = dataOut(),
                                         dataColumn = "data",
                                         whichData = "spatial")

        patchSummary <- sf::st_drop_geometry(patchSummary)
      }

      # make plot
      {
        plot1 <- ggplot()+
          geom_hline(yintercept = input$resTimeLimit, colour = "red", lty = 2)+
          geom_rect(data = patchSummary, aes(xmin = time_start, xmax = time_end,
            ymin = 0, ymax = max(patch_point_data$resTime), fill = patch), alpha = 0.6)+
          geom_line(data = patch_point_data,
                    aes(time, resTime, group = tidalcycle), col = "grey50", size = 0.1)+
          geom_point(data = patch_point_data,
                     aes(time, resTime),
                     alpha = 0.2, size = 0.2)+
          scale_x_time(labels = scales::time_format(format = "%Y-%m-%d\n %H:%M"))+

          geom_label(data = patchSummary, aes(time_mean, max(patch_point_data$resTime), label = patch))+
          geom_vline(data = patchSummary, aes(xintercept = time_end), col = 2, lty = 3, size = 0.2)+
          geom_vline(data = patchSummary, aes(xintercept = time_start), col = 4, lty = 3, size = 0.2)+

          # scale_color_manual(values = somecolours, na.value = "grey")+
          scale_fill_distiller(palette = "Blues",na.value = "red", direction = 1)+
          theme_bw()+
          ylim(0, max(patch_point_data$resTime))+
          theme(legend.position = 'none',
                axis.title = element_text(size = rel(0.6)),
                panel.grid = element_blank())+
          labs(x = "time", y = "raw (mins)", col = "patch")
      }

      return((plot1))

    }, res = 100
    )
}

# ends here