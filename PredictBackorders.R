if(!require(tidyverse)) install.packages("tidyverse", repos = "http://cran.us.r-project.org")
if(!require(caret)) install.packages("caret", repos = "http://cran.us.r-project.org")
if(!require(data.table)) install.packages("data.table", repos = "http://cran.us.r-project.org")
if(!require(rafalib)) install.packages("rafalib", repos = "http://cran.us.r-project.org")
if(!require(lubridate)) install.packages("lubridate", repos = "http://cran.us.r-project.org")
if(!require(reshape2)) install.packages("reshape2", repos = "http://cran.us.r-project.org")
if(!require(ggcorrplot)) install.packages("ggcorrplot", repos = "http://cran.us.r-project.org")
if(!require(randomForest)) install.packages("randomForest", repos = "http://cran.us.r-project.org")
if(!require(Rborist)) install.packages("Rborist", repos = "http://cran.us.r-project.org")
if(!require(ROCR)) install.packages("ROCR", repos = "http://cran.us.r-project.org")
if(!require(kableExtra)) install.packages("kableExtra", repos = "http://cran.us.r-project.org")
library(tidyverse)
library(caret)
library(data.table)
library(rafalib)
library(lubridate)
library(reshape2)
library(ggcorrplot)
library(randomForest)
library(Rborist)
library(ROCR)
library(kableExtra)

# Dataset:
# https://github.com/doshading/PredictBackorders/raw/main/dataset.zip
url <- "https://github.com/doshading/PredictBackorders/raw/main/dataset.zip"
tmp_filename <- tempfile()
download.file(url, tmp_filename)
training_set <- read_csv(unzip(tmp_filename, "Kaggle_Training_Dataset_v2.csv"))
testing_set <- read_csv(unzip(tmp_filename, "Kaggle_Test_Dataset_v2.csv"))
file.remove(tmp_filename)

# 1. Introduction

# This project is originally from Kaggle Community Prediction Competition.
# Material backorder is a very common challenge in the industries. Being able to mitigate risks of backorder help companies to enable a resilient supply chain. It not only saves millions of cost but also improve customer satisfaction as well as increase market share.
# There are many off-the-shelf software aiming to solving the same problem. A lot of them focuses on building some sort of simulation model, or simply monitor the run chart with threshold to notify users of upcoming backorders.
# With the development of computation power in the recent decades, and the fast advancement of machine learning, today I'd like to explore possible solutions using machine learning models.
# The dataset has already been taken down on Kaggle website. However, you can still find in online, such as https://github.com/rodrigosantis1/backorder_prediction
# I have also uploaded a copy in my GitHub. Here is the link: https://github.com/doshading/PredictBackorders/raw/main/dataset.zip
# The dataset is already splitted into training set and testing set, with roughly 87% and 13% of the original data.
# Below are the explanation of the data fields:
# � sku -sku code
# � national_inv- Current inventory level of component
# � lead_time -Transit time
# � in_transit_qtry - Quantity in transit
# � forecast_x_month - Forecast sales for the net 3, 6, 9 months
# � sales_x_month - Sales quantity for the prior 1, 3, 6, 9 months
# � min_bank - Minimum recommended amount in stock
# � potential_issue - Indictor variable noting potential issue with item
# � pieces_past_due - Parts overdue from source
# � perf_x_months_avg - Source performance in the last 6 and 12 months
# � local_bo_qty - Amount of stock orders overdue
# � X17-X22 - General Risk Flags
# � went_on_back_order - Product went on backorder
# Our target is to develop a model to predict future backorders for a specific SKU based on provided predictors. The outcome is binary.
# Due to the nature of the backorder and imbalance of the classes (more details are explained in later part of this report), we will use the AUC (Area under the RoC Curve) Score to evaluate the model performance and decide the final model.
# This report, following the course requirements, will explain the process to explore the data, identify data quality issues, clean the data, develop insights, build model and eventually pick the optimal model.

# 2. Data Exploration and Analysis

# 2.1 General Overview

# I start by looking at the dimensions of both data sets. 
# The training set includes over 1,687,000 rows and 23 columns. And the testing set includes over 242,000 rows and 23 columns.
# dimension of the datasets
dim(training_set)
dim(testing_set)
# head of the datasets
head(training_set)
head(testing_set)

# As I mentioned in the Introduction, the training set and testing set was splitted by 87% and 13%.
nrow(training_set)/(nrow(training_set)+nrow(testing_set))

# 2.2 SKU

