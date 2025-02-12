#!/usr/bin/env bash

# Copyright 2021 Cloudera, Inc. All Rights Reserved.
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

set -e

IMAGE_NAME="ghcr.io/cloudera-labs/cldr-runner"
provider=${provider:-full}
IMAGE_VER=latest
IMAGE_TAG=${provider}-${IMAGE_VER}
IMAGE_FULL_NAME=${IMAGE_NAME}:${IMAGE_TAG}
CONTAINER_NAME=cloudera-deploy

# dir of script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )";
# parent dir of that dir
PARENT_DIRECTORY="${DIR%/*}"

PROJECT_DIR=${1:-${PARENT_DIRECTORY}}

echo "Checking if Docker is running..."
{ docker info >/dev/null 2>&1; echo "Docker OK"; } || { echo "Docker is required and does not seem to be running - please start Docker and retry" ; exit 1; }

docker pull ${IMAGE_NAME}:"${IMAGE_TAG}"

echo "Ensuring default credential paths are available in calling using profile for mounting to execution environment"
for thisdir in ".aws" ".ssh" ".cdp" ".azure" ".kube" ".config" ".config/cloudera-deploy/log" ".config/cloudera-deploy/profiles"
do
  mkdir -p "${HOME}"/$thisdir
done

echo "Ensure Default profile is present"
if [ ! -f "${HOME}"/.config/cloudera-deploy/profiles/default ]; then
  cp "${DIR}/profile.yml" "${HOME}"/.config/cloudera-deploy/profiles/default
fi

echo "Mounting ${PROJECT_DIR} to container and Project Directory /runner/project"

if [ ! "$(docker ps -q -f name=${CONTAINER_NAME})" ]; then
    if [ "$(docker ps -aq -f status=exited -f name=${CONTAINER_NAME})" ]; then
        # cleanup if exited
        echo "Attempting removal of exited execution container named '${CONTAINER_NAME}'"
        docker rm "${CONTAINER_NAME}" >/dev/null 2>&1 || echo "Execution container '${CONTAINER_NAME}' already removed, continuing..."
    fi
    # create new container if not running
    echo "Creating new execution container named '${CONTAINER_NAME}'"
    docker run -td \
      --detach-keys="ctrl-@" \
      -v "${PROJECT_DIR}":/runner/project \
      --mount type=bind,src=/run/host-services/ssh-auth.sock,target=/run/host-services/ssh-auth.sock \
      -e SSH_AUTH_SOCK="/run/host-services/ssh-auth.sock" \
      -e ANSIBLE_LOG_PATH="/home/runner/.config/cloudera-deploy/log/${CLDR_BUILD_VER:-latest}-$(date +%F_%H%M%S)" \
      -e ANSIBLE_INVENTORY="inventory" \
      -e ANSIBLE_CALLBACK_WHITELIST="ansible.posix.profile_tasks" \
      -e ANSIBLE_GATHERING="smart" \
      -e ANSIBLE_DEPRECATION_WARNINGS=false \
      -e ANSIBLE_HOST_KEY_CHECKING=false \
      -e ANSIBLE_SSH_RETRIES=10 \
      -e ANSIBLE_COLLECTIONS_PATH="/opt/cldr-runner/collections" \
      -e ANSIBLE_ROLES_PATH="/opt/cldr-runner/roles" \
      --mount "type=bind,source=${HOME}/.aws,target=/home/runner/.aws" \
      --mount "type=bind,source=${HOME}/.config,target=/home/runner/.config" \
      --mount "type=bind,source=${HOME}/.ssh,target=/home/runner/.ssh" \
      --mount "type=bind,source=${HOME}/.cdp,target=/home/runner/.cdp" \
      --mount "type=bind,source=${HOME}/.azure,target=/home/runner/.azure" \
      --mount "type=bind,source=${HOME}/.kube,target=/home/runner/.kube" \
      --network="host" \
      --name "${CONTAINER_NAME}" \
      "${IMAGE_FULL_NAME}" \
      /usr/bin/env bash

    echo "Installing the cloudera-deploy project to the execution container '${CONTAINER_NAME}'"
    docker exec -td "${CONTAINER_NAME}" /usr/bin/env git clone https://github.com/cloudera-labs/cloudera-deploy.git /opt/cloudera-deploy --depth 1
fi

cat <<SSH_HOST_KEY

  *** WARNING: SSH Host Key Checking is disabled by default. ***

  This setting may not be suitable for Production deployments. 
  If you wish to enable host key checking, please set the Ansible environment
  variable, ANSIBLE_HOST_KEY_CHECKING, to True before execution. See the project 
  documentation for further details on managing SSH host key checking.

SSH_HOST_KEY

echo 'Quickstart? Run this command -- ansible-playbook /opt/cloudera-deploy/main.yml -e "definition_path=examples/sandbox" -t run,default_cluster'
docker exec \
  --detach-keys="ctrl-@" \
  -it "${CONTAINER_NAME}" \
  /usr/bin/env bash