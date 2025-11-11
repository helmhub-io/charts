#!/bin/bash
set -euo pipefail

#########################################################################
# Comprehensive Helm Charts Testing Script
# Tests all 101 charts from GitHub Pages repository
#########################################################################

REPO_NAME="helmhub"
REPO_URL="https://helmhub-io.github.io/charts/"
TEST_DIR="/tmp/helm-chart-tests"
RESULTS_FILE="$TEST_DIR/test_results.log"
SUMMARY_FILE="$TEST_DIR/test_summary.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL_CHARTS=0
TEMPLATE_SUCCESS=0
TEMPLATE_FAILED=0
DOWNLOAD_SUCCESS=0
DOWNLOAD_FAILED=0

mkdir -p "$TEST_DIR"
echo "Helm Charts Comprehensive Test - $(date)" > "$RESULTS_FILE"
echo "============================================" >> "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"

#########################################################################
# Step 1: Add/Update Helm Repository
#########################################################################
echo -e "${BLUE}Step 1: Adding Helm repository${NC}"
if helm repo list | grep -q "^${REPO_NAME}"; then
    echo "Repository already exists, updating..."
    helm repo update "$REPO_NAME"
else
    echo "Adding repository..."
    helm repo add "$REPO_NAME" "$REPO_URL"
fi

echo -e "${GREEN}✓ Repository ready${NC}"
echo "" >> "$RESULTS_FILE"

#########################################################################
# Step 2: Get list of all charts
#########################################################################
echo -e "${BLUE}Step 2: Fetching chart list${NC}"
CHART_LIST=$(helm search repo "$REPO_NAME/" -o json | jq -r '.[].name' | sort)
TOTAL_CHARTS=$(echo "$CHART_LIST" | wc -l)

echo "Found $TOTAL_CHARTS charts to test"
echo "Total charts: $TOTAL_CHARTS" >> "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"

#########################################################################
# Step 3: Test each chart
#########################################################################
echo -e "${BLUE}Step 3: Testing all charts${NC}"
echo "This will take several minutes..."
echo ""

for CHART_FULL in $CHART_LIST; do
    CHART_NAME=$(echo "$CHART_FULL" | cut -d'/' -f2)
    
    echo -e "${YELLOW}Testing: $CHART_NAME${NC}"
    
    # Create chart-specific test directory
    CHART_TEST_DIR="$TEST_DIR/$CHART_NAME"
    mkdir -p "$CHART_TEST_DIR"
    
    #####################################################################
    # Test 1: Download chart
    #####################################################################
    echo -n "  - Downloading... "
    if helm pull "$CHART_FULL" -d "$CHART_TEST_DIR" 2>"$CHART_TEST_DIR/download.err"; then
        echo -e "${GREEN}✓${NC}"
        echo "✓ $CHART_NAME: Download successful" >> "$RESULTS_FILE"
        DOWNLOAD_SUCCESS=$((DOWNLOAD_SUCCESS + 1))
    else
        echo -e "${RED}✗${NC}"
        echo "✗ $CHART_NAME: Download FAILED" >> "$RESULTS_FILE"
        cat "$CHART_TEST_DIR/download.err" >> "$RESULTS_FILE"
        DOWNLOAD_FAILED=$((DOWNLOAD_FAILED + 1))
        continue
    fi
    
    #####################################################################
    # Test 2: Render templates with helm template
    #####################################################################
    echo -n "  - Rendering templates... "
    
    # Special configurations for specific charts
    EXTRA_ARGS=""
    case "$CHART_NAME" in
        argo-cd)
            EXTRA_ARGS="--set redis.enabled=true --set externalRedis.host=''"
            ;;
        harbor)
            EXTRA_ARGS="--set postgresql.enabled=true --set externalDatabase.password='' --set harborAdminPassword=admin123"
            ;;
        keycloak)
            EXTRA_ARGS="--set postgresql.enabled=true --set auth.adminPassword=admin123"
            ;;
        mlflow)
            EXTRA_ARGS="--set postgresql.enabled=true --set auth.enabled=false"
            ;;
        superset)
            EXTRA_ARGS="--set postgresql.enabled=true"
            ;;
    esac
    
    # Try with minimal values
    if helm template test-release "$CHART_FULL" \
        --set persistence.enabled=false \
        --set service.type=ClusterIP \
        --set ingress.enabled=false \
        --set metrics.enabled=false \
        $EXTRA_ARGS \
        > "$CHART_TEST_DIR/rendered.yaml" 2>"$CHART_TEST_DIR/template.err"; then
        
        # Verify we got some output
        if [ -s "$CHART_TEST_DIR/rendered.yaml" ]; then
            RESOURCE_COUNT=$(grep -c "^kind:" "$CHART_TEST_DIR/rendered.yaml" || true)
            echo -e "${GREEN}✓${NC} ($RESOURCE_COUNT resources)"
            echo "✓ $CHART_NAME: Template rendering successful ($RESOURCE_COUNT resources)" >> "$RESULTS_FILE"
            TEMPLATE_SUCCESS=$((TEMPLATE_SUCCESS + 1))
        else
            echo -e "${YELLOW}⚠${NC} (no resources)"
            echo "⚠ $CHART_NAME: Template rendered but no resources generated" >> "$RESULTS_FILE"
            TEMPLATE_FAILED=$((TEMPLATE_FAILED + 1))
        fi
    else
        echo -e "${RED}✗${NC}"
        echo "✗ $CHART_NAME: Template rendering FAILED" >> "$RESULTS_FILE"
        cat "$CHART_TEST_DIR/template.err" >> "$RESULTS_FILE"
        TEMPLATE_FAILED=$((TEMPLATE_FAILED + 1))
    fi
    
    #####################################################################
    # Test 3: Validate YAML syntax
    #####################################################################
    echo -n "  - Validating YAML... "
    if [ -f "$CHART_TEST_DIR/rendered.yaml" ] && [ -s "$CHART_TEST_DIR/rendered.yaml" ]; then
        if python3 -c "import yaml; yaml.safe_load_all(open('$CHART_TEST_DIR/rendered.yaml'))" 2>"$CHART_TEST_DIR/yaml.err"; then
            echo -e "${GREEN}✓${NC}"
            echo "✓ $CHART_NAME: YAML validation successful" >> "$RESULTS_FILE"
        else
            echo -e "${RED}✗${NC}"
            echo "✗ $CHART_NAME: YAML validation FAILED" >> "$RESULTS_FILE"
            cat "$CHART_TEST_DIR/yaml.err" >> "$RESULTS_FILE"
        fi
    else
        echo -e "${YELLOW}⊘${NC} (skipped - no template)"
    fi
    
    echo "" >> "$RESULTS_FILE"
