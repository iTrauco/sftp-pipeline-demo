provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_container_cluster" "sftp_cluster" {
  name     = "sftp-demo"
  location = var.zone
  
  initial_node_count  = 2
  deletion_protection = false
  
  node_config {
    machine_type = "e2-medium"
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}
