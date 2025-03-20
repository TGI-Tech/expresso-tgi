# Configure AWS Provider
provider "aws" {
  region = "us-east-1"
}

# Terraform configuration
terraform {
  required_version = "> 0.14"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.67"  # Updated for better EKS 1.26 compatibility
    }
    
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.9.0"  # Updated for better EKS compatibility
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20.0"  # Added for EKS management
    }
  }
}

# Configure Kubernetes Provider
provider "kubernetes" {
  host                   = aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.eks.certificate_authority[0].data)
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.eks.name]
    command     = "aws"
  }
}