done

#########################################################################
# Step 4: Generate Summary
#########################################################################
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                 TEST SUMMARY                      ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"

cat > "$SUMMARY_FILE" << EOF
═══════════════════════════════════════════════════
         HELM CHARTS TEST SUMMARY
═══════════════════════════════════════════════════
Date: $(date)
Repository: $REPO_URL

TOTAL CHARTS TESTED: $TOTAL_CHARTS

DOWNLOAD TESTS:
  ✓ Successful: $DOWNLOAD_SUCCESS
  ✗ Failed:     $DOWNLOAD_FAILED
  Success Rate: $(awk "BEGIN {printf \"%.1f\", ($DOWNLOAD_SUCCESS/$TOTAL_CHARTS)*100}")%

TEMPLATE RENDERING TESTS:
  ✓ Successful: $TEMPLATE_SUCCESS
  ✗ Failed:     $TEMPLATE_FAILED
  Success Rate: $(awk "BEGIN {printf \"%.1f\", ($TEMPLATE_SUCCESS/$TOTAL_CHARTS)*100}")%

OVERALL STATUS:
EOF

if [ $TEMPLATE_FAILED -eq 0 ] && [ $DOWNLOAD_FAILED -eq 0 ]; then
    echo "  ✅ ALL TESTS PASSED - Production Ready!" >> "$SUMMARY_FILE"
    echo -e "${GREEN}✅ ALL TESTS PASSED - Production Ready!${NC}"
elif [ $TEMPLATE_FAILED -lt 10 ]; then
    echo "  ⚠️  MOSTLY PASSING - Minor issues to fix" >> "$SUMMARY_FILE"
    echo -e "${YELLOW}⚠️  MOSTLY PASSING - Minor issues to fix${NC}"
else
    echo "  ❌ MULTIPLE FAILURES - Review needed" >> "$SUMMARY_FILE"
    echo -e "${RED}❌ MULTIPLE FAILURES - Review needed${NC}"
fi

echo "" >> "$SUMMARY_FILE"
echo "Detailed results: $RESULTS_FILE" >> "$SUMMARY_FILE"
echo "Test artifacts: $TEST_DIR" >> "$SUMMARY_FILE"
echo "═══════════════════════════════════════════════════" >> "$SUMMARY_FILE"

cat "$SUMMARY_FILE"

# Also append summary to results file
echo "" >> "$RESULTS_FILE"
cat "$SUMMARY_FILE" >> "$RESULTS_FILE"

#########################################################################
# Step 5: Show Failed Charts (if any)
#########################################################################
if [ $TEMPLATE_FAILED -gt 0 ] || [ $DOWNLOAD_FAILED -gt 0 ]; then
    echo ""
    echo -e "${RED}Failed Charts:${NC}"
    grep "✗" "$RESULTS_FILE" | grep -E "Download FAILED|Template rendering FAILED" | while read line; do
        echo -e "${RED}  $line${NC}"
    done
fi

echo ""
echo "Full test results saved to: $RESULTS_FILE"
echo "Summary saved to: $SUMMARY_FILE"

# Exit with appropriate code
if [ $TEMPLATE_FAILED -eq 0 ] && [ $DOWNLOAD_FAILED -eq 0 ]; then
    exit 0
else
    exit 1
fi