# Let's look at individual columns. First is sku. Below shows the number of unique skus in both data sets.
training_set %>% summarize(n_sku = n_distinct(sku))
testing_set %>% summarize(n_sku = n_distinct(sku))
# I notice the number of unique sku is the same as the number of rows. Therefore I will remove sku column.
training_set <- training_set[,-1]
testing_set <- testing_set[,-1]

# 2.3 Missing values

# Here is an overview of missing values.
# Except that lead_time has a lot of missing values, all other columns have just one missing value. 
sapply(training_set, function(x) sum(is.na(x)))
sapply(testing_set, function(x) sum(is.na(x)))
# It turns out the last row of the dataset was just a summary. 
training_set[nrow(training_set),]
testing_set[nrow(testing_set),]
# Therefore I can remove it.
training_set <- training_set[-1687861,]
testing_set <- testing_set[-242076,]
# Now check the missing values again. It shows only lead_time now.
sapply(training_set, function(x) sum(is.na(x)))
sapply(testing_set, function(x) sum(is.na(x)))

# 2.4 Sales Data

# Here is the summary of each columns in the datasets.
# Looking at forecast sales for the next 3, 6, 9 months, I do see similar increments in between. It indicates the data quality is good.
# I also looked at sales quantity for the past 1, 3, 6, 9 months. Similar increments can be seen in between as well, which indicates good data quality.
# Note both perf_6_month_avg and perf_12_month_avg (Source performance in the last 6 and 12 months) have only negative values. This may be due to their IT system setup.
summary(training_set)
summary(testing_set)

# 2.5 Minimum Recommended Stock

# As to min_bank (Minimum recommended amount in stock), my experience in the Automotive industry tells me it has to be positively related to the lead time, sales and sale forecasting.
# Below is a correlation heatmap among them. Except lead time, min_bank is correlated to all other features. This proves min_bank has good data quality.
training_set %>% 
  select(min_bank, lead_time, forecast_3_month, forecast_6_month, forecast_9_month, sales_1_month, sales_3_month, sales_6_month, sales_9_month) %>% 
  cor() %>%
  ggcorrplot()

# 2.6 Lead Time

# Since lead_time has a lot of missing value and could not generate correlation map. I removed all missing values and tried again. Still no success.
training_set %>% 
  filter(!is.na(lead_time)) %>% 
  select(min_bank, lead_time) %>% 
  cor() %>%
  ggcorrplot()
# Then I created a scatter plot (1000 sample observations) to look at details between min_bank and lead_time. There is clearly no correlation between the two features. This conflicts with my industry experience.
# set.seed(123) # if using R 3.5 or earlier
set.seed(123, sample.kind = "Rounding") # if using R 3.6 or later
index <- sample(nrow(training_set), 1000)
training_set[index,] %>% 
  filter(!is.na(lead_time)) %>% 
  ggplot(aes(min_bank, lead_time)) +
  geom_point() +
  scale_x_log10()
# In addition, analysis shows there are 100,893 missing values + 10,511 zero values in lead_time. 
training_set %>% 
  group_by(is.na(lead_time)) %>% 
  summarize(n())
training_set %>% 
  filter(!is.na(lead_time)) %>% 
  summarize(sum(lead_time==0))
# At this point, I decided to remove lead_time column because the data quality does not seem good.
training_set <- training_set %>% select(-lead_time)
testing_set <- testing_set %>% select(-lead_time)

# 2.7 Current Inventory Level

# Here is a histogram of Current Inventory Level.
training_set %>% 
  ggplot(aes(national_inv)) + 
  geom_histogram(binwidth = 0.1, color = "black") + 
  scale_x_log10() + 
  xlab("Current Inventory Level") + ylab("count") +
  ggtitle("Current Inventory Level Histogram")
# I notice national_inv has many negative values. Over 0.3% (5888) of national_inv in the training set is negative. 
# Negative inventory absolutely doesn't make sense. However, from my past experience of interacting with these IT systems, I recognize it could be pretty common to have negative inventory in the system.
mean(training_set$national_inv<0)
sum(training_set$national_inv<0)
# Let's take a look only the negative values, and see how they distribute. The distribution is pretty broad. 
training_set %>% 
  filter(national_inv<0) %>%
  mutate(national_inv=abs(national_inv)) %>%
  ggplot(aes(national_inv)) + 
  geom_histogram(binwidth = 0.1, color = "black") + 
  scale_x_log10() + 
  xlab("Current Inventory Level (absolute from negative values)") + ylab("count") +
  ggtitle("Current Inventory Level (only negative values) Histogram")
