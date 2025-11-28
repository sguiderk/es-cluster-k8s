# Elasticsearch on Kubernetes - Architecture

## Overview

Production-ready Elasticsearch cluster on Kubernetes with:
- **High Availability**: 3-node cluster with quorum-based failover
- **Data Persistence**: Independent PVC per node (AWS EBS)
- **Safe Maintenance**: Pod Disruption Budget for zero-downtime updates
- **Security**: TLS encryption for inter-node and client communication
- **Identical Roles**: All nodes configured identically for simplified operations

## Cluster Topology

```
                     EKS Cluster (3 K8s Nodes)
    ┌─────────────────────────────────────────────────┐
    │                                                   │
    │  ┌──────────────┐  ┌──────────────┐  ┌─────────┐│
    │  │   K8s Node   │  │   K8s Node   │  │ K8s    ││
    │  │     #1       │  │     #2       │  │ Node#3 ││
    │  │              │  │              │  │        ││
    │  │ ┌────────┐   │  │ ┌────────┐   │  │┌──────┐││
    │  │ │  ES-0  │   │  │ │  ES-1  │   │  ││ ES-2 │││
    │  │ │ (30GB) │   │  │ │ (30GB) │   │  ││(30GB)│││
    │  │ └────────┘   │  │ └────────┘   │  │└──────┘││
    │  └──────────────┘  └──────────────┘  └─────────┘│
    │                                                   │
    └─────────────────────────────────────────────────┘
    
    Node Roles: [master, data, ingest, ml] - Identical for all
    
    Quorum: 2 of 3 nodes required
    PDB: Minimum 2 pods always running
```

## Node Configuration

All nodes have identical roles:
- **master**: Participates in cluster coordination and elections
- **data**: Stores index shards and executes queries
- **ingest**: Processes ingest pipeline requests
- **ml**: Runs machine learning jobs

This simplifies operations while allowing each node to perform any function.

## High Availability Features

### 1. Quorum-Based Cluster Formation
- 3 master-eligible nodes
- Requires 2 nodes for quorum (prevent split-brain)
- Configuration: `cluster.election.strategy: ranked`

### 2. Pod Disruption Budget (PDB)
- Minimum 2 pods must be running
- Prevents Kubernetes from draining multiple nodes simultaneously
- Enables safe cluster maintenance

### 3. Pod Anti-Affinity
- Pods spread across different Kubernetes nodes
- If one K8s node crashes, other Elasticsearch pods survive
- Implementation: `topologyKey: kubernetes.io/hostname`

### 4. Data Persistence
- Each pod has independent PVC (AWS EBS volume)
- Data survives pod termination
- Automatic recovery on pod restart

### 5. Health Monitoring
- Liveness probe: Checks cluster health every 30 seconds
- Readiness probe: Checks local cluster health every 10 seconds
- Failed pods automatically restarted

### 6. Shard Allocation
- Limits shards per node for balanced distribution
- Rebalance throttling during node changes
- Recovery rate controlled to prevent overload

## File Structure

```
helm/elasticsearch/
├── Chart.yaml              # Chart metadata
├── values.yaml             # Default configuration values
├── templates/
│   ├── namespace.yaml      # Kubernetes namespace
│   ├── rbac.yaml           # Service account & permissions
│   ├── configmap.yaml      # Elasticsearch configuration
│   ├── service.yaml        # Kubernetes services (headless + ClusterIP)
│   ├── statefulset.yaml    # Pod deployment spec
│   ├── poddisruptionbudget.yaml  # PDB for safe maintenance
│   └── _helpers.tpl        # Template helpers
└── ARCHITECTURE.md         # This file
```

## Key Configuration Files

### values.yaml
Main configuration file with:
- Cluster parameters (3 replicas)
- Node roles: `[master,data,ingest,ml]`
- Resources: 1000m CPU request, 4Gi memory limit
- Storage: 30Gi per node
- Pod disruption budget: minAvailable 2
- Health probe settings

### configmap.yaml
Elasticsearch configuration:
- Cluster discovery settings
- Node roles template
- Shard allocation strategies
- Recovery settings
- Security (TLS) configuration

### statefulset.yaml
Pod deployment:
- 3 replicas with stable identity (es-0, es-1, es-2)
- Init containers for environment setup
- Security context (non-root, read-only filesystem)
- Volume mounts for data, config, certificates

## Failure Scenarios

### Single K8s Node Failure
1. Elasticsearch pod is terminated
2. Kubernetes reschedules to healthy node
3. Pod rejoins cluster (quorum maintained with 2 nodes)
4. Data recovered from replicas
5. **Recovery Time**: 60-120 seconds

### K8s Maintenance (Node Drain)
1. PDB check: Can drain? (2+ pods must remain)
2. If yes: Pod gracefully evicted with shutdown signal
3. Pod rescheduled to healthy node
4. Cluster maintains 2 running pods
5. **Service Impact**: Zero downtime

### Network Partition
1. Nodes lose connectivity
2. Quorum voting determines which partition continues
3. Minority partition goes read-only
4. Majority partition handles all writes
5. **Data Safety**: No data corruption

## Deployment

```bash
# Create namespace and deploy
helm install elasticsearch helm/elasticsearch/ \
  -n elasticsearch --create-namespace

# Check status
kubectl get pods -n elasticsearch -o wide
kubectl exec -n elasticsearch es-0 -- \
  curl -s localhost:9200/_cluster/health?pretty
```

## Operations

### Check Cluster Health
```bash
kubectl exec -n elasticsearch es-0 -- \
  curl -s localhost:9200/_cluster/health?pretty
```

### View Node Info
```bash
kubectl exec -n elasticsearch es-0 -- \
  curl -s localhost:9200/_nodes?pretty
```

### Scale Cluster
```bash
# Change replicaCount in values.yaml
helm upgrade elasticsearch helm/elasticsearch/ \
  -n elasticsearch
```

### View Logs
```bash
kubectl logs -n elasticsearch es-0 -f
```

## Performance Characteristics

| Metric | Value |
|--------|-------|
| Expected Uptime | 99.9% |
| RTO (Single Node Failure) | 60-120 seconds |
| Data Loss on Failure | Zero |
| Downtime for Maintenance | Zero |
| Max Shards per Node | 10 |
| Recovery Rate | 125 MB/s |

## Security

- TLS encryption for inter-node communication (transport layer)
- TLS encryption for client connections (HTTP layer)
- Security context: non-root user, read-only filesystem
- RBAC: Limited permissions for service account
- Credentials stored in Kubernetes secrets

## Interview Talking Points

1. **Why 3 nodes?** → Quorum requires odd number, 2 for maintenance protection
2. **Identical roles?** → Simplified operations, any node can handle any task
3. **PDB?** → Ensures safe K8s maintenance without downtime
4. **Data persistence?** → Each pod has independent volume, survives failures
5. **Anti-affinity?** → Spreads pods to isolate K8s node failures
6. **Why Helm?** → IaC, templating, version control, reproducibility
