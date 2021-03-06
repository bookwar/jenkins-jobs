#!/bin/bash

set -ex

export FEATURE_GROUPS="experimental"
export FUELMENU_GERRIT_COMMIT="refs/changes/36/289536/1"

PROD_VER=$(grep 'PRODUCT_VERSION:=' config.mk | cut -d= -f2)
export ISO_NAME="fuel-community-${PROD_VER}-${BUILD_NUMBER}-${BUILD_TIMESTAMP}"

export BUILD_DIR="${WORKSPACE}/../tmp/${JOB_NAME}/build"
export LOCAL_MIRROR="${WORKSPACE}/../tmp/${JOB_NAME}/local_mirror"

export ARTS_DIR="${WORKSPACE}/artifacts"
rm -rf "${ARTS_DIR}"

#########################################

test "$deep_clean" = "true" && make deep_clean

rm -rf /var/tmp/yum-${USER}-*

#########################################

echo "Check version.yaml for Fuel commit ids (if present)"

if [ -n "${FUEL_COMMITS}" ] && [ -f "/home/jenkins/workspace/fuel_commits/${FUEL_COMMITS}" ]; then
  export FUEL_COMMITS="/home/jenkins/workspace/fuel_commits/${FUEL_COMMITS}"
  export ASTUTE_COMMIT=$(fgrep astute_sha "${FUEL_COMMITS}"|cut -d\" -f2)
  export FUELLIB_COMMIT=$(fgrep fuel-library_sha "${FUEL_COMMITS}"|cut -d\" -f2)
  export FUELMAIN_COMMIT=$(fgrep fuelmain_sha "${FUEL_COMMITS}"|cut -d\" -f2)
  export NAILGUN_COMMIT=$(fgrep nailgun_sha "${FUEL_COMMITS}"|cut -d\" -f2)
  export OSTF_COMMIT=$(fgrep ostf_sha "${FUEL_COMMITS}"|cut -d\" -f2)
  export PYTHON_FUELCLIENT_COMMIT=$(fgrep python-fuelclient_sha "${FUEL_COMMITS}"|cut -d\" -f2)
fi

######## Get stable ubuntu mirror from snapshot ###############
# Since we are building community.iso in EU dc let' hardcode this
LATEST_MIRROR_ID_URL=http://mirror.seed-cz1.fuel-infra.org
LATEST_TARGET=$(curl -sSf "${LATEST_MIRROR_ID_URL}/mos-repos/ubuntu/8.0.target.txt" | sed '1p; d')
export MIRROR_MOS_UBUNTU_ROOT="/mos-repos/ubuntu/${LATEST_TARGET}"

echo "Using mirror: ${USE_MIRROR} with ${MIRROR_MOS_UBUNTU_ROOT}"

echo "Checkout fuel-main"

if [ -n "${FUELMAIN_COMMIT}" ] ; then
    git checkout "${FUELMAIN_COMMIT}"
fi

#########################################
echo "STEP 0. Export Workarounds"
export MIRROR_FUEL=http://mirror.seed-cz1.fuel-infra.org/mos-repos/centos/mos8.0-centos7-fuel/os/x86_64/
export MIRROR_MOS_UBUNTU=mirror.seed-cz1.fuel-infra.org
export MIRROR_UBUNTU=mirror.seed-cz1.fuel-infra.org
export USE_MIRROR=ext

echo "STEP 1. Make everything"

make iso

echo "STEP 2. Publish everything"

cd "${WORKSPACE}"

cp "${LOCAL_MIRROR}/*changelog ${ARTS_DIR}/" || true
(cd "${BUILD_DIR}/iso/isoroot" && find . | sed -s 's/\.\///') > "${WORKSPACE}/listing.txt" || true

echo "BUILD FINISHED."

# cleanup after the job
# we can cleanup freely since make deep_clean doesn't wipe out ARTS_DIR
cd "${WORKSPACE}"
make deep_clean
