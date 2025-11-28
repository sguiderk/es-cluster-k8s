#!/bin/bash

################################################################################
# Elasticsearch Cluster Deployment Script
# One-command deployment of 3-node Elasticsearch cluster to AWS EKS
# With built-in delivery satisfaction data insertion
#
# Usage:
#   ./deploy-elasticsearch.sh [deploy|verify|cleanup|insert]
#
# Prerequisites:
#   - kubectl configured and connected to EKS cluster
#   - Helm installed and configured
#   - curl installed for data insertion
#   - jq installed for JSON parsing (optional)
################################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="elasticsearch"
RELEASE_NAME="elasticsearch"
CHART_PATH="./helm/elasticsearch"
ENDPOINT="http://localhost:9200"
INDEX_NAME="delivery-satisfaction"
DOCUMENT_COUNT=50
PORT_FORWARD_PID=""

################################################################################
# Utility Functions
################################################################################

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_section() {
    echo ""
    echo -e "${CYAN}=========================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}=========================================================${NC}"
    echo ""
}

# Cleanup function
cleanup() {
    if [ -n "$PORT_FORWARD_PID" ] && kill -0 "$PORT_FORWARD_PID" 2>/dev/null; then
        log_info "Stopping port-forward (PID: $PORT_FORWARD_PID)..."
        kill "$PORT_FORWARD_PID" 2>/dev/null || true
    fi
}

trap cleanup EXIT

################################################################################
# Prerequisites Verification
################################################################################

verify_prerequisites() {
    log_info "Verifying prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
    fi
    log_success "kubectl is installed"
    
    # Check helm
    if ! command -v helm &> /dev/null; then
        log_error "Helm not found. Please install Helm."
    fi
    log_success "Helm is installed"
    
    # Check cluster connection
    if ! kubectl config current-context &> /dev/null; then
        log_error "Not connected to Kubernetes cluster"
    fi
    local context=$(kubectl config current-context)
    log_success "Connected to cluster: $context"
    
    # Check Helm chart
    if [ ! -d "$CHART_PATH" ]; then
        log_error "Helm chart not found at: $CHART_PATH"
    fi
    log_success "Helm chart found: $CHART_PATH"
    
    # Check curl (for data insertion)
    if ! command -v curl &> /dev/null; then
        log_warn "curl not found. Data insertion will not work."
    else
        log_success "curl is installed"
    fi
}

################################################################################
# Deployment Functions
################################################################################

deploy_cluster() {
    log_section "Deploying Elasticsearch Cluster via Helm"
    
    log_info "Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE" 2>/dev/null || log_info "Namespace already exists"
    
    log_info "Installing Helm release: $RELEASE_NAME"
    helm upgrade --install "$RELEASE_NAME" "$CHART_PATH" \
        --namespace "$NAMESPACE" \
        --create-namespace \
        --wait \
        --timeout 10m
    
    if [ $? -eq 0 ]; then
        log_success "Helm release deployed successfully"
    else
        log_error "Failed to deploy Helm release"
    fi
    
    log_info "Waiting for pods to be ready (this may take 2-3 minutes)..."
    kubectl rollout status statefulset/es \
        -n "$NAMESPACE" \
        --timeout=5m || true
    
    log_success "Deployment initiated"
}

################################################################################
# Verification Functions
################################################################################

