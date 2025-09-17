resource "google_filestore_instance" "nfs" {
  name     = "sftp-storage"
  location = var.zone
  tier     = "BASIC_HDD"
  
  file_shares {
    capacity_gb = 1024
    name        = "share1"
  }
  
  networks {
    network = "default"
    modes   = ["MODE_IPV4"]
  }
}

resource "google_storage_bucket" "archive" {
  name     = "${var.project_id}-sftp-archive"
  location = "US"
}