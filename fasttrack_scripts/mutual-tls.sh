#!/usr/bin/env bash

# Copyright 2019 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# TASK: This script completes the deploy application section of ASM workshop.

#!/bin/bash

# Verify that the scripts are being run from Linux and not Mac
if [[ $OSTYPE != "linux-gnu" ]]; then
    echo "ERROR: This script and consecutive set up scripts have only been tested on Linux. Currently, only Linux (debian) is supported. Please run in Cloud Shell or in a VM running Linux".
    exit;
fi

# Export a SCRIPT_DIR var and make all links relative to SCRIPT_DIR
export SCRIPT_DIR=$(dirname $(readlink -f $0 2>/dev/null) 2>/dev/null || echo "${PWD}/$(dirname $0)")
export LAB_NAME=mutual-tls

# Create a logs folder and file and send stdout and stderr to console and log file 
mkdir -p ${SCRIPT_DIR}/../logs
export LOG_FILE=${SCRIPT_DIR}/../logs/ft-${LAB_NAME}-$(date +%s).log
touch ${LOG_FILE}
exec 2>&1
exec &> >(tee -i ${LOG_FILE})

source ${SCRIPT_DIR}/../scripts/functions.sh

# Lab: Mutual TLS

# Set speed
bold=$(tput bold)
normal=$(tput sgr0)

color='\e[1;32m' # green
nc='\e[0m'

echo -e "\n"
title_no_wait "*** Lab: Mutual TLS ***"
echo -e "\n"

title_and_wait "Check MeshPolicy in ops clusters."
print_and_execute "kubectl --context ${OPS_GKE_1} get MeshPolicy -o json | jq '.items[].spec'"
print_and_execute "kubectl --context ${OPS_GKE_2} get MeshPolicy -o json | jq '.items[].spec'"

# validate permissive state
PERMISSIVE_OPS_1=`kubectl --context ${OPS_GKE_1} get MeshPolicy -o json | jq -r '.items[].spec.peers[].mtls.mode'`
if [[ ${PERMISSIVE_OPS_1} == "PERMISSIVE" ]]
then 
    title_no_wait "Note mTLS is PERMISSIVE in ${OPS_GKE_1} cluster, allowing for both encrypted and non-mTLS traffic."
elif [[ ${PERMISSIVE_OPS_1} == "{}" ]]
then
    title_no_wait "mTLS is already configured on the ${OPS_GKE_1} cluster"
fi

PERMISSIVE_OPS_2=`kubectl --context ${OPS_GKE_2} get MeshPolicy -o json | jq -r '.items[].spec.peers[].mtls.mode'`
if [[ ${PERMISSIVE_OPS_2} == "PERMISSIVE" ]]
then 
    title_no_wait "Note mTLS is PERMISSIVE in ${OPS_GKE_2} cluster, allowing for both encrypted and non-mTLS traffic."
elif [[ ${PERMISSIVE_OPS_2} == "{}" ]]
then
    title_no_wait "mTLS is already configured on the ${OPS_GKE_2} cluster"
fi

title_no_wait "Turn on mTLS. The Istio operator controller is running and we can change the "
title_no_wait "Istio configuration by editing or replacing the IstioControlPlane resource. "
title_no_wait "The controller will detect the change and respond by updating the Istio installation "
title_no_wait "accordingly. We will set mtls to enabled in the IstioControlPlane resource for both "
title_no_wait "the shared and replicated control plane. This will set the MeshPolicy to ISTIO_MUTUAL "
title_and_wait "and create a default Destination Rule."

print_and_execute "cd ${WORKDIR}/asm"
print_and_execute "sed -i '/global:/a\ \ \ \ \ \ mtls:\n\ \ \ \ \ \ \ \ enabled: true' ${WORKDIR}/k8s-repo/${OPS_GKE_1_CLUSTER}/istio-controlplane/istio-replicated-controlplane.yaml"
print_and_execute "sed -i '/global:/a\ \ \ \ \ \ mtls:\n\ \ \ \ \ \ \ \ enabled: true' ${WORKDIR}/k8s-repo/${OPS_GKE_2_CLUSTER}/istio-controlplane/istio-replicated-controlplane.yaml"
print_and_execute "sed -i '/global:/a\ \ \ \ \ \ mtls:\n\ \ \ \ \ \ \ \ enabled: true' ${WORKDIR}/k8s-repo/${DEV1_GKE_1_CLUSTER}/istio-controlplane/istio-shared-controlplane.yaml"
print_and_execute "sed -i '/global:/a\ \ \ \ \ \ mtls:\n\ \ \ \ \ \ \ \ enabled: true' ${WORKDIR}/k8s-repo/${DEV1_GKE_2_CLUSTER}/istio-controlplane/istio-shared-controlplane.yaml"
print_and_execute "sed -i '/global:/a\ \ \ \ \ \ mtls:\n\ \ \ \ \ \ \ \ enabled: true' ${WORKDIR}/k8s-repo/${DEV2_GKE_1_CLUSTER}/istio-controlplane/istio-shared-controlplane.yaml"
print_and_execute "sed -i '/global:/a\ \ \ \ \ \ mtls:\n\ \ \ \ \ \ \ \ enabled: true' ${WORKDIR}/k8s-repo/${DEV2_GKE_2_CLUSTER}/istio-controlplane/istio-shared-controlplane.yaml"
 