verify_deployment() {
    log_section "Verifying Elasticsearch Cluster Deployment"
    
    # Check pod status
    log_info "Pod Status:"
    kubectl get pods -n "$NAMESPACE"
    echo ""
    
    # Check pod details with node assignments
    log_info "Pod Details (Node Assignments):"
    kubectl get pods -n "$NAMESPACE" -o wide
    echo ""
    
    # Check services
    log_info "Services:"
    kubectl get svc -n "$NAMESPACE"
    echo ""
    
    # Try to check cluster health
    log_info "Checking Cluster Health..."
    
    # Set up port-forward in background
    log_info "Setting up port-forward to Elasticsearch..."
    kubectl port-forward -n "$NAMESPACE" svc/elasticsearch 9200:9200 &> /dev/null &
    PORT_FORWARD_PID=$!
    sleep 2
    
    # Check health
    if command -v curl &> /dev/null; then
        local health_response
        health_response=$(curl -s "$ENDPOINT/_cluster/health" 2>/dev/null || echo "")
        
        if [ -n "$health_response" ]; then
            log_success "Connected to Elasticsearch"
            
            # Extract values
            if command -v jq &> /dev/null; then
                local status=$(echo "$health_response" | jq -r '.status')
                local nodes=$(echo "$health_response" | jq -r '.number_of_nodes')
                
                log_info "Cluster Name: $(echo "$health_response" | jq -r '.cluster_name')"
                log_info "Cluster Status: $status"
                
                if [ "$status" = "green" ]; then
                    log_success "Cluster Status is GREEN"
                else
                    log_warn "Cluster Status is $status"
                fi
                
                log_info "Number of Nodes: $nodes"
                
                if [ "$nodes" = "3" ]; then
                    log_success "All 3 nodes connected"
                else
                    log_warn "Expected 3 nodes, found $nodes"
                fi
            else
                log_info "Cluster health response received (jq not available for parsing)"
            fi
        else
            log_warn "Could not retrieve cluster health - pods may still be starting"
        fi
    else
        log_warn "curl not available - skipping health check"
    fi
    
    # Kill port-forward
    if [ -n "$PORT_FORWARD_PID" ] && kill -0 "$PORT_FORWARD_PID" 2>/dev/null; then
        kill "$PORT_FORWARD_PID" 2>/dev/null
        PORT_FORWARD_PID=""
    fi
    
    echo ""
    log_success "Verification complete"
}

################################################################################
# Data Insertion Functions
################################################################################

