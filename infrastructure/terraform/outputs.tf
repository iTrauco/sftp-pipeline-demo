output "filestore_ip" {
  value = google_filestore_instance.nfs.networks[0].ip_addresses[0]
}

output "archive_bucket" {
  value = google_storage_bucket.archive.name
}

output "cluster_name" {
  value = google_container_cluster.sftp_cluster.name
}
