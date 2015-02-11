#!/bin/bash

set -ex

VENV="${WORKSPACE}_VENV"
virtualenv -p python2.6 "${VENV}"
source ${VENV}/bin/activate

export TEST_NAILGUN_DB="nailgun"

cd ${WORKSPACE}

pushd nailgun > /dev/null

wget https://fuel-jenkins.mirantis.com/job/nailgun_performance_tests/lastCompletedBuild/artifact/nailgun/nailgun_perf_test_report.csv

pushd nailgun > /dev/null

# modify paths since by default /tmp/ is used
sed -i 's#load_tests_base:.*#load_tests_base: "'${WORKSPACE}'/results/tests/"#' settings.yaml
sed -i 's#last_performance_test:.*#last_performance_test: "'${WORKSPACE}'/results/last/"#' settings.yaml
sed -i 's#load_tests_results:.*#load_tests_results: "'${WORKSPACE}'/results/results/"#' settings.yaml
sed -i 's#last_performance_test_run:.*#last_performance_test_run: "'${WORKSPACE}'/results/last/run/"#' settings.yaml
sed -i 's#load_previous_tests_results:.*#load_previous_tests_results: "'${WORKSPACE}'/results/previous_results.json"#' settings.yaml

popd
popd
mkdir -p ${WORKSPACE}/results
./run_tests.sh -x
