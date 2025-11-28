# Environment Variables Reference

This document describes all configurable environment variables used in the Elasticsearch deployment scripts.

## Overview

All hardcoded values in test and data insertion scripts have been replaced with environment variables. Use these to customize script behavior without editing the scripts themselves.

---

## Available Environment Variables

### Elasticsearch Connection

| Variable | Default | Description |
|----------|---------|-------------|
| `ES_ENDPOINT` | `http://localhost:9200` | Elasticsearch API endpoint URL |
| `ES_NAMESPACE` | `elasticsearch` | Kubernetes namespace where Elasticsearch is deployed |
| `ES_POD_NAME` | `es-0` | Name of the Elasticsearch pod to use for operations |

### Index Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `ES_INDEX_NAME` | `delivery-satisfaction` | Name of the Elasticsearch index for delivery data |
| `ES_SHARDS` | `1` | Number of shards when creating an index |
| `ES_REPLICAS` | `0` | Number of replicas when creating an index |

---

## Usage Examples

### PowerShell

#### Set environment variables for a single session:
```powershell
$env:ES_ENDPOINT = "http://10.0.1.100:9200"
$env:ES_NAMESPACE = "prod-elasticsearch"
$env:ES_INDEX_NAME = "delivery-data"
$env:ES_POD_NAME = "es-prod-0"

# Run the script with custom settings
.\insert-data-and-test.sh
```

#### Set environment variables permanently (for current user):
```powershell
[System.Environment]::SetEnvironmentVariable("ES_ENDPOINT", "http://10.0.1.100:9200", "User")
[System.Environment]::SetEnvironmentVariable("ES_NAMESPACE", "prod-elasticsearch", "User")
[System.Environment]::SetEnvironmentVariable("ES_INDEX_NAME", "delivery-data", "User")
```

#### Run test with specific endpoint:
```powershell
$env:ES_ENDPOINT = "http://remote-cluster:9200"
.\test-elasticsearch.sh

# Or pass as parameter
.\test-elasticsearch.sh -Endpoint "http://remote-cluster:9200"
```

### Bash / Shell

#### Set environment variables for a single session:
```bash
export ES_ENDPOINT="http://10.0.1.100:9200"
export ES_NAMESPACE="prod-elasticsearch"
export ES_INDEX_NAME="delivery-data"
export ES_POD_NAME="es-prod-0"
export ES_SHARDS="3"
export ES_REPLICAS="2"

# Run the script
./test-elasticsearch.sh
```

#### Set environment variables permanently:
```bash
# Add to ~/.bashrc or ~/.zshrc
export ES_ENDPOINT="http://10.0.1.100:9200"
export ES_NAMESPACE="prod-elasticsearch"
export ES_INDEX_NAME="delivery-data"

# Reload shell
source ~/.bashrc
```

---

## Script-Specific Variables

### insert-data-and-test.sh

**Supported Environment Variables:**
- `ES_POD_NAME` - Which pod to execute commands against
- `ES_NAMESPACE` - Kubernetes namespace
- `ES_INDEX_NAME` - Index to create and populate
- `ES_SHARDS` - Number of shards for the index
- `ES_REPLICAS` - Number of replicas for the index

**Example:**
```powershell
# Create index with 3 shards and 2 replicas in production namespace
$env:ES_NAMESPACE = "production"
$env:ES_INDEX_NAME = "delivery-prod"
$env:ES_SHARDS = "3"
$env:ES_REPLICAS = "2"

.\insert-data-and-test.sh
```

### test-elasticsearch.sh

**Supported Environment Variables:**
- `ES_ENDPOINT` - Elasticsearch endpoint
- `ES_NAMESPACE` - Kubernetes namespace
- `ES_POD_NAME` - Pod name for operations

**Example:**
```powershell
# Test remote cluster
$env:ES_ENDPOINT = "http://10.0.1.100:9200"
.\test-elasticsearch.sh
```

### test-delivery-data.sh

**Supported Environment Variables:**
- `ES_ENDPOINT` - Elasticsearch endpoint
- `ES_INDEX_NAME` - Index name to test

**Example:**
```powershell
# Test production delivery data
$env:ES_ENDPOINT = "http://prod-es.company.com:9200"
$env:ES_INDEX_NAME = "delivery-satisfaction-prod"

.\test-delivery-data.sh
```

---

## Common Scenarios

### Development Environment

```powershell
# Use local Elasticsearch
$env:ES_ENDPOINT = "http://localhost:9200"
$env:ES_NAMESPACE = "elasticsearch"
$env:ES_INDEX_NAME = "delivery-satisfaction"

.\insert-data-and-test.sh
.\test-delivery-data.sh
```

### Production Deployment

