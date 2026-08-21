output "bucket_name" {
  value = google_storage_bucket.mlops.name
}

output "vm_ip" {
  value = google_compute_instance.mlops_serve.network_interface[0].access_config[0].nat_ip
}

output "service_account_email" {
  value = google_service_account.mlops_sa.email
}

output "workload_identity_provider" {
  value       = google_iam_workload_identity_pool_provider.github.name
  description = "Full resource name for the WORKLOAD_IDENTITY_PROVIDER GitHub secret"
}
