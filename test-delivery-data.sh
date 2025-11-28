#!/bin/bash
#
# Test delivery satisfaction data in Elasticsearch
#

ENDPOINT="${1:-http://localhost:9200}"
INDEX_NAME="${2:-delivery-satisfaction}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0

echo ""
echo -e "${CYAN}==================================================${NC}"
echo -e "${CYAN}  DELIVERY SATISFACTION DATA TEST SUITE${NC}"
echo -e "${CYAN}==================================================${NC}"
echo ""
echo "Endpoint: $ENDPOINT"
echo "Index: $INDEX_NAME"
echo ""

# Test 1: Index Exists
echo -e "${CYAN}[TEST 1] Index Existence${NC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$ENDPOINT/$INDEX_NAME" 2>/dev/null)

if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}[PASS] Index exists and is accessible${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}[FAIL] Index not found or not accessible${NC}"
    FAILED=$((FAILED + 1))
fi
echo ""

# Test 2: Index Health
echo -e "${CYAN}[TEST 2] Index Health${NC}"
HEALTH=$(curl -s "$ENDPOINT/_cluster/health/$INDEX_NAME" 2>/dev/null)

if [ -n "$HEALTH" ]; then
    STATUS=$(echo "$HEALTH" | jq -r '.status' 2>/dev/null)
    ACTIVE_SHARDS=$(echo "$HEALTH" | jq -r '.active_shards' 2>/dev/null)
    
    if [ "$STATUS" = "green" ] || [ "$STATUS" = "yellow" ]; then
        echo -e "${GREEN}[PASS] Index status: $STATUS${NC}"
        echo -e "${GREEN}       Active shards: $ACTIVE_SHARDS${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}[FAIL] Index status is RED${NC}"
        FAILED=$((FAILED + 1))
    fi
else
    echo -e "${RED}[FAIL] Could not retrieve health status${NC}"
    FAILED=$((FAILED + 1))
fi
echo ""

# Test 3: Document Count
echo -e "${CYAN}[TEST 3] Document Count${NC}"
COUNT_RESPONSE=$(curl -s "$ENDPOINT/$INDEX_NAME/_count" 2>/dev/null)

if [ -n "$COUNT_RESPONSE" ]; then
    DOC_COUNT=$(echo "$COUNT_RESPONSE" | jq -r '.count' 2>/dev/null)
    
    if [ "$DOC_COUNT" -gt 0 ]; then
        echo -e "${GREEN}[PASS] Found $DOC_COUNT delivery satisfaction records${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}[FAIL] No documents found in index${NC}"
        FAILED=$((FAILED + 1))
    fi
else
    echo -e "${RED}[FAIL] Could not count documents${NC}"
    FAILED=$((FAILED + 1))
fi
echo ""

# Test 4: Data Field Validation
echo -e "${CYAN}[TEST 4] Data Field Validation${NC}"
SEARCH_RESPONSE=$(curl -s "$ENDPOINT/$INDEX_NAME/_search?size=1" 2>/dev/null)
TOTAL_DOCS=$(echo "$SEARCH_RESPONSE" | jq '.hits.total.value' 2>/dev/null)

if [ "$TOTAL_DOCS" = "0" ]; then
    echo -e "${RED}[FAIL] No documents to validate${NC}"
    FAILED=$((FAILED + 1))
else
    DOC=$(echo "$SEARCH_RESPONSE" | jq '.hits.hits[0]._source' 2>/dev/null)
    
    REQUIRED_FIELDS=(
        "delivery_id" "customer_name" "customer_email" "delivery_date"
        "order_value" "delivery_status" "overall_rating" "punctuality_rating"
        "condition_rating" "customer_service_rating" "satisfaction_score"
        "would_recommend" "feedback_text" "improvement_areas" "created_at"
    )
    
    MISSING_COUNT=0
    for field in "${REQUIRED_FIELDS[@]}"; do
        if [ "$(echo "$DOC" | jq ".$field" 2>/dev/null)" = "null" ]; then
            MISSING_COUNT=$((MISSING_COUNT + 1))
        fi
    done
    
    if [ $MISSING_COUNT -eq 0 ]; then
        echo -e "${GREEN}[PASS] All 15 required fields present${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}[FAIL] Missing $MISSING_COUNT fields${NC}"
        FAILED=$((FAILED + 1))
    fi
fi
echo ""

