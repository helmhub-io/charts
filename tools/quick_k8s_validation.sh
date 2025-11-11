#!/bin/bash
set -euo pipefail

#########################################################################
# Quick Kubernetes Validation Test
# Tests that critical charts can be installed with helm install --dry-run
#########################################################################

REPO_NAME="helmhub"
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Critical charts to test
CHARTS=(
    "nginx"
    "apache"
    "redis"
    "postgresql"
    "mysql"
    "mariadb"
    "mongodb"
    "grafana"
    "prometheus"
    "jenkins"
    "rabbitmq"
    "kafka"
    "nginx-ingress-controller"
    "cert-manager"
    "vault"
)

echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Quick Kubernetes Validation Test (Dry Run)       ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo ""

for chart in "${CHARTS[@]}"; do
    TEST_COUNT=$((TEST_COUNT + 1))
    echo -ne "${YELLOW}Testing $chart...${NC} "
    
    if helm install test-$chart $REPO_NAME/$chart \
        --dry-run \
        --namespace test \
        --create-namespace \
        --set persistence.enabled=false \
        --set service.type=ClusterIP \
        --set ingress.enabled=false \
        > /tmp/dry-run-$chart.yaml 2>/tmp/dry-run-$chart.err; then
        
        # Count resources
        RESOURCES=$(grep -c "^# Source:" /tmp/dry-run-$chart.yaml || echo "0")
        echo -e "${GREEN}✓${NC} ($RESOURCES manifests)"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}✗ FAILED${NC}"
        echo "  Error: $(head -1 /tmp/dry-run-$chart.err)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                    SUMMARY                        ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo ""
echo "Total charts tested: $TEST_COUNT"
echo -e "${GREEN}Passed: $PASS_COUNT${NC}"
echo -e "${RED}Failed: $FAIL_COUNT${NC}"
echo ""

SUCCESS_RATE=$(awk "BEGIN {printf \"%.1f\", ($PASS_COUNT/$TEST_COUNT)*100}")
echo "Success Rate: $SUCCESS_RATE%"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}✅ ALL TESTS PASSED!${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠️  Some tests failed${NC}"
    exit 1
fi
