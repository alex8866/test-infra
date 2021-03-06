#!/bin/bash
# Copyright 2016 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o nounset
set -o pipefail
set -o xtrace

readonly testinfra="$(dirname "${0}")/.."

# TODO(fejta): remove this
if [[ "${ghprbTargetBranch:-}" == "release-1.0" || "${ghprbTargetBranch:-}" == "release-1.1" ]]; then
  echo "PR GCE job disabled for legacy branches."
  exit
fi

export KUBE_GCS_RELEASE_BUCKET=kubernetes-release-pull
export KUBE_GCS_RELEASE_SUFFIX="/${JOB_NAME}"
export KUBE_GCS_UPDATE_LATEST=n
export JENKINS_USE_LOCAL_BINARIES=y
export KUBE_FASTBUILD=true
./hack/jenkins/build.sh

export KUBERNETES_PROVIDER="gce"
export E2E_MIN_STARTUP_PODS="1"
export KUBE_GCE_ZONE="us-central1-f"

# Flake detection. Individual tests get a second chance to pass.
export GINKGO_TOLERATE_FLAKES="y"

export E2E_NAME="cri-e2e-${NODE_NAME}-${EXECUTOR_NUMBER:-0}"
export GINKGO_PARALLEL="y"
# This list should match the list in kubernetes-e2e-gce.
export GINKGO_TEST_ARGS='--ginkgo.skip=\[Slow\]|\[Serial\]|\[Disruptive\]|\[Flaky\]|\[Feature:.+\]'
export FAIL_ON_GCP_RESOURCE_LEAK="false"
export PROJECT="kubernetes-pr-cri-validation"
# NUM_NODES and GINKGO_PARALLEL_NODES should match kubernetes-e2e-gce.
export NUM_NODES="3"

# Force to use container-vm.
export KUBE_NODE_OS_DISTRIBUTION="gci"

# Enable experimental CRI integration
export KUBELET_TEST_ARGS="--experimental-runtime-integration-type=cri"

# Assume we're upping, testing, and downing a cluster
export E2E_UP="true"
export E2E_TEST="true"
export E2E_DOWN="true"

# Skip gcloud update checking
export CLOUDSDK_COMPONENT_MANAGER_DISABLE_UPDATE_CHECK=true

# GCE variables
export INSTANCE_PREFIX=${E2E_NAME}
export KUBE_GCE_NETWORK=${E2E_NAME}
export KUBE_GCE_INSTANCE_PREFIX=${E2E_NAME}

# Get golang into our PATH so we can run e2e.go
export PATH=${PATH}:/usr/local/go/bin

readonly runner="${testinfra}/jenkins/dockerized-e2e-runner.sh"
timeout -k 15m 55m "${runner}" && rc=$? || rc=$?
if [[ ${rc} -ne 0 ]]; then
  if [[ -x cluster/log-dump.sh && -d _artifacts ]]; then
    echo "Dumping logs for any remaining nodes"
    ./cluster/log-dump.sh _artifacts
  fi
fi
if [[ ${rc} -eq 124 || ${rc} -eq 137 ]]; then
  echo "Build timed out" >&2
elif [[ ${rc} -ne 0 ]]; then
  echo "Build failed" >&2
fi
echo "Exiting with code: ${rc}"
exit ${rc}