# Even though negative inventory doesn't make sense since you cannot have negative number of parts, I consider those are good indication that either the actual inventory is not properly monitored, or the whole supplier management system is not properly used. Therefore I will still include them in the model.

# 2.8 All Character Columns

# Now let's look at all character class columns. As you can see below, all of them have only "Yes", "No" values. 
rbind(table(training_set$potential_issue), 
      table(training_set$deck_risk),
      table(training_set$oe_constraint),
      table(training_set$ppap_risk),
      table(training_set$stop_auto_buy),
      table(training_set$rev_stop),
      table(training_set$went_on_backorder))
# This should be converted to 1 and 0.
training_set <- training_set %>% 
  mutate(potential_issue = ifelse(potential_issue=="Yes",1,0), 
         deck_risk = ifelse(deck_risk=="Yes",1,0), 
         oe_constraint = ifelse(oe_constraint=="Yes",1,0), 
         ppap_risk = ifelse(ppap_risk=="Yes",1,0), 
         stop_auto_buy = ifelse(stop_auto_buy=="Yes",1,0), 
         rev_stop = ifelse(rev_stop=="Yes",1,0), 
         went_on_backorder = ifelse(went_on_backorder=="Yes",1,0), 
         )
testing_set <- testing_set %>% 
  mutate(potential_issue = ifelse(potential_issue=="Yes",1,0), 
         deck_risk = ifelse(deck_risk=="Yes",1,0), 
         oe_constraint = ifelse(oe_constraint=="Yes",1,0), 
         ppap_risk = ifelse(ppap_risk=="Yes",1,0), 
         stop_auto_buy = ifelse(stop_auto_buy=="Yes",1,0), 
         rev_stop = ifelse(rev_stop=="Yes",1,0), 
         went_on_backorder = ifelse(went_on_backorder=="Yes",1,0), 
         )

# 2.9 Correlations

# Now all the data is cleaned. Let's see the overall correlation among all remaining features.
training_set %>% 
  cor() %>%
  ggcorrplot()
# First, there is no direct correlation between went_on_backorder and any predictors. A linear model may not work well.
# Second, there are clear correlations among sales forecasting, historical sales, minimum recommended stock, current inventory, quantity in transit, and parts overdue from source.
# This makes sense because stronger sales require more stock, more in transit, and often lead to more parts overdue from suppliers.

# 2.10 Outcome Column

# went_on_backorder is the outcome we are trying to predict. Here I convert the outcome to factors.
training_set <- training_set %>% 
  mutate(went_on_backorder = as.factor(went_on_backorder))
testing_set <- testing_set %>% 
  mutate(went_on_backorder = as.factor(went_on_backorder))

# A quick view shows that only 0.669% of the training data has value 1. The data is very much imbalanced. 
table(training_set$went_on_backorder)
training_set %>% 
  summarize(mean(went_on_backorder==1))

# 3. Model Building and Methods

# 3.1 Class Imbalance

# In order to solve the imbalance challenge, I have to either downsample or upsample the data before training the model.
# Due to the fact that the training set has over 1.5 million rows, and the limited computing power of my laptop, I decided to downsample the data.
# set.seed(111) # if using R 3.5 or earlier
set.seed(111, sample.kind = "Rounding") # if using R 3.6 or later
training_set_down <- downSample(x=training_set[,-ncol(training_set)], 
                                y=training_set$went_on_backorder,
                                list = FALSE,
                                yname = "went_on_backorder")
# Now both classes have equal number of observations.
table(training_set_down$went_on_backorder)

# (Below creates subsets from training set and testing set so my laptop can test in less time. Final report is switched to full size data set.)
# (Subset: <7 min run time)
# set.seed(123) # if using R 3.5 or earlier
# -----------------------
# set.seed(123, sample.kind = "Rounding") # if using R 3.6 or later
# index <- sample(nrow(training_set_down), 3000)
# x <- training_set_down[index,-ncol(training_set_down)]
# y <- training_set_down$went_on_backorder[index]
# index <- sample(nrow(testing_set), 500)
# x_test <- testing_set[index,-ncol(testing_set)]
# y_test <- testing_set$went_on_backorder[index]
# -----------------------
# (below switch to full size data set for the final report.)
# (Wholeset: 30 min run time)
# -----------------------
x <- training_set_down[ ,-ncol(training_set_down)]
y <- training_set_down$went_on_backorder
x_test <- testing_set[ ,-ncol(testing_set)]
y_test <- testing_set$went_on_backorder
# -----------------------

# 3.2 kNN Model