title_and_wait "Commit to k8s-repo."

print_and_execute "cd ${WORKDIR}/k8s-repo"
print_and_execute "git add . && git commit -am \"turn mTLS on\""
print_and_execute "git push"
 
title_and_wait "Wait for rollout to complete"
print_and_execute "${WORKDIR}/asm/scripts/stream_logs.sh $TF_VAR_ops_project_name"
 
title_no_wait "Verify mTLS"
title_and_wait "Check MeshPolicy once more in ops clusters. Note mTLS is no longer PERMISSIVE and will only allow for mTLS traffic."
print_and_execute "kubectl --context ${OPS_GKE_1} get MeshPolicy -o yaml"
print_and_execute "kubectl --context ${OPS_GKE_2} get MeshPolicy -o yaml"

# actually validate here
# Output (do not copy):
# 
# spec:
#     peers:
#     - mtls: {}

# validate not-permissive state
NUM_MTLS_1=`kubectl --context ${OPS_GKE_1} get MeshPolicy -o yaml | grep "mtls: {}" | wc -l`
if [[ $NUM_MTLS_1 -eq 0 ]]
then 
    error_no_wait "oops, MTLS isn't enabled in ${OPS_GKE_1}. get some help, or give it another try."
    exit 1
else 
    title_no_wait "ops-1 cluster looks good! continuing..."
fi

NUM_MTLS_2=`kubectl --context ${OPS_GKE_2} get MeshPolicy -o yaml | grep "mtls: {}" | wc -l`
if [[ $NUM_MTLS_2 -eq 0 ]]
then 
    error_no_wait "oops, MTLS isn't enabled in ${OPS_GKE_2}. get some help, or give it another try."
    exit 1
else 
    title_no_wait "ops-2 cluster looks good! continuing..."
fi

title_and_wait "Describe the DestinationRule created by the Istio operator controller."
print_and_execute "kubectl --context ${OPS_GKE_1} get DestinationRule default -n istio-system -o yaml"
print_and_execute "kubectl --context ${OPS_GKE_2} get DestinationRule default -n istio-system -o yaml"
 
#validate
#Output (do not copy):
#
#  apiVersion: networking.istio.io/v1alpha3
#  kind: DestinationRule
#  metadata:  
#    name: default
#    namespace: istio-system
#  spec:
#    host: '*.local'
#    trafficPolicy:
#      tls:
#        mode: ISTIO_MUTUAL

# validate not-permissive state
NUM_ISTIO_MUTUAL_1=`kubectl --context ${OPS_GKE_1} get DestinationRule default -n istio-system -o yaml | grep "mode: ISTIO_MUTUAL" | wc -l`
if [[ $NUM_ISTIO_MUTUAL_1 -eq 0 ]]
then 
    error_no_wait "oops, ISTIO_MUTUAL isn't enabled in ${OPS_GKE_1}. get some help, or give it another try."
    exit 1
else 
    title_no_wait "ops-1 cluster looks good! continuing..."
fi

NUM_ISTIO_MUTUAL_2=`kubectl --context ${OPS_GKE_2} get DestinationRule default -n istio-system -o yaml | grep "mode: ISTIO_MUTUAL" | wc -l`
if [[ $NUM_ISTIO_MUTUAL_2 -eq 0 ]]
then 
    error_no_wait "oops, ISTIO_MUTUAL isn't enabled in ${OPS_GKE_2}. get some help, or give it another try."
    exit 1
else 
    title_no_wait "ops-2 cluster looks good! continuing..."
fi

# show some logs that prove secure
# log into envoy for frontend, curl product on port 8080? and output headers, grep for something.
# kubectl --context ${DEV2_GKE_2} exec -n payment $(kubectl get pod --context ${DEV2_GKE_2} -n payment | grep payment | awk '{print $1}') -c istio-proxy -- curl frontend.frontend:8080/