```powershell
# Connect to production cluster
$env:ES_ENDPOINT = "http://es-prod.internal:9200"
$env:ES_NAMESPACE = "prod-elasticsearch"
$env:ES_INDEX_NAME = "delivery-satisfaction-prod"
$env:ES_POD_NAME = "es-prod-0"
$env:ES_SHARDS = "5"
$env:ES_REPLICAS = "3"

.\insert-data-and-test.sh
.\test-elasticsearch.sh
.\test-delivery-data.sh
```

### Multi-Cluster Testing

```powershell
# Test Cluster 1
$env:ES_NAMESPACE = "staging-1"
$env:ES_POD_NAME = "es-1-0"
.\test-elasticsearch.sh

# Test Cluster 2
$env:ES_NAMESPACE = "staging-2"
$env:ES_POD_NAME = "es-2-0"
.\test-elasticsearch.sh
```

### Custom Index Configuration

```powershell
# Create small development index
$env:ES_INDEX_NAME = "dev-delivery"
$env:ES_SHARDS = "1"
$env:ES_REPLICAS = "0"
.\insert-data-and-test.sh

# Create large production index
$env:ES_INDEX_NAME = "prod-delivery"
$env:ES_SHARDS = "10"
$env:ES_REPLICAS = "3"
.\insert-data-and-test.sh
```

---

## Docker / Kubernetes Environment Variables

### Running scripts in containers:

```dockerfile
# Dockerfile
ENV ES_ENDPOINT="http://elasticsearch:9200"
ENV ES_NAMESPACE="elasticsearch"
ENV ES_INDEX_NAME="delivery-satisfaction"
```

### Kubernetes ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: es-script-config
data:
  ES_ENDPOINT: "http://elasticsearch:9200"
  ES_NAMESPACE: "elasticsearch"
  ES_INDEX_NAME: "delivery-satisfaction"
  ES_SHARDS: "3"
  ES_REPLICAS: "2"
---
apiVersion: batch/v1
kind: Job
metadata:
  name: es-test-job
spec:
  template:
    spec:
      containers:
      - name: tester
        image: powershell:latest
        envFrom:
        - configMapRef:
            name: es-script-config
        command:
        - pwsh
        - -Command
        - |
          .\insert-data-and-test.sh
          .\test-elasticsearch.sh
      restartPolicy: Never
```

---

## Validation and Defaults

### How Environment Variables Work

1. **Fallback to defaults**: If an environment variable is not set, the script uses its default value
2. **Command-line override**: Some scripts accept command-line parameters that override environment variables

```powershell
# Environment variable
$env:ES_ENDPOINT = "http://custom:9200"
.\test-elasticsearch.sh

# Override with parameter
.\test-elasticsearch.sh -Endpoint "http://override:9200"
# Uses "http://override:9200"
```

### Checking Current Values

```powershell
# Display all ES-related environment variables
Get-ChildItem env: | Where-Object { $_.Name -match "^ES_" }

# Display specific variable
$env:ES_ENDPOINT
$env:ES_NAMESPACE
```

---

## Troubleshooting

### Variables Not Taking Effect

1. **Check if variable is set:**
```powershell
# PowerShell
Write-Host $env:ES_ENDPOINT

# Bash
echo $ES_ENDPOINT
```

2. **Verify script uses the variable:**
```powershell
# Add debug output to script
Write-Host "Using namespace: $namespace" -ForegroundColor Yellow
```

3. **Use correct syntax:**
```powershell
# Correct
$env:ES_NAMESPACE = "elasticsearch"

# Incorrect (won't work)
$ES_NAMESPACE = "elasticsearch"
```

### Connection Issues

```powershell
# Verify endpoint is accessible
$env:ES_ENDPOINT
Invoke-WebRequest -Uri $env:ES_ENDPOINT -UseBasicParsing

# Check namespace
kubectl get namespace $env:ES_NAMESPACE

# Verify pod exists
kubectl get pods -n $env:ES_NAMESPACE | Select-String $env:ES_POD_NAME
```

---

## Best Practices

1. **Use environment variables for environment-specific settings**
   - Dev: localhost, small indexes
   - Prod: remote endpoint, large indexes with replicas

2. **Document custom values**
   - Add comments to scripts showing which variables are used
   - Maintain a configuration file listing all environment variables

3. **Version control**
   - Don't commit `.env` files with secrets
   - Use `.env.example` file to show required variables

4. **Automation**
   - Use CI/CD to set environment variables automatically
   - Store sensitive values in secret managers (HashiCorp Vault, AWS Secrets Manager)

---

## Reference

All scripts have been updated to support environment variables as of version 1.0.

- `insert-data-and-test.sh` - Data insertion with configurable index
- `test-elasticsearch.sh` - Cluster testing
- `test-delivery-data.sh` - Delivery data validation

For more information, see individual script headers.
