zscore = function(data) {
  z = (data-mean(data))/sd(data)
  return(z)
}

winsorize = function(data = NULL, sigAdj=NULL) {
  require(dplyr)
  
  new_data = data[abs(zscore(data)) <= sigAdj]
  new_mean = mean(new_data)
  new_sd = sd(new_data)
  lowerb = new_mean - sigAdj*new_sd
  upperb = new_mean + sigAdj*new_sd
  
  wd = case_when(
  data < lowerb ~ lowerb,
  data > upperb ~ upperb,
  TRUE ~ data
  )
  
  return(wd)
}

wins_rs = function(data=NULL, sigCheck=NULL, sigAdj=NULL) {
  # define additional parameters
  maxitr = 100 # max iteration limit (use equal sigCheck & sigAdj to test)
  i = 1 # initialization parameter
  wCt = 0 # counts of winsorization
  Log = data.frame(data, zs = zscore(data))
  
  # while loop
  while (i == 1) {
    maz = max(abs(zscore(data)))
    if ( maz > sigCheck && wCt <= maxitr) {
      data = winsorize(data,sigAdj)
      Log = data.frame(Log, data, zs = zscore(data))
      wCt = wCt+1
    } else {
      i = 0
    }
  }

  # Outputs
  list.out = list("data" = data, 
                  "dataz" = zscore(data),
                  "WinsCount" = wCt,
                  "LastZscore" = maz,
                  "log" = Log
                  )
  return(list.out)
}

#### test ###
# a = as.double(c(1:49))
# a = c(a,1E+16)
# op = wins_rs(a,5,3)
# 
# op$data
# op$dataz
# op$WinsCount
# op$log