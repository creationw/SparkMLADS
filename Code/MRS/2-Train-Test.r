# NOTE: Run 1-Clean-Join.r in the same R session before running 2-Train-Test.r

################################################
# Split out Training and Test Datasets
################################################

# split out the training data

airWeatherTrainDF <- airWeatherDF %>% filter(Year < 2012) 
airWeatherTrainDF <- airWeatherTrainDF %>% sdf_register("flightsweathertrain")

# split out the testing data

airWeatherTestDF <- airWeatherDF %>% filter(Year == 2012 & Month == 1)
airWeatherTestDF <- airWeatherTestDF %>% sdf_register("flightsweathertest")


# Create ScaleR data source objects

colInfo <- list(
  ArrDel15 = list(type="numeric"),
  CRSArrTime = list(type="integer"),
  Year = list(type="factor"),
  Month = list(type="factor"),
  DayOfMonth = list(type="factor"),
  DayOfWeek = list(type="factor"),
  Carrier = list(type="factor"),
  OriginAirportID = list(type="factor"),
  DestAirportID = list(type="factor")
)

finalData <- RxHiveData(table = "flightsweather", colInfo = colInfo)
colInfoFull <- rxCreateColInfo(finalData)

trainDS <- RxHiveData(table = "flightsweathertrain", colInfo = colInfoFull)
testDS <- RxHiveData(table = "flightsweathertest", colInfo = colInfoFull)


################################################
# Train and Test a Logistic Regression model
################################################

formula <- as.formula(ArrDel15 ~ Month + DayOfMonth + DayOfWeek + Carrier + OriginAirportID + 
                        DestAirportID + CRSDepTime + CRSArrTime + RelativeHumidityOrigin + 
                        AltimeterOrigin + DryBulbCelsiusOrigin + WindSpeedOrigin + 
                        VisibilityOrigin + DewPointCelsiusOrigin + RelativeHumidityDest + 
                        AltimeterDest + DryBulbCelsiusDest + WindSpeedDest + VisibilityDest + 
                        DewPointCelsiusDest
)

# Use the scalable rxLogit() function

logitModel <- rxLogit(formula, data = trainDS)

summary(logitModel)

save(logitModel, file = "logitModelSubset.RData")

# Predict over test data (Logistic Regression).

logitPredict <- RxXdfData(file.path(dataDir, "logitPredictSubset"))

# Use the scalable rxPredict() function

rxPredict(logitModel, data = testDS, outData = logitPredict,
          extraVarsToWrite = c("ArrDel15"),
          type = 'response', overwrite = TRUE)

# Calculate ROC and Area Under the Curve (AUC).

logitRoc <- rxRoc("ArrDel15", "ArrDel15_Pred", logitPredict)
logitAuc <- rxAuc(logitRoc)
# 0.645261

plot(logitRoc)


#####################################
# rxEnsemble of fastTrees
#####################################

trainers <- list(fastTrees(numTrees = 50))

fastTreesEnsembleModelTime <- system.time(
  fastTreesEnsembleModel <- rxEnsemble(formula, data = trainDS,
    type = "regression", trainers = trainers, modelCount = 16, splitData = TRUE)
)

summary(fastTreesEnsembleModel)

save(fastTreesEnsembleModel, file = "fastTreesEnsembleModelSubset.RData")

# Test
fastTreesEnsemblePredict <- RxXdfData(file.path(dataDir, "fastTreesEnsemblePredictSubset"))

# Experimental feature to parallelize rxPredict when using a MicrosoftML model
assign("predictMethod", "useDataStep", envir = MicrosoftML:::rxHashEnv)

fastTreesEnsemblePredictTime <- system.time(
  rxPredict(fastTreesEnsembleModel, data = testDS, outData = fastTreesEnsemblePredict,
          extraVarsToWrite = c("ArrDel15"),
          overwrite = TRUE)
)

# Calculate ROC and Area Under the Curve (AUC).

fastTreesEnsembleRoc <- rxRoc("ArrDel15", "Score", fastTreesEnsemblePredict)
fastTreesEnsembleAuc <- rxAuc(fastTreesEnsembleRoc)
# 0.6662082

plot(fastTreesEnsembleRoc)

rxSparkDisconnect(cc)