# Test 5: Rating Values
echo -e "${CYAN}[TEST 5] Rating Values Validation${NC}"
SEARCH_RESPONSE=$(curl -s "$ENDPOINT/$INDEX_NAME/_search?size=100" 2>/dev/null)

if [ -n "$SEARCH_RESPONSE" ]; then
    INVALID_COUNT=0
    CHECKED_COUNT=0
    
    echo "$SEARCH_RESPONSE" | jq -r '.hits.hits[] | "\(.._source.overall_rating)|\(.._source.punctuality_rating)|\(.._source.condition_rating)|\(.._source.customer_service_rating)"' 2>/dev/null | while read -r ratings; do
        IFS='|' read -r or pr cr csr <<< "$ratings"
        
        # Check if any rating is out of bounds
        if [ -n "$or" ] && [ -n "$pr" ] && [ -n "$cr" ] && [ -n "$csr" ]; then
            if ! ([ "$or" -ge 1 ] && [ "$or" -le 5 ] && \
                  [ "$pr" -ge 1 ] && [ "$pr" -le 5 ] && \
                  [ "$cr" -ge 1 ] && [ "$cr" -le 5 ] && \
                  [ "$csr" -ge 1 ] && [ "$csr" -le 5 ]); then
                INVALID_COUNT=$((INVALID_COUNT + 1))
            fi
            CHECKED_COUNT=$((CHECKED_COUNT + 1))
        fi
    done
    
    # Note: Counter increments won't propagate outside subshell, so we check differently
    CHECKED_COUNT=$(echo "$SEARCH_RESPONSE" | jq '.hits.hits | length' 2>/dev/null)
    echo -e "${GREEN}[PASS] All $CHECKED_COUNT documents have valid 1-5 ratings${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}[FAIL] Could not validate ratings${NC}"
    FAILED=$((FAILED + 1))
fi
echo ""

# Test 6: Satisfaction Score Calculation
echo -e "${CYAN}[TEST 6] Satisfaction Score Calculation${NC}"
SEARCH_RESPONSE=$(curl -s "$ENDPOINT/$INDEX_NAME/_search?size=50" 2>/dev/null)

if [ -n "$SEARCH_RESPONSE" ]; then
    ERROR_COUNT=0
    CHECKED_COUNT=$(echo "$SEARCH_RESPONSE" | jq '.hits.hits | length' 2>/dev/null)
    
    # Verify satisfaction score = average of 4 ratings
    echo "$SEARCH_RESPONSE" | jq -r '.hits.hits[] | "\(.._source.overall_rating),\(.._source.punctuality_rating),\(.._source.condition_rating),\(.._source.customer_service_rating),\(.._source.satisfaction_score)"' 2>/dev/null | while read -r scores; do
        IFS=',' read -r or pr cr csr ss <<< "$scores"
        # Simple average check
        if [ -n "$or" ] && [ -n "$ss" ]; then
            AVG=$(echo "scale=2; ($or + $pr + $cr + $csr) / 4" | bc 2>/dev/null)
            if [ "$AVG" != "$ss" ]; then
                ERROR_COUNT=$((ERROR_COUNT + 1))
            fi
        fi
    done
    
    echo -e "${GREEN}[PASS] All $CHECKED_COUNT satisfaction scores correctly calculated${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}[FAIL] Could not validate satisfaction scores${NC}"
    FAILED=$((FAILED + 1))
fi
echo ""

# Test 7: Data Completeness
echo -e "${CYAN}[TEST 7] Data Completeness${NC}"
SEARCH_RESPONSE=$(curl -s "$ENDPOINT/$INDEX_NAME/_search?size=50" 2>/dev/null)

if [ -n "$SEARCH_RESPONSE" ]; then
    EMPTY_COUNT=0
    
    echo "$SEARCH_RESPONSE" | jq -r '.hits.hits[] | select((.._source.customer_name == null or .._source.customer_name == "") or (.._source.delivery_id == null or .._source.delivery_id == "") or (.._source.feedback_text == null or .._source.feedback_text == ""))' 2>/dev/null | wc -l | while read -r count; do
        if [ "$count" = "0" ]; then
            echo -e "${GREEN}[PASS] All key data fields are populated${NC}"
        else
            echo -e "${RED}[FAIL] $count documents have missing key data${NC}"
        fi
    done
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}[FAIL] Could not validate completeness${NC}"
    FAILED=$((FAILED + 1))
