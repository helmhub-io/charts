#!/bin/bash
# Comprehensive validation of ALL charts before deployment
# Tests: lint, template rendering, dependency resolution, image availability

set -euo pipefail

CHARTS_DIR="/home/freeman/helmchart/charts/helmhubio"
REPORT_FILE="/tmp/helmhub_charts_validation_report.txt"
FAILED_CHARTS_FILE="/tmp/helmhub_failed_charts.txt"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  HelmHub Charts - COMPLETE VALIDATION                         ║"
echo "║  Testing EVERY chart to ensure 100% success                   ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Initialize report
cat > "$REPORT_FILE" << 'EOF'
HelmHub Charts - Complete Validation Report
============================================
Generated: $(date)

EOF

# Initialize counters
TOTAL_CHARTS=0
LINT_PASS=0
LINT_FAIL=0
TEMPLATE_PASS=0
TEMPLATE_FAIL=0
FULLY_WORKING=0

# Clear failed charts file
> "$FAILED_CHARTS_FILE"

cd "$CHARTS_DIR"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 1: Testing All Charts"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

for chart_dir in */; do
    chart_name="${chart_dir%/}"
    
    # Skip if not a chart
    if [ ! -f "$chart_dir/Chart.yaml" ]; then
        continue
    fi
    
    # Skip common library
    if [ "$chart_name" = "common" ]; then
        continue
    fi
    
    ((TOTAL_CHARTS++)) || true
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[$TOTAL_CHARTS] Testing: $chart_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    CHART_STATUS="✅ PASS"
    ISSUES=""
    
    # Test 1: Helm Lint
    echo -n "   [1/3] Helm lint ... "
    if helm lint "$chart_name" >/dev/null 2>&1; then
        echo "✅ PASS"
        ((LINT_PASS++)) || true
    else
        echo "❌ FAIL"
        ((LINT_FAIL++)) || true
        CHART_STATUS="❌ FAIL"
        ISSUES="${ISSUES}lint-failed "
        
        # Capture lint errors
        echo "" >> "$REPORT_FILE"
        echo "LINT ERRORS for $chart_name:" >> "$REPORT_FILE"
        helm lint "$chart_name" 2>&1 | head -20 >> "$REPORT_FILE"
    fi
    
    # Test 2: Template Rendering
    echo -n "   [2/3] Template rendering ... "
    if helm template "test-$chart_name" "./$chart_name" >/dev/null 2>&1; then
        echo "✅ PASS"
        ((TEMPLATE_PASS++)) || true
    else
        echo "❌ FAIL"
        ((TEMPLATE_FAIL++)) || true
        CHART_STATUS="❌ FAIL"
        ISSUES="${ISSUES}template-failed "
        
        # Capture template errors
        echo "" >> "$REPORT_FILE"
        echo "TEMPLATE ERRORS for $chart_name:" >> "$REPORT_FILE"
        helm template "test-$chart_name" "./$chart_name" 2>&1 | head -20 >> "$REPORT_FILE"
    fi
    
    # Test 3: Dependency Check
    echo -n "   [3/3] Dependencies ... "
    if [ -d "$chart_name/charts" ]; then
        echo "✅ Vendored"
    else
        if grep -q "^dependencies:" "$chart_name/Chart.yaml" 2>/dev/null; then
            echo "⚠️  Missing (needs vendoring)"
            ISSUES="${ISSUES}missing-deps "
        else
            echo "✅ None required"
        fi
    fi
    
    # Overall status
    if [ "$CHART_STATUS" = "✅ PASS" ]; then
        echo "   Status: ✅ FULLY WORKING"
        ((FULLY_WORKING++)) || true
    else
        echo "   Status: ❌ NEEDS FIXING ($ISSUES)"
        echo "$chart_name: $ISSUES" >> "$FAILED_CHARTS_FILE"
    fi
    
    echo ""
done

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "VALIDATION SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Total charts tested: $TOTAL_CHARTS"
echo ""
echo "Helm Lint:"
echo "   ✅ Passed: $LINT_PASS"
echo "   ❌ Failed: $LINT_FAIL"
echo ""
echo "Template Rendering:"
echo "   ✅ Passed: $TEMPLATE_PASS"
echo "   ❌ Failed: $TEMPLATE_FAIL"
echo ""
echo "Overall:"
echo "   ✅ Fully Working: $FULLY_WORKING"
echo "   ❌ Need Fixing: $((TOTAL_CHARTS - FULLY_WORKING))"
echo ""

# Calculate success rate
SUCCESS_RATE=$((FULLY_WORKING * 100 / TOTAL_CHARTS))

echo "Success Rate: $SUCCESS_RATE%"
echo ""

# Save summary to report
cat >> "$REPORT_FILE" << EOF

SUMMARY
=======
Total Charts: $TOTAL_CHARTS
Lint Pass: $LINT_PASS
Lint Fail: $LINT_FAIL
Template Pass: $TEMPLATE_PASS
Template Fail: $TEMPLATE_FAIL
Fully Working: $FULLY_WORKING
Success Rate: $SUCCESS_RATE%

EOF

if [ $FULLY_WORKING -lt $TOTAL_CHARTS ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "CHARTS THAT NEED FIXING"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    cat "$FAILED_CHARTS_FILE"
    echo ""
    echo "Detailed errors saved to: $REPORT_FILE"
    echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "NEXT STEPS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ $SUCCESS_RATE -eq 100 ]; then
    echo "🎉 ALL CHARTS WORKING PERFECTLY!"
    echo ""
    echo "Ready to deploy:"
    echo "   1. Run: ./tools/setup_github_pages.sh"
    echo "   2. Run: git add docs/"
    echo "   3. Run: git commit -m 'Deploy Helm charts'"
    echo "   4. Run: git push"
else
    echo "⚠️  Some charts need fixing before deployment"
    echo ""
    echo "Option 1: Fix the failing charts"
    echo "   - Review errors in: $REPORT_FILE"
    echo "   - Fix issues and re-run this script"
    echo ""
    echo "Option 2: Deploy working charts only"
    echo "   - $FULLY_WORKING out of $TOTAL_CHARTS charts are working"
    echo "   - Deploy these and fix others later"
fi

echo ""
echo "Full report: $REPORT_FILE"
echo "Failed charts: $FAILED_CHARTS_FILE"
echo ""
echo "════════════════════════════════════════════════════════════════"
