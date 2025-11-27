# Elasticsearch Cluster on AWS EKS

A production-ready 3-node Elasticsearch 8.11.0 cluster deployed on AWS EKS with high availability, fault isolation, and automatic node discovery.

## 🎯 Overview

This project provides everything you need to deploy a **highly available Elasticsearch cluster** to AWS EKS. The cluster is designed for teams that need a fault-tolerant, scalable search infrastructure.

**Key Features:**
- ✅ 3-node cluster with automatic discovery
- ✅ High availability - survives single node failure
- ✅ Pod anti-affinity - nodes spread across worker nodes
- ✅ Pod Disruption Budget - maintains 2+ nodes during maintenance
- ✅ Health probes - liveness and readiness checks
- ✅ Easy troubleshooting - clear documentation and scripts
- ✅ Production-ready - security and resource limits configured
- ✅ AWS EKS optimized - tested on eu-central-1 region

## 📋 Prerequisites

Before deploying, ensure you have:

- **kubectl** configured to connect to your EKS cluster
- **kubeconfig** properly set up

Verify your setup:
```bash
kubectl cluster-info
kubectl config current-context
aws eks describe-cluster --name elasticsearch-cluster --region eu-central-1
```

## 🚀 Quick Start - Deploy in 5 Minutes

### 1️⃣ Create Namespace
```bash
kubectl create namespace elasticsearch
```

### 2️⃣ Deploy Elasticsearch Cluster
```bash
# Apply the complete StatefulSet (3 nodes, ConfigMap, PDB, services)
kubectl apply -f manifests/statefulset-3node.yaml

# Watch pods starting up (2-3 minutes)
kubectl get pods -n elasticsearch -w
```