#!/bin/bash
set -euo pipefail

#########################################################################
# Kubernetes Deployment Testing Script
# Tests critical charts in a real Kubernetes cluster (kind/minikube)
#########################################################################

REPO_NAME="helmhub"
REPO_URL="https://helmhub-io.github.io/charts/"
CLUSTER_NAME="helmhub-test-cluster"
TEST_NAMESPACE="helm-test"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Charts to test (most critical ones)
CRITICAL_CHARTS=(
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
    "elasticsearch"
    "nginx-ingress-controller"
    "cert-manager"
)

#########################################################################
# Functions
#########################################################################

install_kind() {
    echo -e "${BLUE}Installing kind (Kubernetes in Docker)...${NC}"
    if ! command -v kind &> /dev/null; then
        # Install kind
        curl -Lo /tmp/kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
        chmod +x /tmp/kind
        sudo mv /tmp/kind /usr/local/bin/kind
        echo -e "${GREEN}✓ kind installed${NC}"
    elsewhich
        echo -e "${GREEN}✓ kind already installed${NC}"
    fi
}

install_kubectl() {
    echo -e "${BLUE}Checking kubectl...${NC}"
    if ! kubectl version --client &> /dev/null; then
        echo -e "${YELLOW}kubectl not working properly, installing...${NC}"
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/
        echo -e "${GREEN}✓ kubectl installed${NC}"
    else
        echo -e "${GREEN}✓ kubectl ready${NC}"
    fi
}

create_cluster() {
    echo -e "${BLUE}Creating Kubernetes cluster: $CLUSTER_NAME${NC}"
    
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        echo -e "${YELLOW}Cluster already exists, deleting old one...${NC}"
        kind delete cluster --name "$CLUSTER_NAME"
    fi
    
    cat > /tmp/kind-config.yaml << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF
    
    kind create cluster --name "$CLUSTER_NAME" --config /tmp/kind-config.yaml --wait 5m
    
    # Set context
    kubectl cluster-info --context "kind-${CLUSTER_NAME}"
    
    echo -e "${GREEN}✓ Cluster created and ready${NC}"
}

setup_helm_repo() {
    echo -e "${BLUE}Setting up Helm repository${NC}"
    if helm repo list | grep -q "^${REPO_NAME}"; then
        helm repo update "$REPO_NAME"
    else
        helm repo add "$REPO_NAME" "$REPO_URL"
    fi
    echo -e "${GREEN}✓ Helm repository ready${NC}"
}

create_test_namespace() {
    echo -e "${BLUE}Creating test namespace: $TEST_NAMESPACE${NC}"
    kubectl create namespace "$TEST_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    echo -e "${GREEN}✓ Namespace ready${NC}"
}

test_chart_deployment() {
    local chart_name=$1
    local release_name="test-${chart_name}"
    
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════${NC}"
    echo -e "${YELLOW}Testing: $chart_name${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════${NC}"
    
    # Install chart with minimal configuration
    echo -n "  - Installing chart... "
    if helm install "$release_name" "${REPO_NAME}/${chart_name}" \
        --namespace "$TEST_NAMESPACE" \
        --set persistence.enabled=false \
        --set service.type=ClusterIP \
        --set ingress.enabled=false \
        --set metrics.enabled=false \
        --set replicaCount=1 \
        --timeout 3m \
        --wait \
        2>&1 | tee "/tmp/${chart_name}-install.log" | grep -v "^$" > /dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗ FAILED${NC}"
        echo "  Error log: /tmp/${chart_name}-install.log"
        return 1
    fi
    
    # Check pod status
    echo -n "  - Checking pods... "
    sleep 5
    POD_COUNT=$(kubectl get pods -n "$TEST_NAMESPACE" -l "app.kubernetes.io/instance=${release_name}" --no-headers 2>/dev/null | wc -l)
    if [ "$POD_COUNT" -gt 0 ]; then
        RUNNING_PODS=$(kubectl get pods -n "$TEST_NAMESPACE" -l "app.kubernetes.io/instance=${release_name}" --no-headers 2>/dev/null | grep -c "Running" || true)
        echo -e "${GREEN}✓${NC} ($RUNNING_PODS/$POD_COUNT running)"
    else
        echo -e "${YELLOW}⚠${NC} (no pods found)"
    fi
    
    # Check services
    echo -n "  - Checking services... "
    SVC_COUNT=$(kubectl get svc -n "$TEST_NAMESPACE" -l "app.kubernetes.io/instance=${release_name}" --no-headers 2>/dev/null | wc -l)
    echo -e "${GREEN}✓${NC} ($SVC_COUNT services)"
    
    # Get release status
    echo -n "  - Release status... "
    STATUS=$(helm status "$release_name" -n "$TEST_NAMESPACE" -o json | jq -r '.info.status')
    if [ "$STATUS" = "deployed" ]; then
        echo -e "${GREEN}✓ $STATUS${NC}"
    else
        echo -e "${YELLOW}⚠ $STATUS${NC}"
    fi
    
    # Cleanup
    echo -n "  - Cleaning up... "
    helm uninstall "$release_name" -n "$TEST_NAMESPACE" --wait --timeout 2m > /dev/null 2>&1
    echo -e "${GREEN}✓${NC}"
    
    return 0
}

cleanup_cluster() {
    echo ""
    echo -e "${BLUE}Cleaning up cluster${NC}"
    kind delete cluster --name "$CLUSTER_NAME"
    echo -e "${GREEN}✓ Cluster deleted${NC}"
}

#########################################################################
# Main Execution
#########################################################################

echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Kubernetes Deployment Testing for Helm Charts    ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo ""

# Check if user wants to install kind
if ! command -v kind &> /dev/null; then
    echo -e "${YELLOW}kind is not installed.${NC}"
    read -p "Install kind? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_kind
    else
        echo -e "${RED}Cannot proceed without kind. Exiting.${NC}"
        exit 1
    fi
fi

# Setup prerequisites
install_kubectl
setup_helm_repo

# Create cluster
create_cluster
create_test_namespace

# Test counters
TOTAL_TESTS=${#CRITICAL_CHARTS[@]}
PASSED=0
FAILED=0

# Test each critical chart
for chart in "${CRITICAL_CHARTS[@]}"; do
    if test_chart_deployment "$chart"; then
        PASSED=$((PASSED + 1))
    else
        FAILED=$((FAILED + 1))
    fi
    
    # Small pause between tests
    sleep 2
done

# Summary
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                  TEST SUMMARY                     ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo ""
echo "Total charts tested: $TOTAL_TESTS"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo ""

SUCCESS_RATE=$(awk "BEGIN {printf \"%.1f\", ($PASSED/$TOTAL_TESTS)*100}")
echo "Success Rate: $SUCCESS_RATE%"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ ALL TESTS PASSED!${NC}"
    STATUS_CODE=0
else
    echo -e "${YELLOW}⚠️  Some tests failed, review logs in /tmp/${NC}"
    STATUS_CODE=1
fi

# Cleanup
read -p "Delete test cluster? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    cleanup_cluster
else
    echo -e "${YELLOW}Cluster kept for manual inspection: $CLUSTER_NAME${NC}"
    echo "To delete later: kind delete cluster --name $CLUSTER_NAME"
fi

exit $STATUS_CODE
