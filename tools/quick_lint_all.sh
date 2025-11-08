#!/bin/bash
# Quick validation - helm lint only for all charts

cd /home/freeman/helmchart/charts/helmhubio

echo "Testing all charts with helm lint..."
echo ""

PASS=0
FAIL=0
TOTAL=0

for chart_dir in */; do
    chart="${chart_dir%/}"
    
    [ ! -f "$chart/Chart.yaml" ] && continue
    [ "$chart" = "common" ] && continue
    
    ((TOTAL++)) || true
    
    if helm lint "$chart" >/dev/null 2>&1; then
        echo "✅ $chart"
        ((PASS++)) || true
    else
        echo "❌ $chart"
        ((FAIL++)) || true
        # Show error
        helm lint "$chart" 2>&1 | grep -i "error" | head -2
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SUMMARY:"
echo "  Total: $TOTAL"
echo "  ✅ Pass: $PASS"
echo "  ❌ Fail: $FAIL"
echo "  Success: $((PASS * 100 / TOTAL))%"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
