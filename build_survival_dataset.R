# ============================================================
# build_survival_dataset.R  (base R only, no packages needed)
# ============================================================

# ---- 1. Read the origination file (force everything to text) ----
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

# convert the columns that should actually be numeric
num_cols_orig <- c("credit_score", "mi_pct", "num_units", "orig_cltv",
                    "orig_dti", "orig_upb", "orig_ltv", "orig_rate",
                    "orig_loan_term", "num_borrowers")
for (col in num_cols_orig) {
  origination[[col]] <- as.numeric(origination[[col]])
}

# ---- 2. Read the performance file (force everything to text) ----
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

num_cols_perf <- c("current_upb", "loan_age", "remaining_months", "current_rate")
for (col in num_cols_perf) {
  performance[[col]] <- as.numeric(performance[[col]])
}

performance$zero_balance_code <- trimws(performance$zero_balance_code)

# ---- 3. Collapse performance to one row per loan (base R) ----
performance <- performance[order(performance$loan_id, performance$loan_age), ]
last_idx <- !duplicated(performance$loan_id, fromLast = TRUE)
survival_table <- performance[last_idx, ]

survival_table$duration <- survival_table$loan_age

survival_table$event <- ifelse(
  is.na(survival_table$zero_balance_code) | survival_table$zero_balance_code == "",
  0,
  ifelse(survival_table$zero_balance_code == "01", 1, 0)
)

survival_table <- survival_table[, c("loan_id", "duration", "event", "zero_balance_code")]

# ---- 4. Join with origination covariates ----
dataset <- merge(survival_table, origination, by = "loan_id", all.x = TRUE)

# ---- 5. Quick sanity checks ----
cat("Origination rows:", nrow(origination), "\n")
cat("Performance rows:", nrow(performance),
    " (", length(unique(performance$loan_id)), "unique loans )\n")
cat("Survival table rows:", nrow(survival_table), "\n")
cat("Event rate:", mean(dataset$event, na.rm = TRUE), "\n")

# ---- 6. Save output ----
write.csv(dataset, "callable_bond_survival_sample.csv", row.names = FALSE)

print(dataset)