# Get the current AWS account ID
data "aws_caller_identity" "current" {}

# Resource: aws_iam_role for EKS Cluster
resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "amazon_eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "amazon_eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "amazon_ebs_csi_driver_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# EKS Cluster
resource "aws_eks_cluster" "eks" {
  name     = "eks"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.26"

  vpc_config {
    endpoint_private_access = false
    endpoint_public_access  = true
    public_access_cidrs    = ["0.0.0.0/0"]

    subnet_ids = [
      aws_subnet.public_1.id,
      aws_subnet.public_2.id
    ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.amazon_eks_cluster_policy,
    aws_iam_role_policy_attachment.amazon_eks_cni_policy,
    aws_iam_role_policy_attachment.amazon_ebs_csi_driver_policy
  ]
}

# Extract OIDC provider URL
locals {
  oidc_provider = replace(aws_eks_cluster.eks.identity[0].oidc[0].issuer, "https://", "")
}

# Get EKS OIDC Certificate Thumbprint
data "tls_certificate" "eks" {
  url = aws_eks_cluster.eks.identity[0].oidc[0].issuer
}

# Create OIDC Provider
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.eks.identity[0].oidc[0].issuer
}

# Create IAM role for EBS CSI Driver
resource "aws_iam_role" "ebs_csi_driver" {
  name = "eks-ebs-csi-driver"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_provider}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_provider}:sub" : "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          }
        }
      }
    ]
  })

  depends_on = [aws_iam_openid_connect_provider.eks]
}

# Attach policy to EBS CSI Driver role
resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_driver.name
}

# Helm provider configuration
# provider "helm" {
#   kubernetes {
#     host                   = aws_eks_cluster.eks.endpoint
#     cluster_ca_certificate = base64decode(aws_eks_cluster.eks.certificate_authority[0].data)
#     exec {
#       api_version = "client.authentication.k8s.io/v1beta1"
#       args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.eks.name]
#       command     = "aws"
#     }
#   }
# }

# # Install EBS CSI Driver using Helm
# resource "helm_release" "aws_ebs_csi_driver" {
#   name       = "aws-ebs-csi-driver"
#   namespace  = "kube-system"
#   repository = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
#   chart      = "aws-ebs-csi-driver"

#   set {
#     name  = "controller.serviceAccount.create"
#     value = "true"
#   }

#   set {
#     name  = "controller.serviceAccount.name"
#     value = "ebs-csi-controller-sa"
#   }

#   set {
#     name  = "controller.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
#     value = aws_iam_role.ebs_csi_driver.arn
#   }

#   depends_on = [
#     aws_eks_cluster.eks,
#     aws_iam_role_policy_attachment.ebs_csi_driver,
#     aws_iam_openid_connect_provider.eks
#   ]
  
# }