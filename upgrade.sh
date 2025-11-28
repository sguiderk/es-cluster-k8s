#!/bin/bash
# Elasticsearch Operational Runbooks
# Collection of automated procedures for daily operations

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="elasticsearch"
CLUSTER_NAME="elasticsearch"
ES_POD="es-0"

# Logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# ============================================================================
# HEALTH CHECK RUNBOOK
# ============================================================================
health_check() {
    log_info "Starting Elasticsearch cluster health check..."
    
    # Cluster health
    log_info "Checking cluster health..."
    HEALTH=$(kubectl exec -n $NAMESPACE $ES_POD -- \
        curl -s localhost:9200/_cluster/health?pretty)
    
    STATUS=$(echo "$HEALTH" | jq -r '.status')
    NODES=$(echo "$HEALTH" | jq -r '.number_of_nodes')
    UNASSIGNED=$(echo "$HEALTH" | jq -r '.unassigned_shards')
    PENDING=$(echo "$HEALTH" | jq -r '.number_of_pending_tasks')
    
    echo "  Status: $STATUS"
    echo "  Nodes: $NODES"
    echo "  Unassigned Shards: $UNASSIGNED"
    echo "  Pending Tasks: $PENDING"
    
    if [ "$STATUS" == "green" ] && [ "$UNASSIGNED" == "0" ] && [ "$PENDING" == "0" ]; then
        log_success "Cluster health is GREEN"
    else
        log_warn "Cluster health is $STATUS"
        [ "$UNASSIGNED" -gt 0 ] && log_warn "Found $UNASSIGNED unassigned shards"
        [ "$PENDING" -gt 0 ] && log_warn "Found $PENDING pending tasks"
    fi
    
    # Pod status
    log_info "Checking pod status..."
    POD_STATUS=$(kubectl get pods -n $NAMESPACE -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.phase}{" "}{.status.ready}{"\n"}{end}')
    echo "$POD_STATUS"
    
    # Disk usage
    log_info "Checking disk usage..."
    for i in 0 1 2; do
        POD="es-$i"
        DISK=$(kubectl exec -n $NAMESPACE $POD -- df -h /usr/share/elasticsearch/data | tail -1 | awk '{print $5}')
        echo "  $POD: $DISK"
    done
    
    # Memory usage
    log_info "Checking memory usage..."
    kubectl top pods -n $NAMESPACE --containers 2>/dev/null || log_warn "Metrics not available"
    
    log_success "Health check completed"
}

# ============================================================================
# SCALE UP RUNBOOK
# ============================================================================
scale_up() {
    log_info "Starting cluster scale-up..."
    
    CURRENT=$(kubectl get statefulset es -n $NAMESPACE -o jsonpath='{.spec.replicas}')
    TARGET=$((CURRENT + 1))
    
    log_info "Current replicas: $CURRENT"
    log_info "Target replicas: $TARGET"
    
    # Update values
    log_info "Updating Helm values..."
    sed -i "s/replicaCount: $CURRENT/replicaCount: $TARGET/" helm/elasticsearch/values.yaml
    
    # Apply upgrade
    log_info "Applying Helm upgrade..."
    helm upgrade elasticsearch ./helm/elasticsearch -n $NAMESPACE
    
    # Monitor
    log_info "Monitoring upgrade progress (this may take several minutes)..."
    kubectl rollout status statefulset/es -n $NAMESPACE --timeout=10m || true
    
    # Wait for new pod
    sleep 30
    kubectl wait --for=condition=ready pod/es-$((CURRENT)) \
        -n $NAMESPACE --timeout=300s 2>/dev/null || log_warn "Timeout waiting for pod"
    
    # Verify
    log_info "Verifying cluster health..."
    sleep 30
    kubectl exec -n $NAMESPACE $ES_POD -- \
        curl -s localhost:9200/_cluster/health?pretty | jq '.status'
    
    log_success "Scale-up completed to $TARGET nodes"
}

