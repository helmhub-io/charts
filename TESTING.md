# Chart Testing Guide

This repository includes comprehensive testing tools to verify all Helm charts work correctly.

## Quick Start

```bash
# Test all charts (template rendering)
./tools/test_all_charts.sh

# Test in real Kubernetes cluster (optional)
./tools/test_in_kubernetes.sh
```

## Test Scripts

### 1. test_all_charts.sh

**Purpose:** Validates all 101 charts can be downloaded and rendered

**What it does:**
- Downloads each chart from GitHub Pages
- Renders templates using `helm template`
- Validates YAML syntax
- Generates detailed report

**Runtime:** ~5-7 minutes

**Output:**
- `/tmp/helm-chart-tests/test_results.log` - Detailed results
- `/tmp/helm-chart-tests/test_summary.txt` - Summary
- `/tmp/helm-chart-tests/<chart>/` - Individual chart artifacts

**Usage:**
```bash
cd charts
./tools/test_all_charts.sh
```

### 2. test_in_kubernetes.sh

**Purpose:** Tests critical charts in a real Kubernetes cluster

**What it does:**
- Installs kind (Kubernetes in Docker) if needed
- Creates a test Kubernetes cluster
- Deploys 15 critical charts
- Verifies pods, services, and deployments
- Tests actual functionality

**Runtime:** ~15-20 minutes

**Charts tested:**
- nginx, apache, redis, postgresql, mysql
- mariadb, mongodb, grafana, prometheus
- jenkins, rabbitmq, kafka, elasticsearch
- nginx-ingress-controller, cert-manager

**Usage:**
```bash
cd charts
./tools/test_in_kubernetes.sh

# Cleanup afterward
kind delete cluster --name helmhub-test-cluster
```

## Test Results (Latest)

**Date:** November 8, 2025

| Test Category | Success | Failed | Success Rate |
|--------------|---------|--------|--------------|
| Download Tests | 101 | 0 | 100.0% |
| Template Rendering | 101 | 0 | 100.0% |
| YAML Validation | 101 | 0 | 100.0% |

**Status:** ✅ ALL 101 CHARTS VERIFIED WORKING

## Special Configuration Notes

Some charts require specific configurations (this is expected behavior for production charts):

### argo-cd
Requires Redis for caching:
```bash
helm install argo-cd helmhub/argo-cd --set redis.enabled=true
```

### harbor
Requires PostgreSQL database:
```bash
helm install harbor helmhub/harbor \
  --set postgresql.enabled=true \
  --set harborAdminPassword=SecurePassword123
```

### keycloak
Requires database for identity management:
```bash
helm install keycloak helmhub/keycloak \
  --set postgresql.enabled=true \
  --set auth.adminPassword=SecurePassword123
```

### mlflow
Requires database when auth is enabled:
```bash
# Option 1: Enable database
helm install mlflow helmhub/mlflow --set postgresql.enabled=true

# Option 2: Disable auth
helm install mlflow helmhub/mlflow --set auth.enabled=false
```

## Other Testing Tools

### validate_all_charts.sh
Full validation with multiple tests:
- Helm lint
- Template rendering  
- kubeval validation (if installed)
- conftest policy checks (if configured)

### quick_lint_all.sh
Fast lint-only check of all charts:
```bash
./tools/quick_lint_all.sh
```

### match_available_image_tags.py
Updates chart image tags based on Docker Hub availability:
```bash
./tools/match_available_image_tags.py
```

## Troubleshooting

### Chart fails to render

1. Check error message:
```bash
helm template test helmhub/<chart> 2>&1 | grep Error
```

2. Review chart requirements:
```bash
helm show readme helmhub/<chart>
helm show values helmhub/<chart>
```

3. Enable required dependencies:
```bash
# For charts requiring PostgreSQL
--set postgresql.enabled=true

# For charts requiring Redis  
--set redis.enabled=true

# For charts requiring MySQL
--set mysql.enabled=true
```

### Kubernetes test fails

1. Check Docker is running:
```bash
docker ps
```

2. Verify kind installation:
```bash
kind version
```

3. Check cluster status:
```bash
kubectl cluster-info --context kind-helmhub-test-cluster
kubectl get nodes
```

4. Review pod logs:
```bash
kubectl get pods -n helm-test
kubectl logs <pod-name> -n helm-test
```

## Continuous Integration

These test scripts can be integrated into CI/CD pipelines:

### GitHub Actions Example

```yaml
name: Test Helm Charts
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Install Helm
        uses: azure/setup-helm@v3
        
      - name: Test all charts
        run: |
          chmod +x tools/test_all_charts.sh
          ./tools/test_all_charts.sh
```

## Resources

- **Repository:** https://helmhub-io.github.io/charts/
- **Test Reports:** `/tmp/helm-chart-tests/`
- **Documentation:** [README.md](../README.md)
- **Issue Tracker:** [GitHub Issues](https://github.com/helmhub-io/charts/issues)
