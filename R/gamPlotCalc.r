# ####
#' plots data and gam fit vs. time
#'
#' @param dep variable dep
#' @param tsdat variable tsdat
#' @param pgam variable pgam
#' @param iSpec variable iSpec
#' @param analySpec variable analySpec
#' @param t.deriv variable t.deriv
#' @param alpha variable alpha
#' @param dayStep variable dayStep
#' @param step.pt variable step.pt
#'
#' @export
#'
# ####
.gamPlotCalc <- function(dep,tsdat,pgam,iSpec, analySpec,  t.deriv=FALSE,
                     alpha = 0.05, dayStep=10, step.pt='none', q.doy) {
#  pgam <- gamRslt;  tsdat<-ct1;  dayStep=figRes
# ----- Change history --------------------------------------------
# 30Sep2017: JBH: add creation of pdatWgt;
# 01Aug2017: JBH: add a row id number and sort columns in the prediction data set (pdat)
# 29Jul2017: JBH: added flw_sal and flw_sal.sd to prediction data set
# 08Feb2017: JBH: reverted prediction data set creation to be based on begin date
#                 of data set
# 06Feb2017: JBH: extended new seasonally averaged model calculations to intervention
#                 type gams, e.g., gam3
#                 re-sorted some code sections
# 05Feb2017: JBH: update prediction data set creation so that each year uses a consistent
#                 set of doy each year (i.e., dayStep=10 will yield a prediction data set
#                 of Jan 1, Jan 11, Jan 21 for each year of analysis)
# 04Feb2017: JBH: changed dayStep default to 10
# 05Jan2017: JBH: substituted new seasonally averaged model calculations (for
#                 non-intervention type gams, e.g., gam0,1,2)
# 20Oct2016: JBH: add intervention term to prediction data set (pdat)
# 17Oct2016: JBH: separated gamPlot to gamPlotCalc (calculations) and gamPlotDisp
#                 (display). This enables gamPlotDisp have a cleaner strategy for
#                 customizing plots.
# 16Oct2016: JBH: Added q.doy to list of arguments
# 16Jun2016: JBH: re-activated derivative code; updated pdat code to always compute
#                 predicted values for seasons and return pdat to calling function;
#                 added code to tally range of dates for significant increases/decreases
# 04Jun2016: JBH: added argument dayStep to thin plot density and reduce processing time
# 03Jun2016: JBH: Added unpack of stat and layer from iSpec
# 27Apr2016: JBH: Explicit use of "::" for non-base functions added.
# 04Feb2016: JBH: added horizontal grid lines to plots

#esp
#ESP dep is dependent variable character string
#esp tsdat is data frame of time series data
#esp pgam  gam object for currently fitted gam??
#esp iSpec collection of objects that get passed around among functions - like a global set
#esp t.deriv boolean for whether or not to test slope for significance
#esp alpha, dayStep, step.pt='none'
#esp q.doy vector of doys for plotting seasonal traces??
  # Unpack & initialization
  {
    # pgam <- gamRslt;  tsdat<-ct1;  dayStep=figRes
    date.range   <- c(iSpec$dateBegin, iSpec$dateEnd)
    centerYear   <- iSpec$centerYear
    formula      <- iSpec$gamForm
    transform    <- iSpec$transform
    stat         <- iSpec$stat
    layer        <- iSpec$layer

    # does model include intervention term 04Nov2016
    intervention <- ifelse (length(grep('intervention',pgam$formula  )) == 0, FALSE, TRUE)

    # does model include flw_sal term #29Jul2017 #06Aug2017 #30Sep2017
    has.flw_sal <- ifelse (length(grep('flw_sal',pgam$formula  )) == 0, FALSE, TRUE)
    if(has.flw_sal) {
      pdatWgt <- data.frame(normPct = analySpec$gamFlw_Sal.Wgt.Perc,
                            Z       = stats::qnorm(analySpec$gamFlw_Sal.Wgt.Perc),
                            normD   = stats::dnorm(stats::qnorm(analySpec$gamFlw_Sal.Wgt.Perc)))
    } else {
      pdatWgt <- data.frame(normPct = 0.5,
                            Z       = stats::qnorm(0.5),
                            normD   = stats::dnorm(stats::qnorm(0.5)))
    }
    pdatWgt$flw.wgt <- pdatWgt$normD/sum(pdatWgt$normD)

    # concatenate station-layer
    stat.layer <- paste(stat,layer,sep="-")

    # set dayStep to 10 if out of range
    if(!dayStep %in% c(1:30))  dayStep<-10   #04Feb2017
  } # end unpack/initialization

  # Build prediction data set #05Feb2017 #####
  {
    # # build prediction data set based on constant doy through the year
    # pdat       <- expand.grid(year=as.numeric(c(iSpec$yearBegin:iSpec$yearEnd)), doy = seq(1, 366, by=dayStep))
    # pdat$date  <- as.POSIXct(paste(pdat$year,
    #                                lubridate::month(as.Date(pdat$doy, origin = "1999-12-31")),
    #                                lubridate::day  (as.Date(pdat$doy, origin = "1999-12-31")),
    #                                sep='-'), format = "%Y-%m-%d")
    # pdat$doy.actual <- pdat$doy
    # pdat            <- pdat[with(pdat, order(date)), c("date","year","doy.actual","doy")]
    # pdat <- pdat[!is.na(pdat$date) & pdat$date >= iSpec$dateBegin &  pdat$date <= iSpec$dateEnd,]

    # build prediction data set based on begin date
    pdat <- data.frame(date = seq( as.Date(date.range[1]),as.Date(date.range[2]),by=dayStep))
    pdat$date  <- as.POSIXct(pdat$date)
    pdat$year  <- year(pdat$date)
    pdat$doy   <- pdat$doy.actual <- as.numeric(smwrBase::baseDay(pdat$date))

    pdat$cyear <- (pdat$year + (pdat$doy-1)/366) - centerYear # compute cyear

    ### add intervention term to prediction data set ###
    # internally adjust begin date of 1st intervention and end date of last
    # intervention by 10 days to make sure that we dont miss any days
    intervenList <- iSpec$intervenList
    intervenList$intervention <- as.character(intervenList$intervention)
    intervenList$beginDate[1] <- intervenList$beginDate[1] - 10*(24*3600)
    intervenList$endDate[nrow(intervenList)] <- intervenList$endDate[nrow(intervenList)] + 10*(24*3600)

    # create a column in pdat, intervention, which stores which method is applicable
    tmp <- lapply(1:nrow(pdat), function(x)
      list(intervenList[ intervenList$beginDate <= pdat$date[x] &
                           intervenList$endDate +(24*3600)-1 >= pdat$date[x], c("intervention")]))
    tmp[sapply(tmp, is.null)] <- NA
    pdat$intervention <- sapply(1:nrow(pdat), function(x) unname(unlist(tmp[x])[1]))
    pdat$intervention <- factor(pdat$intervention, levels = intervenList$intervention)
    pdat$intervention.actual <- pdat$intervention

    # add flw_sal and flw_sal.sd term for models with flw_sal  # 29Jul2017
    if(has.flw_sal) {
      pdat$flw_sal <- 0
      if(iSpec$hydroTermSel=="flow") {
        # for "flow", iSpec$hydroTermSel.var will be d* indicating the averaging period
        # associated with the best correlation (i.e., max(abs(cor))) between the dependent variable
        # and the detrended log flow, e.g., d120 refers to a 120-day averaging window
        tmp <- flow.detrended[[paste0("q",iSpec$usgsGageID,".sum")]][["lowess.sd"]]
        tmp <- tmp[,c("doy",iSpec$hydroTermSel.var )]
        names(tmp)[names(tmp) == iSpec$hydroTermSel.var] <- 'flw_sal.sd'
      } else if (iSpec$hydroTermSel=="salinity") {
        # for "salinity", iSpec$hydroTermSel.var will be SAP or BBP indicating the
        # average detrended salinity for "surface and above pycnocline" [SAP] or "bottom
        # and below pycnocline [BBP]. Selection is BBP for dependent variable from B, BP,
        # or BBP; and SAP otherwise
        tmp <- salinity.detrended[[paste0(stat,".sum")]][["lowess.sd"]]
        tmp <- tmp[,c("doy",iSpec$hydroTermSel.var )]
        names(tmp)[names(tmp) == iSpec$hydroTermSel.var] <- 'flw_sal.sd'
      } else {
        return('ERROR in lowess.sd pickup')
      }
      pdat <- merge(pdat,tmp, by="doy", all.x=TRUE)
      pdat <- pdat[with(pdat, order(date)), ]
    } else {
      pdat$flw_sal    <- NA_real_
      pdat$flw_sal.sd <- NA_real_
    }

    # add a row id number and sort columns #01Aug2017
    pdat$rowID <- seq.int(nrow(pdat))
    tmp <- c("rowID","date","year","cyear","doy","doy.actual")
    pdat<-pdat[c(tmp, setdiff(names(pdat), tmp))]

  } # end prediction data set build

  # Compute predicted values for full model and seasonal models values ####
  {
    # confirm pdat's intervention and doy are original values
    pdat$intervention   <- pdat$intervention.actual
    pdat$doy            <- pdat$doy.actual

    # full model
    p1 <- predict(pgam,newdata=pdat,se.fit=TRUE)
    pdat$pred1 <- p1$fit
    pdat$se1   <- p1$se.fit

    # seasonal model
    for (i in 1:length(q.doy)) {
      pdat$doy   <- q.doy[i]
      pdat[, paste0("seas.",i)] <- predict(pgam,newdata=pdat)
    }
  } # end full/seasonal model predictions

  # With Interventions: Compute *adjusted* predicted values for full model ####
  # and seasonal models values for when interventions exists (assumes last method applies)
  {
    if(intervention) {
      # confirm pdat's intervention is set to last method and doy is original value
      pdat$intervention   <- pdat$intervention.actual[nrow(pdat)]
      pdat$doy            <- pdat$doy.actual

      # full model
      pdat$pred1.adjusted <- predict(pgam,newdata=pdat)

      # seasonal models
      for (i in 1:length(q.doy)) {
        pdat$doy   <- q.doy[i]
        pdat[, paste0("seas.",i,".adjusted")] <- predict(pgam,newdata=pdat)
      }
    } # end *adjusted* full/seasonal model predictions
  }

  # Compute seasonally averaged model & significant trends ####
  {
    # confirm pdat's intervention is set to last method and doy is original value
    pdat$intervention   <- pdat$intervention.actual[nrow(pdat)]
    pdat$doy            <- pdat$doy.actual

    # create pdatLong from pdat with a downselected number of columns for merging
    # with pdatWgt; in the merge of pdatWgt and pdatLong (each row of pdat is repeated
    # for each record in pdatWgt, then goes to next row of pdat); flw_sal based on
    # z stat and sd
    pdatLong <- pdat[,c("rowID", "cyear", "doy", "doy.actual", "intervention", "intervention.actual", "flw_sal", "flw_sal.sd"  )]
    pdatLong <- merge( pdatWgt[,c("Z","flw.wgt")], pdat[,c("rowID", "cyear", "doy", "doy.actual", "intervention",
                                                           "intervention.actual", "flw_sal", "flw_sal.sd"  )])
    pdatLong$flw_sal <- pdatLong$Z * pdatLong$flw_sal.sd

    # compute seasonal- and flow/salinity-weighted average #30Sep2017: flw/sal weighting added
    Xlp     <- predict(pgam,newdata=pdatLong,type="lpmatrix")          ##2017-09-15: extract prediction matrix for pdatLong
    beta    <- pgam$coefficients        # coefficients vector
    VCmat   <- pgam$Vp                  # variance-covariance matrix of coefficents
    halfYearNobs <- as.integer(floor(183 / dayStep )) #esp compute approximate number of observations in half a year in pdat
    for(dpti in halfYearNobs:(length(pdat$date)-halfYearNobs)) {
      x2 <- (dpti-halfYearNobs+1)*nrow(pdatWgt)-(nrow(pdatWgt)-1)      ##2017-09-15: x2 & x3 represent which rows to extract
      x3 <- (dpti+halfYearNobs)*nrow(pdatWgt)                          ##2017-09-15: from pdatLong
      Xpc <- Xlp[x2:x3,]                                               ##2017-09-15: pull +/- 1/2 yr linear predictors
      Xsa <- pdatLong[x2:x3,"flw.wgt"]/sum(pdatLong[x2:x3,"flw.wgt"])  ##2017-09-15: construct averaging matrix
      Xsapc <- Xsa%*%Xpc  # multiply seasonal average matrix by 1 year of linear predictors
      pdat[dpti,'sa.pred1'] <- Xsapc%*%beta # this matrix times parameter vector gives seasonally adjusted prediction
      pdat[dpti,'sa.se1']   <- sqrt(Xsapc%*%VCmat%*%t(Xsapc))   # compute Std. Err. by usual rules
      #points(pdat$dyear[dpti],pdat[dpti,'sap2'],pch=19,cex=0.5)
      # derivative processing - compute slope test estimates
      if(dpti > halfYearNobs) # if past first point, do slope test
      {
        # again get a single matrix that will estimate the difference between SA estimates
        # current SA point is Xsapc%*%beta, last SA point is Xsapcl%*%beta,
        # difference  is Xsapc%*%beta - Xsapcl%*%beta = (Xsapc - Xsapcl)%*%beta
        Xsad <- Xsapc-Xsapcl  # compute matrix for difference between current and previous point
        #esp these are new columns in pdat
        pdat[dpti,'sad'] <- Xsad%*%beta  # compute seasonally adjusted difference
        pdat[dpti,'sad.se'] <- sqrt(Xsad%*%VCmat%*%t(Xsad)) # compute se for seasonally adjusted difference
      }
      Xsapcl <- Xsapc  # save current matrix for computing diffence in next interation.
    }
    #esp compute confidence band for seasonally adjusted predictions
    halpha     <- alpha/2
    pdat$ciub  <- pdat$sa.pred1 + qnorm(1-halpha) * pdat$sa.se1
    pdat$cilb  <- pdat$sa.pred1 - qnorm(1-halpha) * pdat$sa.se1
    pdat$ndate <- as.numeric(pdat$date)

    # compute significance of point to point slope
    pdat$sadz <- abs(pdat$sad / pdat$sad.se)          # new column in pdat
    pdat$sadzp <- pnorm(pdat$sadz,lower.tail=FALSE)   # new column in pdat
    pdat$sa.pred1.sig <- sign(pdat$sad) * (pdat$sadzp <= alpha)
  } # end seasonally averaged model & significant trends

  # With Interventions: compute seasonally averaged model & significant trends ####
  {
    if(intervention & nrow(intervenList)>1) {
      # copy seasonally averaged model as *adjusted* model (this is because the above
      # calc's assume the last method). If there is no intervention then the above calc's
      # are the final result, but if there is intervention then the above are the
      # *adjusted* results
      pdat$sa.pred1.adjusted <- pdat$sa.pred1
      pdat$sa.se1.adjusted   <- pdat$sa.se1

      # confirm pdat's doy is original value
      pdat$doy            <- pdat$doy.actual

      for (iInterven in 1:(nrow(intervenList)-1)) {
        # set pdat's intervention
        pdat$intervention   <- intervenList[iInterven,"intervention"]

        # create pdatLong from pdat with a downselected number of columns for merging
        # with pdatWgt; in the merge of pdatWgt and pdatLong (each row of pdat is repeated
        # for each record in pdatWgt, then goes to next row of pdat); flw_sal based on
        # z stat and sd
        pdatLong <- pdat[,c("rowID", "cyear", "doy", "doy.actual", "intervention", "intervention.actual", "flw_sal", "flw_sal.sd"  )]
        pdatLong <- merge( pdatWgt[,c("Z","flw.wgt")], pdat[,c("rowID", "cyear", "doy", "doy.actual", "intervention",
                                                               "intervention.actual", "flw_sal", "flw_sal.sd"  )])
        pdatLong$flw_sal <- pdatLong$Z * pdatLong$flw_sal.sd

        # compute seasonally averaged model & significant trends
        {
          Xlp     <- predict(pgam,newdata=pdatLong,type="lpmatrix")          ##2017-09-15: extract prediction matrix for pdatLong
          beta    <- pgam$coefficients        # coefficients vector
          VCmat   <- pgam$Vp                  # variance-covariance matrix of coefficents
          halfYearNobs <- as.integer(floor(183 / dayStep )) #esp compute approximate number of observations in half a year in pdat
          for(dpti in halfYearNobs:(length(pdat$date)-halfYearNobs)) {
            x2 <- (dpti-halfYearNobs+1)*nrow(pdatWgt)-(nrow(pdatWgt)-1)      ##2017-09-15: x2 & x3 represent which rows to extract
            x3 <- (dpti+halfYearNobs)*nrow(pdatWgt)                          ##2017-09-15: from pdatLong
            Xpc <- Xlp[x2:x3,]                                               ##2017-09-15: pull +/- 1/2 yr linear predictors
            Xsa <- pdatLong[x2:x3,"flw.wgt"]/sum(pdatLong[x2:x3,"flw.wgt"])  ##2017-09-15: construct averaging matrix
            Xsapc <- Xsa%*%Xpc  # multiply seasonal average matrix by 1 year of linear predictors
            pdat[dpti,'tmp.sa.pred1'] <- Xsapc%*%beta # this matrix times parameter vector gives seasonally adjusted prediction
            pdat[dpti,'tmp.sa.se1']   <- sqrt(Xsapc%*%VCmat%*%t(Xsapc))   # compute Std. Err. by usual rules
            #points(pdat$dyear[dpti],pdat[dpti,'sap2'],pch=19,cex=0.5)
          }
          #esp compute confidence band for seasonally adjusted predictions
          halpha     <- alpha/2
          pdat$tmp.ciub  <- pdat$tmp.sa.pred1 + qnorm(1-halpha) * pdat$tmp.sa.se1
          pdat$tmp.cilb  <- pdat$tmp.sa.pred1 - qnorm(1-halpha) * pdat$tmp.sa.se1

        } # end seasonally averaged model & significant trends

        # Frankenstein in selected results for ith intervention into final position
        pdat[pdat$intervention.actual==intervenList[iInterven,"intervention"],"sa.pred1"] <-
          pdat[pdat$intervention.actual==intervenList[iInterven,"intervention"],"tmp.sa.pred1"]
        pdat[pdat$intervention.actual==intervenList[iInterven,"intervention"],"sa.se1"] <-
          pdat[pdat$intervention.actual==intervenList[iInterven,"intervention"],"tmp.sa.se1"]
        pdat[pdat$intervention.actual==intervenList[iInterven,"intervention"],"ciub"] <-
          pdat[pdat$intervention.actual==intervenList[iInterven,"intervention"],"tmp.ciub"]
        pdat[pdat$intervention.actual==intervenList[iInterven,"intervention"],"cilb"] <-
          pdat[pdat$intervention.actual==intervenList[iInterven,"intervention"],"tmp.cilb"]
      } #end iInterven loop

      # drop tmp columns
      pdat <- pdat[,!(names(pdat) %in% c("tmp.sa.pred1","tmp.sa.se1","tmp.ciub","tmp.cilb"))]
    } # end: With Interventions: compute seasonally averaged model
  }

  # identify date ranges of significant increases ####
  {
    sa.sig.inc <- NA
    sa.sig.dec <- NA

    if(t.deriv)   {
      pdat$event  <- smwrBase::eventNum(pdat$sa.pred1.sig==1, reset=TRUE)
      events <- max(pdat$event)
      if(events>0) {
        sa.sig.inc <- NA
        for(i in 1:events) {
          tmp <- paste0(format(min (pdat[pdat$event==i,"date"]), "%m/%Y"), "-",
                        format(max (pdat[pdat$event==i,"date"]), "%m/%Y"), " ")
          if (is.na(sa.sig.inc)) sa.sig.inc <- tmp else
            sa.sig.inc <- paste0 (sa.sig.inc, tmp)
        }
      }

      # identify date ranges of significant decreases
      pdat$event  <- smwrBase::eventNum(pdat$sa.pred1.sig==-1, reset=TRUE)
      events <- max(pdat$event)
      if(events>0) {
        sa.sig.dec <- NA
        for(i in 1:events) {
          tmp <- paste0(format(min (pdat[pdat$event==i,"date"]), "%m/%Y"), "-",
                        format(max (pdat[pdat$event==i,"date"]), "%m/%Y"), " ")
          if (is.na(sa.sig.dec)) sa.sig.dec <- tmp else
            sa.sig.dec <- paste0 (sa.sig.dec, tmp)
        }
      }
      pdat <- pdat[,!(names(pdat) %in% c("event"))]
    } # end of t.deriv conditional
  } # end significant trend date range

  # Clean, Pack up list and return ####
  {
    # confirm pdat's intervention and doy are original values
    pdat$intervention   <- pdat$intervention.actual
    pdat$doy            <- pdat$doy.actual

    # Pack up list and return
    # if(!exists("mn.doy")) mn.doy <- NA  #06Aug2017
    gamPlotList <-list(pdat=pdat, sa.sig.inc=sa.sig.inc,
                       sa.sig.dec=sa.sig.dec               ) #06Aug2017 mn.doy dropped

    return(gamPlotList)
  }

}