insert_sample_data() {
    log_section "Delivery Satisfaction Data Insertion"
    log_info "Index: $INDEX_NAME | Documents: $DOCUMENT_COUNT"
    
    # Check curl
    if ! command -v curl &> /dev/null; then
        log_error "curl is required for data insertion"
    fi
    
    # Set up port-forward
    log_info "Setting up port-forward to Elasticsearch..."
    kubectl port-forward -n "$NAMESPACE" svc/elasticsearch 9200:9200 &> /dev/null &
    PORT_FORWARD_PID=$!
    sleep 2
    
    # Wait for Elasticsearch to be ready
    log_info "Waiting for Elasticsearch to be ready..."
    local retries=0
    local max_retries=30
    while [ $retries -lt $max_retries ]; do
        if curl -s "$ENDPOINT" &> /dev/null; then
            log_success "Elasticsearch is ready"
            break
        fi
        retries=$((retries + 1))
        echo -n "."
        sleep 1
    done
    
    if [ $retries -eq $max_retries ]; then
        log_warn "Elasticsearch may not be fully ready, continuing anyway..."
    fi
    echo ""
    
    # Step 1: Create index
    log_info "[STEP 1] Creating index: $INDEX_NAME"
    echo "-------------------------------------------------------"
    
    local mappings='{
        "mappings": {
            "properties": {
                "delivery_id": {"type": "keyword"},
                "customer_name": {"type": "text"},
                "customer_email": {"type": "keyword"},
                "delivery_date": {"type": "date"},
                "order_value": {"type": "float"},
                "delivery_status": {"type": "keyword"},
                "overall_rating": {"type": "integer"},
                "punctuality_rating": {"type": "integer"},
                "condition_rating": {"type": "integer"},
                "customer_service_rating": {"type": "integer"},
                "satisfaction_score": {"type": "float"},
                "would_recommend": {"type": "boolean"},
                "feedback_text": {"type": "text"},
                "improvement_areas": {"type": "text"},
                "created_at": {"type": "date"}
            }
        }
    }'
    
    log_info "Creating delivery satisfaction index..."
    
    if curl -s -X PUT "$ENDPOINT/$INDEX_NAME" \
        -H "Content-Type: application/json" \
        -d "$mappings" &> /dev/null; then
        log_success "Index created (or already exists)"
    else
        log_warn "Index creation returned an error (may already exist)"
    fi
    
    echo ""
    
    # Step 2: Insert data
    log_info "[STEP 2] Inserting $DOCUMENT_COUNT delivery satisfaction records"
    echo "-------------------------------------------------------"
    
    local firstNames=("John" "Sarah" "Michael" "Emma" "David" "Lisa" "James" "Anna" "Robert" "Maria")
    local lastNames=("Smith" "Johnson" "Williams" "Brown" "Jones" "Garcia" "Miller" "Davis" "Rodriguez" "Martinez")
    local statuses=("Delivered" "Signed" "Attempted" "Completed")
    local feedback=("Fast and professional" "Great communication" "Perfect condition" "Courteous driver" "On-time delivery" "Excellent packaging" "Very satisfied" "Exceeded expectations" "Professional service" "Highly recommend")
    local improvements=("Delivery time" "Communication" "Packaging" "Driver courtesy" "None")
    
    local insertCount=0
    
    for ((i = 1; i <= DOCUMENT_COUNT; i++)); do
        local firstName=${firstNames[$((RANDOM % ${#firstNames[@]}))]}
        local lastName=${lastNames[$((RANDOM % ${#lastNames[@]}))]}
        local customerName="$firstName $lastName"
        local customerEmail="${firstName,,}.${lastName,,}@example.com"
        local deliveryId="DEL-$(date +%Y%m%d)-$((1000 + i))"
        local orderValue=$(awk "BEGIN {print int(rand() * 4701) + 2999}")
        orderValue=$(awk "BEGIN {printf \"%.2f\", $orderValue / 100}")
        local deliveryStatus=${statuses[$((RANDOM % ${#statuses[@]}))]}
        
        local overallRating=$((RANDOM % 3 + 3))
        local punctualityRating=$((RANDOM % 3 + 3))
        local conditionRating=$((RANDOM % 3 + 3))
        local serviceRating=$((RANDOM % 3 + 3))
        
        local satisfactionScore=$(awk "BEGIN {printf \"%.2f\", ($overallRating + $punctualityRating + $conditionRating + $serviceRating) / 4}")
        local wouldRecommend=$((RANDOM % 100 > 30 ? "true" : "false"))
        
        local feedbackText=${feedback[$((RANDOM % ${#feedback[@]}))]}
        local improvementArea=${improvements[$((RANDOM % ${#improvements[@]}))]}
        
        local deliveryDate=$(date -u -d "$((RANDOM % 30 + 1)) days ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -v -$((RANDOM % 30 + 1))d +"%Y-%m-%dT%H:%M:%SZ")
        local createdAt=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        
        local doc="{
            \"delivery_id\": \"$deliveryId\",
            \"customer_name\": \"$customerName\",
            \"customer_email\": \"$customerEmail\",
            \"delivery_date\": \"$deliveryDate\",
            \"order_value\": $orderValue,
            \"delivery_status\": \"$deliveryStatus\",
            \"overall_rating\": $overallRating,
            \"punctuality_rating\": $punctualityRating,
            \"condition_rating\": $conditionRating,
            \"customer_service_rating\": $serviceRating,
            \"satisfaction_score\": $satisfactionScore,
            \"would_recommend\": $wouldRecommend,
            \"feedback_text\": \"$feedbackText\",
            \"improvement_areas\": \"$improvementArea\",
            \"created_at\": \"$createdAt\"
        }"
        
        if curl -s -X POST "$ENDPOINT/$INDEX_NAME/_doc" \
            -H "Content-Type: application/json" \
            -d "$doc" &> /dev/null; then
            insertCount=$((insertCount + 1))
        fi
        
        if [ $((i % 10)) -eq 0 ]; then
            log_info "       Progress: $i/$DOCUMENT_COUNT records inserted"
        fi
    done
    
    log_success "       Progress: $insertCount/$DOCUMENT_COUNT records inserted"
    echo ""
    
    # Step 3: Verify
    log_info "[STEP 3] Verifying data insertion"
    echo "-------------------------------------------------------"
    
    sleep 2
    
    local verify_response
    verify_response=$(curl -s "$ENDPOINT/$INDEX_NAME/_search?size=0" 2>/dev/null || echo "")
    
    if [ -n "$verify_response" ]; then
        if command -v jq &> /dev/null; then
            local total=$(echo "$verify_response" | jq '.hits.total.value')
            log_success "[OK] Successfully inserted $total delivery satisfaction records"
        else
            log_success "[OK] Data insertion complete (verification requires jq)"
        fi
    else
        log_warn "[WARN] Could not verify insertion"
    fi
    
    echo ""
    
    # Step 4: Show sample
    log_info "[STEP 4] Sample Record"
    echo "-------------------------------------------------------"
    
    local sample_response
    sample_response=$(curl -s "$ENDPOINT/$INDEX_NAME/_search?size=1" 2>/dev/null || echo "")
    
    if [ -n "$sample_response" ] && command -v jq &> /dev/null; then
        local sample=$(echo "$sample_response" | jq '.hits.hits[0]._source')
        if [ "$sample" != "null" ]; then
            log_success "Delivery ID: $(echo "$sample" | jq -r '.delivery_id')"
            log_success "Customer: $(echo "$sample" | jq -r '.customer_name')"
            log_success "Rating: $(echo "$sample" | jq -r '.overall_rating')/5 | Satisfaction: $(echo "$sample" | jq -r '.satisfaction_score')"
            log_success "Recommend: $(echo "$sample" | jq -r '.would_recommend') | Feedback: $(echo "$sample" | jq -r '.feedback_text')"
        fi
    else
        log_info "[INFO] Sample display requires jq - skipping"
    fi
    
    echo ""
    
    # Kill port-forward
    if [ -n "$PORT_FORWARD_PID" ] && kill -0 "$PORT_FORWARD_PID" 2>/dev/null; then
        kill "$PORT_FORWARD_PID" 2>/dev/null
        PORT_FORWARD_PID=""
    fi
}

################################################################################
# Cleanup Functions
################################################################################

cleanup_cluster() {
    log_section "Cluster Cleanup"
    
    log_warn "This will delete the entire Elasticsearch cluster and namespace"
    read -p "Continue? (yes/no): " -r confirm
    
    if [ "$confirm" != "yes" ]; then
        log_info "Cleanup cancelled"
        return
    fi
    
    log_info "Uninstalling Helm release: $RELEASE_NAME"
    helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" || true
    
    log_info "Deleting namespace: $NAMESPACE"
    kubectl delete namespace "$NAMESPACE" || true
    
    log_success "Cleanup complete"
}

################################################################################
# Help and Usage
################################################################################

show_usage() {
    cat << EOF
${CYAN}Elasticsearch Cluster Deployment Script${NC}

${BLUE}Usage:${NC}
    $0 [deploy|verify|cleanup|insert|help]

${BLUE}Actions:${NC}
    deploy     Deploy Elasticsearch cluster via Helm (default)
    verify     Verify cluster deployment status
    cleanup    Delete Elasticsearch cluster
    insert     Insert delivery satisfaction sample data
    help       Show this help message

${BLUE}Examples:${NC}
    $0 deploy              # Deploy cluster
    $0 insert              # Insert 50 sample records
    $0 deploy && $0 insert # Deploy and insert data
    $0 verify              # Check status
    $0 cleanup             # Delete cluster

${BLUE}Prerequisites:${NC}
    - kubectl configured and connected to EKS cluster
    - Helm installed and configured
    - curl installed (for data insertion)
    - jq installed (optional, for better JSON parsing)

EOF
}

################################################################################
# Main Execution
################################################################################

main() {
    local action="${1:-deploy}"
    
    case "$action" in
        deploy)
            verify_prerequisites
            deploy_cluster
            log_info "Waiting before verification..."
            sleep 5
            verify_deployment
            ;;
        verify)
            verify_prerequisites
            verify_deployment
            ;;
        cleanup)
            cleanup_cluster
            ;;
        insert)
            insert_sample_data
            ;;
        help)
            show_usage
            ;;
        *)
            log_error "Unknown action: $action"
            show_usage
            exit 1
            ;;
    esac
    
    echo ""
    log_success "Done!"
    echo ""
}

main "$@"
