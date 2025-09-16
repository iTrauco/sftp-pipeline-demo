terraform {
  backend "gcs" {
    bucket = "trauco-deloitte-playground-tfstate"
    prefix = "sftp-demo/state"
  }
}
