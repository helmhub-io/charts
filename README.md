<!-- markdownlint-disable MD041 -->
<p align="center">
    <img width="400px" height=auto src="https://dyltqmyl993wv.cloudfront.net/helmhubio/bitnami-by-vmware.png" />
</p>

<p align="center">
    <a href="https://x.com/helmhubio"><img src="https://badgen.net/badge/twitter/@helmhubio/1DA1F2?icon&label" /></a>
    <a href="https://github.com/helmhub-io/charts"><img src="https://badgen.net/github/stars/helmhubio/charts?icon=github" /></a>
    <a href="https://github.com/helmhub-io/charts"><img src="https://badgen.net/github/forks/helmhubio/charts?icon=github" /></a>
    <a href="https://artifacthub.io/packages/search?repo=helmhubio"><img src="https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/helmhubio" /></a>
</p>

# The HelmHubIO Library for Kubernetes

Popular applications, provided by [HelmHubIO](https://helmhub.io), ready to launch on Kubernetes using [Kubernetes Helm](https://github.com/helm/helm).

## TL;DR

```console
helm install my-release oci://registry-1.docker.io/helmhubiocharts/<chart>
```

## Vulnerabilities scanner

Each Helm chart contains one or more containers. Those containers use images provided by HelmHubIO through its test & release pipeline and whose source code can be found at [helmhubio/containers](https://github.com/helmhub-io/containers).

As part of the container releases, the images are scanned for vulnerabilities, [here](https://github.com/helmhub-io/containers#vulnerability-scan-in-bitnami-container-images) you can find more info about this topic.

Since the container image is an immutable artifact that is already analyzed, as part of the Helm chart release process we are not looking for vulnerabilities in the containers but running different verifications to ensure the Helm charts work as expected, see the testing strategy defined at [_TESTING.md_](https://github.com/helmhub-io/charts/blob/main/TESTING.md).

## Before you begin

### Prerequisites

- Kubernetes 1.23+
- Helm 3.8.0+

### Setup a Kubernetes Cluster

The quickest way to set up a Kubernetes cluster to install HelmHubIO Charts is by following the "Get Started" guides for the different Kubernetes Providers:

- [Get Started with Kubernetes Using using the Amazon Elastic Container Service for Kubernetes (EKS)](https://docs.aws.amazon.com/eks/latest/userguide/getting-started.html)
- [Get Started With Kubernetes Using Azure Kubernetes Service](https://learn.microsoft.com/en-us/azure/aks/learn/quick-kubernetes-deploy-portal?tabs=azure-cli)
- [Get Started with Kubernetes Using using the Google Kubernetes Engine (GKE)](https://www.skills.google/paths/11/course_templates/2)

For setting up Kubernetes on other cloud platforms or bare-metal servers refer to the Kubernetes [getting started guide](https://kubernetes.io/docs/getting-started-guides/).

### Install Helm

Helm is a tool for managing Kubernetes charts. Charts are packages of pre-configured Kubernetes resources.

To install Helm, refer to the [Helm install guide](https://github.com/helm/helm#install) and ensure that the `helm` binary is in the `PATH` of your shell.

### Using Helm

Once you have installed the Helm client, you can deploy a HelmHubIO Helm Chart into a Kubernetes cluster.

Please refer to the [Quick Start guide](https://helm.sh/docs/intro/quickstart/) if you wish to get running in just a few commands, otherwise, the [Using Helm Guide](https://helm.sh/docs/intro/using_helm/) provides detailed instructions on how to use the Helm client to manage packages on your Kubernetes cluster.

Useful Helm Client Commands:

- Install a chart: `helm install my-release oci://registry-1.docker.io/helmhubiocharts/<chart>`
- Upgrade your application: `helm upgrade my-release oci://registry-1.docker.io/helmhubiocharts/<chart>`

## License

Copyright &copy; 2025 HelmHubIO

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

<http://www.apache.org/licenses/LICENSE-2.0>

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