# Due to the large number of predictors, Generative Models such as LDA and QDA are not good options. 
# Classification and Regression Trees (CART) fit this situation because they are not impacted by the large number of predictors. 
# Before starting with Random Forest which takes over 30 min computing on my laptop, I use kNN as the baseline model.
# set.seed(7) # if using R 3.5 or earlier
set.seed(7, sample.kind = "Rounding") # if using R 3.6 or later
train_knn <- train(x, y, method = "knn")
# tuning parameters chosen
ggplot(train_knn, highlight = TRUE)
train_knn$bestTune
# Apply the fit model to the test set and see result.
knn_preds <- predict(train_knn, x_test)
confusionMatrix(knn_preds, y_test)$overall[["Accuracy"]]

# 3.3 Random Forest Model

# Let's build Random Forest Model.

# set.seed(7) # if using R 3.5 or earlier
set.seed(7, sample.kind = "Rounding") # if using R 3.6 or later
train_rf <- train(x, y, method = "rf")
# tuning parameters chosen
ggplot(train_rf, highlight = TRUE)
train_rf$bestTune
# Apply the fit model to the test set and see result.
rf_preds <- predict(train_rf, x_test)
confusionMatrix(rf_preds, y_test)$overall[["Accuracy"]]
# Variance importance analysis shows us the current inventory level and 3-month sales forecast is the most important factor impacting backorders. They are followed up by other period forecasts, supplier performance and past sales.
# This indeed makes perfect sense compared to real world.
imp <- varImp(train_rf)
imp

# 4. Results

# Random Forest achieved better accuracy than the kNN Model.
# However, accuracy is not a good KPI here because only 0.669% of the training data is positive. It means our model can simply just predict everything to be negative, and reaching 99.33% accuracy.
# Instead, we need to look at Sensitivity and Specificity. 
# For example, if back order will cause big trouble like losing customer, market share, revenue and so on. And the relative cost of maintaining a high inventory is less of a concern for the business, I would pick the model with higher sensitivity.
# On contrast, if inventory and the cost of refilling a supplier order is more of a concern to the business rather than having back orders, I would pick or tune the model with higher specificity.
confusionMatrix(knn_preds, y_test)$byClass[1:2]
confusionMatrix(rf_preds, y_test)$byClass[1:2]

# While eventually it is up to the business to decide model based on the sensitivity and specificity, the RoC Curve can tell us how much the model is capable of distinguishing between classes. Higher the AUC, the better the model is at predicting 0 classes as 0 and 1 classes as 1.
# Therefore we will use AUC to decide our final model.
knn_preds_prob <- predict(train_knn, x_test, type="prob")
pred_knn = prediction(knn_preds_prob[,2], as.numeric(y_test))
perf_knn = performance(pred_knn,"tpr","fpr")
plot(perf_knn, col="red")
abline(a = 0, b = 1) 
# Here is the AUC of kNN Model.
auc = performance(pred_knn, measure = "auc")
print(auc@y.values)

rf_preds_prob <- predict(train_rf, x_test, type="prob")
pred_rf = prediction(rf_preds_prob[,2], as.numeric(y_test))
perf_rf = performance(pred_rf,"tpr","fpr")
plot(perf_rf, add = TRUE, col="blue")
abline(a = 0, b = 1) 
# Here is the AUC of Random Forest Model.
auc = performance(pred_rf, measure = "auc")
print(auc@y.values)

# As you can see from the chart above, the Random Forest Model has larger AUC (Area under the RoC Curve) Score than kNN. Therefore for the purpose of this project, I'm choosing Random Forest Model.

# 5. Conclusions

# After comparing the AUC Score between the two models, I end up chose the Random Forest Model. However, it is important to note that the business eventually get to decide the model and parameters based on their unique situation - some could focus on higher sensitivity and some could weigh more on the Specificity. In summary, it is important for the the business to start using this model to drive their daily business asap therefore realizing the business value.
# Meanwhile, there are also limitations on this final model. Due to the limited computation power on my laptop, I was unable to tune additional values for the parameters except the default ones. All the values of the remaining predictors are included in the model without any data quality check due to the lack of Subject Matter Experts' input on context of these data.
# Looking forward, I would like to get input from the users of the IT system. Their knowledge would help me to further reduce the number of predictors, removing predictor overlap and improve data quality.
# I would also consider upsampling methods such as SMOTE and see how the model performance change. Matrix factorization would be another method to consider as well.
# I hope to obtain additional data fields from their IT system such as the time stamp, location and so on. I can then integrate 3rd party data such as weather and traffic to enhance the dataset and improve model performance.

# 6. Reference

