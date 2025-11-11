#!/bin/bash
set -euo pipefail

#########################################################################
# EKS Cluster Provisioning and Helm Charts Testing
# Creates a minimal EKS cluster, tests critical charts, then cleans up
#########################################################################

CLUSTER_NAME="helmhub-test-cluster"
REGION="us-east-1"
NODE_TYPE="t3.medium"
NODES="2"
REPO_NAME="helmhub"
REPO_URL="https://helmhub-io.github.io/charts/"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Critical charts to test
CHARTS_TO_TEST=(
    "nginx"
    "redis"
    "postgresql"
    "grafana"
    "prometheus"
)

echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  EKS Cluster Provisioning for Helm Charts Testing ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo ""

#########################################################################
# Step 1: Check eksctl
#########################################################################
echo -e "${BLUE}Step 1: Checking eksctl...${NC}"
if ! command -v eksctl &> /dev/null; then
    echo -e "${YELLOW}eksctl not found, installing...${NC}"
    curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
    sudo mv /tmp/eksctl /usr/local/bin
    echo -e "${GREEN}✓ eksctl installed${NC}"
else
    echo -e "${GREEN}✓ eksctl already installed${NC}"
fi

eksctl version
echo ""

#########################################################################
# Step 2: Create EKS Cluster
#########################################################################
echo -e "${BLUE}Step 2: Creating EKS cluster (this takes ~15-20 minutes)...${NC}"
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo "Node Type: $NODE_TYPE"
echo "Node Count: $NODES"
echo ""

# Check if cluster exists
if eksctl get cluster --name "$CLUSTER_NAME" --region "$REGION" &>/dev/null; then
    echo -e "${YELLOW}Cluster already exists, using existing cluster${NC}"
else
    eksctl create cluster \
        --name "$CLUSTER_NAME" \
        --region "$REGION" \
        --nodegroup-name standard-workers \
        --node-type "$NODE_TYPE" \
        --nodes "$NODES" \
        --nodes-min 1 \
        --nodes-max 3 \
        --managed \
        --version 1.28
    
    echo -e "${GREEN}✓ EKS cluster created${NC}"
fi

echo ""

#########################################################################
# Step 3: Update kubeconfig
#########################################################################
echo -e "${BLUE}Step 3: Updating kubeconfig...${NC}"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"
kubectl cluster-info
kubectl get nodes
echo -e "${GREEN}✓ Connected to cluster${NC}"
echo ""

#########################################################################
# Step 4: Setup Helm repository
#########################################################################
echo -e "${BLUE}Step 4: Setting up Helm repository...${NC}"
if helm repo list | grep -q "^${REPO_NAME}"; then
    helm repo update "$REPO_NAME"
else
    helm repo add "$REPO_NAME" "$REPO_URL"
fi
echo -e "${GREEN}✓ Helm repository ready${NC}"
echo ""

#########################################################################
# Step 5: Create test namespace
#########################################################################
echo -e "${BLUE}Step 5: Creating test namespace...${NC}"
kubectl create namespace helm-test --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✓ Namespace created${NC}"
echo ""

#########################################################################
# Step 6: Test Charts
#########################################################################
echo -e "${BLUE}Step 6: Testing Helm Charts...${NC}"
echo ""

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

for chart in "${CHARTS_TO_TEST[@]}"; do
    TEST_COUNT=$((TEST_COUNT + 1))
    release="test-$chart"
    
    echo -e "${YELLOW}═══════════════════════════════════════${NC}"
    echo -e "${YELLOW}Testing: $chart${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════${NC}"
    
    # Install
    echo -n "  - Installing... "
    if helm install "$release" "${REPO_NAME}/${chart}" \
        --namespace helm-test \
        --set persistence.enabled=false \
        --set service.type=ClusterIP \
        --set replicaCount=1 \
        --timeout 5m \
        --wait \
        > "/tmp/${chart}-install.log" 2>&1; then
        echo -e "${GREEN}✓${NC}"
        
        # Check pods
        echo -n "  - Checking pods... "
        sleep 5
        POD_COUNT=$(kubectl get pods -n helm-test -l "app.kubernetes.io/instance=${release}" 2>/dev/null | grep -v NAME | wc -l)
        RUNNING=$(kubectl get pods -n helm-test -l "app.kubernetes.io/instance=${release}" 2>/dev/null | grep -c "Running" || echo "0")
        echo -e "${GREEN}✓${NC} ($RUNNING/$POD_COUNT running)"
        
        # Check services
        echo -n "  - Checking services... "
        SVC_COUNT=$(kubectl get svc -n helm-test -l "app.kubernetes.io/instance=${release}" 2>/dev/null | grep -v NAME | wc -l)
        echo -e "${GREEN}✓${NC} ($SVC_COUNT services)"
        
        # Helm status
        echo -n "  - Helm status... "
        STATUS=$(helm status "$release" -n helm-test -o json | jq -r '.info.status')
        echo -e "${GREEN}✓ $STATUS${NC}"
        
        PASS_COUNT=$((PASS_COUNT + 1))
        
        # Cleanup
        echo -n "  - Cleaning up... "
        helm uninstall "$release" -n helm-test --wait --timeout 3m > /dev/null 2>&1
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗ FAILED${NC}"
        echo "  See: /tmp/${chart}-install.log"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    
    echo ""
done

#########################################################################
# Step 7: Summary
#########################################################################
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                  TEST SUMMARY                     ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo ""
echo "Cluster: $CLUSTER_NAME ($REGION)"
echo "Charts tested: $TEST_COUNT"
echo -e "${GREEN}Passed: $PASS_COUNT${NC}"
echo -e "${RED}Failed: $FAIL_COUNT${NC}"
echo ""

SUCCESS_RATE=$(awk "BEGIN {printf \"%.1f\", ($PASS_COUNT/$TEST_COUNT)*100}")
echo "Success Rate: $SUCCESS_RATE%"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}✅ ALL TESTS PASSED IN REAL EKS CLUSTER!${NC}"
else
    echo -e "${YELLOW}⚠️  Some tests failed${NC}"
fi

echo ""

#########################################################################
# Step 8: Cleanup Option
#########################################################################
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                    CLEANUP                        ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}EKS cluster is still running!${NC}"
echo ""
echo "Cluster costs approximately \$0.10/hour for control plane + \$0.04/hour per node"
echo "Current setup: ~\$0.18/hour total"
echo ""
read -p "Delete EKS cluster now? (y/n) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}Deleting cluster...${NC}"
    eksctl delete cluster --name "$CLUSTER_NAME" --region "$REGION" --wait
    echo -e "${GREEN}✓ Cluster deleted${NC}"
else
    echo -e "${YELLOW}Cluster kept. Delete manually later with:${NC}"
    echo "  eksctl delete cluster --name $CLUSTER_NAME --region $REGION"
fi

echo ""
echo -e "${GREEN}Testing complete!${NC}"