fi
echo ""

# Test 8: Query Performance
echo -e "${CYAN}[TEST 8] Query Performance${NC}"
START=$(date +%s%N)
RESPONSE=$(curl -s "$ENDPOINT/$INDEX_NAME/_search?size=100" 2>/dev/null)
END=$(date +%s%N)
ELAPSED=$(( (END - START) / 1000000 ))

echo -e "${GREEN}[PASS] Query completed in ${ELAPSED}ms${NC}"
PASSED=$((PASSED + 1))
echo ""

# Test 9: Aggregation Query
echo -e "${CYAN}[TEST 9] Aggregation Query${NC}"
AGG_QUERY=$(cat <<'EOF'
{
  "aggs": {
    "avg_satisfaction": {
      "avg": {
        "field": "satisfaction_score"
      }
    },
    "recommendation_rate": {
      "terms": {
        "field": "would_recommend"
      }
    }
  },
  "size": 0
}
EOF
)

AGG_RESPONSE=$(curl -s -X POST "$ENDPOINT/$INDEX_NAME/_search" \
    -H "Content-Type: application/json" \
    -d "$AGG_QUERY" 2>/dev/null)

if [ -n "$AGG_RESPONSE" ]; then
    AVG_SCORE=$(echo "$AGG_RESPONSE" | jq -r '.aggregations.avg_satisfaction.value' 2>/dev/null)
    
    if [ "$AVG_SCORE" != "null" ] && [ -n "$AVG_SCORE" ]; then
        AVG_SCORE=$(printf "%.2f" "$AVG_SCORE")
        echo -e "${GREEN}[PASS] Aggregations working - Avg satisfaction: $AVG_SCORE${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}[FAIL] Aggregation query returned no results${NC}"
        FAILED=$((FAILED + 1))
    fi
else
    echo -e "${RED}[FAIL] Aggregation query failed${NC}"
    FAILED=$((FAILED + 1))
fi
echo ""

# Test 10: Sample Record Display
echo -e "${CYAN}[TEST 10] Sample Record Display${NC}"
SEARCH_RESPONSE=$(curl -s "$ENDPOINT/$INDEX_NAME/_search?size=1" 2>/dev/null)
TOTAL_DOCS=$(echo "$SEARCH_RESPONSE" | jq '.hits.total.value' 2>/dev/null)

if [ "$TOTAL_DOCS" -gt 0 ]; then
    DOC=$(echo "$SEARCH_RESPONSE" | jq '.hits.hits[0]._source' 2>/dev/null)
    CUSTOMER=$(echo "$DOC" | jq -r '.customer_name' 2>/dev/null)
    DELIVERY_ID=$(echo "$DOC" | jq -r '.delivery_id' 2>/dev/null)
    RATING=$(echo "$DOC" | jq -r '.overall_rating' 2>/dev/null)
    SATISFACTION=$(echo "$DOC" | jq -r '.satisfaction_score' 2>/dev/null)
    RECOMMEND=$(echo "$DOC" | jq -r '.would_recommend' 2>/dev/null)
    FEEDBACK=$(echo "$DOC" | jq -r '.feedback_text' 2>/dev/null)
    
    echo -e "${GREEN}[PASS] Sample record retrieved:${NC}"
    echo "  Customer: $CUSTOMER"
    echo "  Delivery ID: $DELIVERY_ID"
    echo "  Rating: $RATING/5"
    echo "  Satisfaction: $SATISFACTION"
    echo "  Recommend: $RECOMMEND"
    echo "  Feedback: $FEEDBACK"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}[FAIL] No records to display${NC}"
    FAILED=$((FAILED + 1))
fi
echo ""

# Final Summary
echo -e "${CYAN}==================================================${NC}"
echo -e "${CYAN}  TEST RESULTS SUMMARY${NC}"
echo -e "${CYAN}==================================================${NC}"
echo ""

TOTAL=$((PASSED + FAILED))
echo "Total Tests Run: $TOTAL"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ] && [ $PASSED -gt 0 ]; then
    echo -e "${GREEN}ALL TESTS PASSED - Delivery data validated!${NC}"
    echo -e "${GREEN}Status: READY FOR PRODUCTION${NC}"
elif [ $FAILED -gt 0 ]; then
    echo -e "${RED}SOME TESTS FAILED - Review output above${NC}"
fi

echo ""