# ============================================================================
# SCALE DOWN RUNBOOK
# ============================================================================
scale_down() {
    log_info "Starting cluster scale-down..."
    
    CURRENT=$(kubectl get statefulset es -n $NAMESPACE -o jsonpath='{.spec.replicas}')
    TARGET=$((CURRENT - 1))
    
    if [ $TARGET -lt 3 ]; then
        log_error "Cannot scale below 3 nodes for high availability"
        exit 1
    fi
    
    log_info "Current replicas: $CURRENT"
    log_info "Target replicas: $TARGET"
    
    # Exclude node from allocation
    EXCLUDE_NODE="es-$TARGET"
    log_info "Excluding $EXCLUDE_NODE from allocation..."
    kubectl exec -n $NAMESPACE $ES_POD -- \
        curl -X PUT 'localhost:9200/_cluster/settings' \
        -H 'Content-Type: application/json' \
        -d "{
            \"transient\": {
                \"cluster.routing.allocation.exclude._name\": \"$EXCLUDE_NODE\"
            }
        }"
    
    # Wait for shards to move
    log_info "Waiting for shards to relocate (this may take several minutes)..."
    for i in {1..60}; do
        RELOCATING=$(kubectl exec -n $NAMESPACE $ES_POD -- \
            curl -s localhost:9200/_cluster/health?pretty | jq '.relocating_shards')
        if [ "$RELOCATING" == "0" ]; then
            log_success "All shards relocated"
            break
        fi
        echo -n "."
        sleep 5
    done
    echo ""
    
    # Update values
    log_info "Updating Helm values..."
    sed -i "s/replicaCount: $CURRENT/replicaCount: $TARGET/" helm/elasticsearch/values.yaml
    
    # Apply upgrade
    log_info "Applying Helm upgrade..."
    helm upgrade elasticsearch ./helm/elasticsearch -n $NAMESPACE
    
    # Remove allocation exclusion
    log_info "Removing allocation exclusion..."
    sleep 10
    kubectl exec -n $NAMESPACE $ES_POD -- \
        curl -X PUT 'localhost:9200/_cluster/settings' \
        -H 'Content-Type: application/json' \
        -d "{
            \"transient\": {
                \"cluster.routing.allocation.exclude._name\": null
            }
        }"
    
    # Verify
    log_info "Verifying cluster health..."
    sleep 30
    kubectl exec -n $NAMESPACE $ES_POD -- \
        curl -s localhost:9200/_cluster/health?pretty | jq '.status'
    
    log_success "Scale-down completed to $TARGET nodes"
}

# ============================================================================
# POD RECOVERY RUNBOOK
# ============================================================================
pod_recovery() {
    POD="${1:-es-0}"
    
    log_info "Starting pod recovery for $POD..."
    
    # Delete pod
    log_info "Deleting pod $POD..."
    kubectl delete pod $POD -n $NAMESPACE --ignore-not-found
    
    # Wait for new pod
    log_info "Waiting for new pod to start..."
    kubectl wait --for=condition=ready pod/$POD \
        -n $NAMESPACE --timeout=300s
    
    # Verify recovery
    log_info "Verifying cluster health..."
    sleep 10
    kubectl exec -n $NAMESPACE $ES_POD -- \
        curl -s localhost:9200/_cluster/health?pretty | jq '.status'
    
    log_success "Pod $POD recovered successfully"
}

