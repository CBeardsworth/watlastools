# server func
library(glue)
library(ggplot2)
library(data.table)
library(pals)

server <- function(input, output) {

  #### general data handling ####
  dataOut <- eventReactive(input$go, {
    # reads in data
    revdata <- data.table::fread(input$revfile$datapath)
    htdata <- data.table::fread(input$htfile$datapath)

    # run the inference func
    inference_output <-
    funcInferResidence(
      revdata = revdata,
      htdata = htdata,
      infResTime = input$infResTime,
      infPatchTimeDiff = input$infPatchTimeDiff,
      infPatchSpatDiff = input$infPatchSpatDiff)

    # run the classification func
    classified_output <-
    funcClassifyPath(
      somedata = inference_output,
      restimeCol = input$resTimeCol,
      resTimeLimit = input$resTimeLimit,
      travelSeg = input$travelSeg
      )

    # run patch construction
    patch_output <-
    funcGetResPatch(
      somedata = classified_output,
      bufferSize = input$bufferSize,
      spatIndepLim = input$spatIndepLimit,
      tempIndepLim = input$tempIndepLimit
      )

    return(patch_output)
  })

  #### raw data ####
  dataRaw <- eventReactive(input$go, {
    # reads in data
    revdata <- data.table::fread(input$revfile$datapath)
  })

  ### patch summary ####
  output$patchSummary <- renderTable(
  {
    patchSummary <- sf::st_drop_geometry(funcGetPatchData(resPatchData = dataOut(),
      dataColumn = "data",
      whichData = "spatial"))

    patchSummary <- dplyr::select(patchSummary,
      id, tidalcycle, patch,
      type,
      tidaltime_mean,
      distInPatch,
      distBwPatch,
      propfixes,
      area)
    return(patchSummary)
  })

  #### patches map plot ####
  output$this_map_label <- renderPrint(
    {paste("bird tag id = ", unique((dataOut())$id),
          "tidal cycle = ", unique((dataOut())$tidalcycle))}
    )

  output$patch_map <- renderPlot(
  {
      # get patch outlines
    patchSummary <- funcGetPatchData(resPatchData = dataOut(),
      dataColumn = "data",
      whichData = "spatial")
      # get trajectories
    {
      patchtraj <- funcPatchTraj(df = patchSummary)
    }
      # get points
    {
      patchdata <- funcGetPatchData(resPatchData = dataOut(),
        dataColumn = "data",
        whichData = "points")
    }

    return(
      ggplot()+
      geom_point(data = dataRaw(), aes(x,y), col = "grey30", 
        size = 0.1, shape = 4, alpha = 0.2)+
      geom_sf(data = patchSummary,
        aes(fill = (patch), geometry = polygons),
        alpha = 0.8, col = 'transparent')+
      
      geom_sf(data = patchtraj, col = "black", size = 0.2)+
      scale_fill_gradientn(colours = pals::kovesi.rainbow(max(patchSummary$patch)),
        breaks = 1:max(patchSummary$patch))+
      ggthemes::theme_few()+
      theme(axis.text = element_blank(),
        axis.title = element_text(size = rel(0.5)),
        legend.title = element_text(size = rel(0.5)),
        legend.text = element_text(size = rel(0.5)),
        legend.position = "bottom",
        legend.key.height = unit(0.05, "cm"),
        plot.title = element_text(size = rel(0.5)))+
      labs(x = "long", y = "lat", fill = "patch",
        title = paste("bird tag = ",
          unique((dataRaw())$id), 
          "tidal cycle = ",
          unique((dataRaw())$tidalcycle)))
      )

  }, res = 150)

  ### restime time plot ####
  output$resTime_time <- renderPlot(
  {
    # get patch points and join to raw data
    {
      patch_point_data <- funcGetPatchData(
        resPatchData = dataOut(),
        dataColumn = "data",
        whichData = "points")

      patch_point_data <- dplyr::left_join(dataRaw(),
        patch_point_data,
        by = c("x", "y", "coordIdx", "time", "id", "tidalcycle", "resTime", "fpt", "revisits"))
    }

    return(
      ggplot()+
      geom_hline(yintercept = input$resTimeLimit, col = 2, lty = 2)+
      geom_line(data = patch_point_data,
        aes(time, resTime, group = tidalcycle), col = "grey50", size = 0.1)+
      geom_point(data = patch_point_data,
       aes(time, resTime, col = factor(patch)),
       alpha = 0.2)+
        # facet_wrap(~tidalcycle, ncol = 1, scales = "free_x",
        #            labeller = "label_both")+
      scale_x_time(labels = scales::time_format(format = "%Y-%m-%d\n %H:%M"))+
        # geom_text(aes(time_mean, 100, label = patch))+
        # geom_vline(aes(xintercept = time_end), lty = 3, size = 0.2)+
      scale_color_manual(values = kovesi.rainbow(max(patch_point_data$patch, 
        na.rm = TRUE)), na.value = "grey90")+
      ggthemes::theme_few()+
      theme(legend.position = 'none')+
      labs(x = "time", y = "residence time (mins)", col = "patch")
      )

  }, 
  res = 100)
}
# ends here