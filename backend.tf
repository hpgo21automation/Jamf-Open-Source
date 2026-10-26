# Remote state — GCS.
#
# State lives in a shared GCS bucket, namespaced under a `jamf-tf/` prefix so
# keys never collide with other repos using the same bucket. Replace
# `your-terraform-state-bucket` with your own bucket name.
#
# The GCS backend does native state locking — a `.tflock` object written next
# to the state in the same bucket — so no separate lock table (the S3/DynamoDB
# equivalent) is required.
#
# CI/apply supplies GOOGLE_CREDENTIALS with read/write on the bucket prefix.
#
# One-time migration from local state (run by a human — see README,
# "Remote state (GCS)"):
#   terraform init -migrate-state
terraform {
  backend "gcs" {
    bucket = "your-terraform-state-bucket"
    prefix = "jamf-tf"
  }
}