# ============================================================================
# MANUAL BACKUP RUNBOOK
# ============================================================================
manual_backup() {
    TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
    SNAPSHOT_NAME="manual_backup_$TIMESTAMP"
    
    log_info "Creating backup: $SNAPSHOT_NAME"
    
    # Create snapshot
    kubectl exec -n $NAMESPACE $ES_POD -- \
        curl -X PUT "localhost:9200/_snapshot/s3_backup/$SNAPSHOT_NAME" \
        -H 'Content-Type: application/json' \
        -d '{
            "indices": "*",
            "include_global_state": true,
            "wait_for_completion": false
        }'
    
    log_info "Snapshot initiated. Monitoring progress..."
    
    # Monitor progress
    for i in {1..360}; do
        STATE=$(kubectl exec -n $NAMESPACE $ES_POD -- \
            curl -s "localhost:9200/_snapshot/s3_backup/$SNAPSHOT_NAME?pretty" | \
            jq -r '.snapshots[0].state')
        
        if [ "$STATE" == "SUCCESS" ]; then
            log_success "Backup completed successfully"
            break
        elif [ "$STATE" == "FAILED" ]; then
            log_error "Backup failed"
            exit 1
        fi
        
        echo -n "."
        sleep 10
    done
    echo ""
}

# ============================================================================
# RESTORE FROM BACKUP RUNBOOK
# ============================================================================
restore_backup() {
    SNAPSHOT_NAME="${1:-}"
    
    if [ -z "$SNAPSHOT_NAME" ]; then
        log_info "Available snapshots:"
        kubectl exec -n $NAMESPACE $ES_POD -- \
            curl -s 'localhost:9200/_snapshot/s3_backup/_all?pretty' | \
            jq '.snapshots[] | {name: .snapshot, state: .state, time: .start_time}'
        
        read -p "Enter snapshot name to restore: " SNAPSHOT_NAME
    fi
    
    log_warn "This will restore all indices from $SNAPSHOT_NAME"
    read -p "Continue? (yes/no): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        log_info "Restore cancelled"
        return
    fi
    
    log_info "Restoring from snapshot: $SNAPSHOT_NAME"
    
    # Restore
    kubectl exec -n $NAMESPACE $ES_POD -- \
        curl -X POST "localhost:9200/_snapshot/s3_backup/$SNAPSHOT_NAME/_restore" \
        -H 'Content-Type: application/json' \
        -d '{
            "indices": "*",
            "include_global_state": true,
            "include_aliases": true,
            "wait_for_completion": false
        }'
    
    log_info "Restore initiated. Monitoring progress..."
    
    # Monitor progress
    for i in {1..600}; do
        RECOVERY=$(kubectl exec -n $NAMESPACE $ES_POD -- \
            curl -s 'localhost:9200/_recovery?pretty' | \
            jq '.[] | length')
        
        if [ "$RECOVERY" == "0" ]; then
            log_success "Restore completed"
            break
        fi
        
        echo -n "."
        sleep 5
    done
    echo ""
    
    # Verify
    log_info "Verifying restored data..."
    kubectl exec -n $NAMESPACE $ES_POD -- \
        curl -s 'localhost:9200/_search?size=0' | jq '.hits.total.value'
}

# ============================================================================
# MAIN MENU
# ============================================================================
main() {
    if [ $# -eq 0 ]; then
        cat << EOF
Elasticsearch Operational Runbooks

Usage: $0 <command>

Commands:
  health-check      - Perform cluster health check
  scale-up          - Add a node to the cluster
  scale-down        - Remove a node from the cluster
  pod-recovery      - Recover a failed pod
  backup            - Create manual backup
  restore           - Restore from backup
  help              - Show this help message

Examples:
  $0 health-check
  $0 scale-up
  $0 pod-recovery es-0
  $0 restore snapshot_2025-11-27

EOF
        exit 0
    fi
    
    case "$1" in
        health-check)
            health_check
            ;;
        scale-up)
            scale_up
            ;;
        scale-down)
            scale_down
            ;;
        pod-recovery)
            pod_recovery "${2:-es-0}"
            ;;
        backup)
            manual_backup
            ;;
        restore)
            restore_backup "${2:-}"
            ;;
        help)
            $0
            ;;
        *)
            log_error "Unknown command: $1"
            $0
            exit 1
            ;;
    esac
}

main "$@"
