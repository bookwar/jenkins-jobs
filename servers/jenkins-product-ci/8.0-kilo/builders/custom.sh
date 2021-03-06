#!/bin/bash

set -ex

export PATH=/bin:/usr/bin:/sbin:/usr/sbin:${PATH}

PROD_VER=$(grep 'PRODUCT_VERSION:=' config.mk | cut -d= -f2)

export ISO_NAME="fuel-gerrit-${PROD_VER}-kilo-${BUILD_NUMBER}-${BUILD_ID}"
export UPGRADE_TARBALL_NAME="fuel-gerrit-${PROD_VER}-kilo-upgrade-${BUILD_NUMBER}-${BUILD_ID}"

export BUILD_DIR="${WORKSPACE}/../tmp/${JOB_NAME}/build"
export LOCAL_MIRROR="${WORKSPACE}/../tmp/${JOB_NAME}/local_mirror"

export ARTS_DIR="${WORKSPACE}/artifacts"
rm -rf "${ARTS_DIR}"

export DEPS_DIR="${BUILD_DIR}/deps"
rm -rf "${DEPS_DIR}"

# Checking gerrit commits for fuel-main
if [ "${FUELMAIN_COMMIT}" != "master" ] ; then
    git checkout "${FUELMAIN_COMMIT}"
fi

# Checking gerrit commits for fuel-main
if [ "${fuelmain_gerrit_commit}" != "none" ] ; then
  for commit in ${fuelmain_gerrit_commit} ; do
    git fetch https://review.openstack.org/openstack/fuel-main "${commit}" && git cherry-pick FETCH_HEAD || false
  done
fi

export NAILGUN_GERRIT_COMMIT="${nailgun_gerrit_commit}"
export ASTUTE_GERRIT_COMMIT="${astute_gerrit_commit}"
export FUELMENU_GERRIT_COMMIT="${fuelmenu_gerrit_commit}"
export SHOTGUN_GERRIT_COMMIT="${shotgun_gerrit_commit}"
export NETWORKCHECKER_GERRIT_COMMIT="${networkchecker_gerrit_commit}"
export FUELUPGRADE_GERRIT_COMMIT="${fuelupgrade_gerrit_commit}"
export OSTF_GERRIT_COMMIT="${ostf_gerrit_commit}"
export FUELLIB_GERRIT_COMMIT="${fuellib_gerrit_commit}"
export PYTHON_FUELCLIENT_GERRIT_COMMIT="${python_fuelclient_gerrit_commit}"
export FUEL_AGENT_GERRIT_COMMIT="${fuel_agent_gerrit_commit}"
export FUEL_NAILGUN_AGENT_GERRIT_COMMIT="${fuel_nailgun_agent_gerrit_commit}"

# Fix snapshot of a mirror which has been copied from 7.0 repositories

TARGET="snapshots/8.0-2015-09-02-000000"
export MIRROR_MOS_UBUNTU_ROOT="/mos-repos/ubuntu/${TARGET}"

echo "Using mirror: ${USE_MIRROR} with ${MIRROR_MOS_UBUNTU_ROOT}"

#########################################

echo "STEP 0. Clean before start"
make deep_clean

#########################################

echo "STEP 1. Make everything"
echo "ENV VARIABLES START"
printenv
echo "ENV VARIABLES END"

make $make_args iso version-yaml

#########################################

echo "STEP 2. Publish everything"

cd "${ARTS_DIR}"
for artifact in $(ls fuel-*)
do
  "${WORKSPACE}/utils/jenkins/process_artifacts.sh" "${artifact}"
done

cd "${WORKSPACE}"

echo FUELMAIN_GERRIT_COMMIT="${fuelmain_gerrit_commit}" > "${ARTS_DIR}/gerrit_commits.txt"
echo NAILGUN_GERRIT_COMMIT="${nailgun_gerrit_commit}" >> "${ARTS_DIR}/gerrit_commits.txt"
echo ASTUTE_GERRIT_COMMIT="${astute_gerrit_commit}" >> "${ARTS_DIR}/gerrit_commits.txt"
echo OSTF_GERRIT_COMMIT="${ostf_gerrit_commit}" >> "${ARTS_DIR}/gerrit_commits.txt"
echo FUELLIB_GERRIT_COMMIT="${fuellib_gerrit_commit}" >> "${ARTS_DIR}/gerrit_commits.txt"
echo PYTHON_FUELCLIENT_GERRIT_COMMIT="${python_fuelclient_gerrit_commit}" >> "${ARTS_DIR}/gerrit_commits.txt"
echo FUEL_AGENT_GERRIT_COMMIT="${fuel_agent_gerrit_commit}" >> "${ARTS_DIR}/gerrit_commits.txt"
echo FUEL_NAILGUN_AGENT_GERRIT_COMMIT="${fuel_nailgun_agent_gerrit_commit}" >> "${ARTS_DIR}/gerrit_commits.txt"
echo FUELMENU_GERRIT_COMMIT="${fuelmenu_gerrit_commit}" >> "${ARTS_DIR}/gerrit_commits.txt"
echo SHOTGUN_GERRIT_COMMIT="${shotgun_gerrit_commit}" >> "${ARTS_DIR}/gerrit_commits.txt"
echo NETWORKCHECKER_GERRIT_COMMIT="${networkchecker_gerrit_commit}" >> "${ARTS_DIR}/gerrit_commits.txt"
echo FUELUPGRADE_GERRIT_COMMIT="${fuelupgrade_gerrit_commit}" >> "${ARTS_DIR}/gerrit_commits.txt"

cp "${LOCAL_MIRROR}"/*changelog "${ARTS_DIR}/" || true
cp "${BUILD_DIR}/iso/isoroot/version.yaml" "${ARTS_DIR}/version.yaml.txt" || true
(cd "${BUILD_DIR}/iso/isoroot" && find . | sed -s 's/\.\///') > "${ARTS_DIR}/listing.txt" || true

grep MAGNET_LINK "${ARTS_DIR}"/*iso.data.txt > "${ARTS_DIR}/magnet_link.txt"

# Generate build description
ISO_MAGNET_LINK=$(grep MAGNET_LINK "${ARTS_DIR}"/*iso.data.txt | sed 's/MAGNET_LINK=//')
ISO_HTTP_LINK=$(grep HTTP_LINK "${ARTS_DIR}"/*iso.data.txt | sed 's/HTTP_LINK=//')
ISO_HTTP_TORRENT=$(grep HTTP_TORRENT "${ARTS_DIR}"/*iso.data.txt | sed 's/HTTP_TORRENT=//')

echo "<a href=${ISO_HTTP_LINK}>ISO download link</a> <a href=${ISO_HTTP_TORRENT}>ISO torrent link</a><br>${ISO_MAGNET_LINK}<br>"

#########################################

echo "STEP 3. Clean after build"
make deep_clean

#########################################
