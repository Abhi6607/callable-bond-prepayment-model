library(survival)

# ---- Load your saved parsed data ----
performance <- read.delim(
  "sample_pref_2015.txt",
  sep = "|", header = FALSE, stringsAsFactors = FALSE,
  colClasses = "character"
)
colnames(performance)[1:11] <- c(
  "loan_id", "reporting_period", "current_upb", "delinquency_status",
  "loan_age", "remaining_months", "defect_settlement_date",
  "modification_flag", "zero_balance_code", "zero_balance_date",
  "current_rate"
)
performance <- performance[, 1:11]
performance$loan_age <- as.numeric(performance$loan_age)
performance$zero_balance_code <- trimws(performance$zero_balance_code)

origination <- read.delim(
  "sample_orig_2015.txt",
  sep = "|", header = FALSE, stringsAsFactors = FALSE,
  colClasses = "character"
)
colnames(origination)[1:24] <- c(
  "credit_score", "first_payment_date", "first_time_homebuyer_flag",
  "maturity_date", "msa", "mi_pct", "num_units", "occupancy_status",
  "orig_cltv", "orig_dti", "orig_upb", "orig_ltv", "orig_rate",
  "channel", "ppm_flag", "product_type", "property_state",
  "property_type", "postal_code", "loan_id", "loan_purpose",
  "orig_loan_term", "num_borrowers", "seller_name"
)
origination <- origination[, 1:24]
origination$orig_rate <- as.numeric(origination$orig_rate)
origination$credit_score <- as.numeric(origination$credit_score)
origination$orig_ltv <- as.numeric(origination$orig_ltv)

# ---- Step 2: collapse PMMS to monthly average ----
pmms <- read.csv("MORTGAGE30US.csv")
pmms$observation_date <- as.Date(pmms$observation_date)
pmms$year_month <- format(pmms$observation_date, "%Y%m")

pmms_monthly <- aggregate(MORTGAGE30US ~ year_month, data = pmms, FUN = mean)
names(pmms_monthly)[2] <- "market_rate"

# ---- Step 3: join market rate onto performance by reporting_period ----
performance <- merge(performance, pmms_monthly,
                      by.x = "reporting_period", by.y = "year_month",
                      all.x = TRUE)

# bring in orig_rate per loan
performance <- merge(performance, origination[, c("loan_id", "orig_rate")],
                      by = "loan_id", all.x = TRUE)

performance$rate_incentive <- performance$orig_rate - performance$market_rate

# ---- Step 4: build counting-process (start, stop) intervals ----
performance <- performance[order(performance$loan_id, performance$loan_age), ]

performance$tstart <- ave(performance$loan_age, performance$loan_id,
                           FUN = function(x) c(0, head(x, -1)))
performance$tstop <- performance$loan_age

performance$event <- ifelse(
  !is.na(performance$zero_balance_code) & performance$zero_balance_code == "01",
  1, 0
)

# drop zero-length intervals (tstart == tstop), coxph rejects these
long_data <- performance[performance$tstart < performance$tstop, ]

# bring in remaining static covariates
long_data <- merge(long_data,
                    origination[, c("loan_id", "credit_score", "orig_ltv")],
                    by = "loan_id", all.x = TRUE)

# ---- Fit the time-varying Cox model ----
tv_model <- coxph(Surv(tstart, tstop, event) ~ rate_incentive + credit_score + orig_ltv,
                   data = long_data)
summary(tv_model)

cox.zph(tv_model)