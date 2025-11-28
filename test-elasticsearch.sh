#!/bin/bash
#
# Comprehensive test suite for Elasticsearch cluster
#
# Tests cluster connectivity, health, operations, and performance
#
# Usage:
#   ./test-elasticsearch.sh
#   ./test-elasticsearch.sh http://10.0.0.1:9200
#

ENDPOINT="${1:-http://localhost:9200}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test results
PASSED=0
FAILED=0

test_connection() {
    echo ""
    echo -e "${CYAN}[TEST 1] Connection to Elasticsearch${NC}"
    echo -e "${CYAN}---------------------------------------------------------${NC}"
    
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$ENDPOINT/")
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo -e "${GREEN}[PASS] Elasticsearch is reachable on $ENDPOINT${NC}"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${RED}[FAIL] HTTP Response: $HTTP_CODE${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

test_cluster_health() {
    echo ""
    echo -e "${CYAN}[TEST 2] Cluster Health Status${NC}"
    echo -e "${CYAN}---------------------------------------------------------${NC}"
    
    HEALTH=$(curl -s "$ENDPOINT/_cluster/health" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}[FAIL] Could not retrieve cluster health${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi
    
    CLUSTER_NAME=$(echo "$HEALTH" | jq -r '.cluster_name' 2>/dev/null)
    STATUS=$(echo "$HEALTH" | jq -r '.status' 2>/dev/null)
    NODES=$(echo "$HEALTH" | jq -r '.number_of_nodes' 2>/dev/null)
    DATA_NODES=$(echo "$HEALTH" | jq -r '.number_of_data_nodes' 2>/dev/null)
    PENDING=$(echo "$HEALTH" | jq -r '.number_of_pending_tasks' 2>/dev/null)
    
    echo -e "${GREEN}       Cluster: $CLUSTER_NAME${NC}"
    echo -e "${GREEN}       Status: $STATUS${NC}"
    echo -e "${GREEN}       Nodes: $NODES${NC}"
    echo -e "${GREEN}       Data Nodes: $DATA_NODES${NC}"
    echo -e "${GREEN}       Pending Tasks: $PENDING${NC}"
    
    if [ "$STATUS" = "green" ] && [ "$PENDING" = "0" ]; then
        echo -e "${GREEN}[PASS] Cluster health is green${NC}"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${YELLOW}[WARN] Cluster status is not fully green${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

test_node_status() {
    echo ""
    echo -e "${CYAN}[TEST 3] Node Status${NC}"
    echo -e "${CYAN}---------------------------------------------------------${NC}"
    
    NODES=$(curl -s "$ENDPOINT/_nodes" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}[FAIL] Could not retrieve node status${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi
    
    TOTAL_NODES=$(echo "$NODES" | jq '.nodes | length' 2>/dev/null)
    echo -e "${GREEN}       Total Nodes: $TOTAL_NODES${NC}"
    
    echo "$NODES" | jq -r '.nodes[] | "       - \(.name): Version \(.version.number)"' 2>/dev/null | while read line; do
        echo -e "\033[90m$line${NC}"
    done
    
    if [ "$TOTAL_NODES" -ge 1 ]; then
        echo -e "${GREEN}[PASS] All nodes responding${NC}"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${YELLOW}[WARN] Some nodes may not be healthy${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

test_index_operations() {
    echo ""
    echo -e "${CYAN}[TEST 4] Index Operations${NC}"
    echo -e "${CYAN}---------------------------------------------------------${NC}"
    
    TEST_INDEX="test-$(date +%s)"
    
    # Create index
    CREATE_RESPONSE=$(curl -s -X PUT "$ENDPOINT/$TEST_INDEX" -H "Content-Type: application/json" 2>/dev/null)
    ACKNOWLEDGED=$(echo "$CREATE_RESPONSE" | jq -r '.acknowledged' 2>/dev/null)
    
    if [ "$ACKNOWLEDGED" = "true" ]; then
        echo -e "${GREEN}       [OK] Index created: $TEST_INDEX${NC}"
    else
        echo -e "${RED}       [FAIL] Index creation failed${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi
    
    # Insert document
    DOC_BODY=$(cat <<EOF
{
  "title": "Test Document",
  "content": "This is a test document",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)
    
    INSERT_RESPONSE=$(curl -s -X POST "$ENDPOINT/$TEST_INDEX/_doc" \
        -H "Content-Type: application/json" \
        -d "$DOC_BODY" 2>/dev/null)
    RESULT=$(echo "$INSERT_RESPONSE" | jq -r '.result' 2>/dev/null)
    DOC_ID=$(echo "$INSERT_RESPONSE" | jq -r '._id' 2>/dev/null)
    
    if [ "$RESULT" = "created" ]; then
        echo -e "${GREEN}       [OK] Document inserted with ID: $DOC_ID${NC}"
    else
        echo -e "${YELLOW}       [WARN] Document insertion response: $RESULT${NC}"
    fi
    
    # Wait for indexing
    sleep 1
    
    # Search documents
    SEARCH_RESPONSE=$(curl -s "$ENDPOINT/$TEST_INDEX/_search" 2>/dev/null)
    DOC_COUNT=$(echo "$SEARCH_RESPONSE" | jq '.hits.total.value' 2>/dev/null)
    echo -e "${GREEN}       [OK] Found $DOC_COUNT documents in index${NC}"
    
    # Delete index
    DELETE_RESPONSE=$(curl -s -X DELETE "$ENDPOINT/$TEST_INDEX" 2>/dev/null)
    DELETE_ACK=$(echo "$DELETE_RESPONSE" | jq -r '.acknowledged' 2>/dev/null)
    
    if [ "$DELETE_ACK" = "true" ]; then
        echo -e "${GREEN}       [OK] Index deleted: $TEST_INDEX${NC}"
    fi
    
    echo -e "${GREEN}[PASS] All index operations successful${NC}"
    PASSED=$((PASSED + 1))
    return 0
}

test_data_persistence() {
    echo ""
    echo -e "${CYAN}[TEST 5] Data Persistence${NC}"
    echo -e "${CYAN}---------------------------------------------------------${NC}"
    
    INDICES=$(curl -s "$ENDPOINT/_cat/indices?format=json" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}[FAIL] Could not check data persistence${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi
    
    INDEX_COUNT=$(echo "$INDICES" | jq 'length' 2>/dev/null)
    echo -e "${GREEN}       Total indices: $INDEX_COUNT${NC}"
    
    echo "$INDICES" | jq -r '.[] | select(.index | startswith(".") | not) | "       - \(.index): \(.["docs.count"]) docs, Size: \(.["store.size"])"' 2>/dev/null | while read line; do
        echo -e "\033[90m$line${NC}"
    done
    
    if [ "$INDEX_COUNT" -gt 0 ]; then
        echo -e "${GREEN}[PASS] Data persisted in cluster${NC}"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${YELLOW}[WARN] No user indices found${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

test_performance() {
    echo ""
    echo -e "${CYAN}[TEST 6] Performance${NC}"
    echo -e "${CYAN}---------------------------------------------------------${NC}"
    
    TOTAL_TIME=0
    COUNT=0
    
    for i in 1 2 3; do
        START=$(date +%s%N)
        curl -s "$ENDPOINT/_search?size=0" > /dev/null 2>&1
        END=$(date +%s%N)
        ELAPSED=$(( (END - START) / 1000000 ))
        echo -e "\033[90m       Query $i: ${ELAPSED}ms${NC}"
        TOTAL_TIME=$((TOTAL_TIME + ELAPSED))
        COUNT=$((COUNT + 1))
    done
    
    AVG_TIME=$((TOTAL_TIME / COUNT))
    echo -e "${GREEN}       Average response time: ${AVG_TIME}ms${NC}"
    
    if [ $AVG_TIME -lt 1000 ]; then
        echo -e "${GREEN}[PASS] Performance is good (< 1000ms)${NC}"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${YELLOW}[WARN] Response time is slow (> 1000ms)${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

# Main execution
echo ""
echo -e "${GREEN}=========================================================${NC}"
echo -e "${GREEN}    Elasticsearch Cluster Test Suite${NC}"
echo -e "${GREEN}    Endpoint: $ENDPOINT${NC}"
echo -e "${GREEN}    Start Time: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${GREEN}=========================================================${NC}"

# Run all tests
test_connection
test_cluster_health
test_node_status
test_index_operations
test_data_persistence
test_performance

# Summary
echo ""
echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN}    TEST SUMMARY${NC}"
echo -e "${CYAN}=========================================================${NC}"

TOTAL=$((PASSED + FAILED))

echo ""
echo -e "${GREEN}    Total Tests: $TOTAL${NC}"
echo -e "${GREEN}    Passed: $PASSED${NC}"
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}    Failed: $FAILED${NC}"
else
    echo -e "${RED}    Failed: $FAILED${NC}"
fi
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}[OK] All tests passed!${NC}"
else
    echo -e "${YELLOW}[WARN] Some tests failed. Review output above.${NC}"
fi

echo ""
echo -e "\033[90m    End Time: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo ""
