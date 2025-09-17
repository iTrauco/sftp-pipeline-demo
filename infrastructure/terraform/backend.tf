terraform {
  backend "gcs" {
    prefix = "sftp-demo/state"
  }
}
