terraform {
  required_version = ">= 1.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
  
  backend "gcs" {
    bucket = "genai-mlops-terraform-state"
    prefix = "terraform/state"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# VPC Configuration
resource "google_compute_network" "vpc" {
  name                    = "genai-mlops-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "genai-mlops-subnet"
  ip_cidr_range = "10.0.0.0/16"
  network       = google_compute_network.vpc.id
  region        = var.region
  
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.1.0.0/16"
  }
  
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.2.0.0/16"
  }
}

# GKE Cluster
resource "google_container_cluster" "primary" {
  name     = "genai-mlops-cluster"
  location = var.region
  
  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name
  
  initial_node_count = 1
  
  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }
  
  release_channel {
    channel = "REGULAR"
  }
  
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  
  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
  }
}

# Node Pools
resource "google_container_node_pool" "general" {
  name       = "general"
  cluster    = google_container_cluster.primary.name
  location   = var.region
  node_count = 2

  node_config {
    machine_type = "n1-standard-4"
    
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    labels = {
      environment = var.environment
      project     = "genai-mlops"
    }
  }
  
  autoscaling {
    min_node_count = 1
    max_node_count = 10
  }
}

resource "google_container_node_pool" "gpu" {
  name       = "gpu"
  cluster    = google_container_cluster.primary.name
  location   = var.region
  node_count = 1

  node_config {
    machine_type = "n1-standard-4"
    
    guest_accelerator {
      type  = "nvidia-tesla-t4"
      count = 1
    }
    
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    labels = {
      environment = var.environment
      project     = "genai-mlops"
      gpu         = "true"
    }
    
    taint {
      key    = "nvidia.com/gpu"
      value  = "true"
      effect = "NO_SCHEDULE"
    }
  }
  
  autoscaling {
    min_node_count = 0
    max_node_count = 4
  }
}

# Cloud Storage Bucket for Model Artifacts
resource "google_storage_bucket" "model_artifacts" {
  name          = "genai-mlops-model-artifacts-${var.environment}"
  location      = var.region
  force_destroy = false
  
  versioning {
    enabled = true
  }
  
  uniform_bucket_level_access = true
  
  labels = {
    environment = var.environment
    project     = "genai-mlops"
  }
}

# Container Registry
resource "google_container_registry" "registry" {
  project  = var.project_id
  location = "US"
}

# Cloud Logging
resource "google_logging_project_bucket_config" "basic" {
  project        = var.project_id
  location       = var.region
  retention_days = 30
  bucket_id      = "_Default"
}

# IAM
resource "google_service_account" "gke_sa" {
  account_id   = "genai-mlops-gke-sa"
  display_name = "GKE Service Account"
}

resource "google_project_iam_member" "gke_sa_roles" {
  for_each = toset([
    "roles/storage.objectViewer",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/artifactregistry.reader"
  ])
  
  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}

# Outputs
output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.primary.endpoint
}

output "cluster_ca_certificate" {
  description = "GKE cluster CA certificate"
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "model_artifacts_bucket" {
  description = "GCS bucket for model artifacts"
  value       = google_storage_bucket.model_artifacts.name
}

output "container_registry" {
  description = "Container Registry URL"
  value       = google_container_registry.registry.id
} 