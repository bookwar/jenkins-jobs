#!/bin/bash
#
#   :mod:`deploy-ci` -- Deployment CI script
#   ==========================================
#
#   .. module:: deploy-ci
#       :platform: Unix
#       :synopsis: This builds complete environment using all available roles to test it.
#   .. vesionadded:: MOS-9.0
#   .. vesionchanged:: MOS-9.0
#   .. author:: Pawel Brzozowski <pbrzozowski@mirantis.com>
#
#
#   This module does everything which is required to test all available roles
#   It contains:
#       * tenant cleaner
#       * tenant setup
#       * preparation of base VMs (Puppet Master, Name server)
#       * role iterator
#
#
#   .. envvar::
#       :var  BUILD_ID: Id of Jenkins build under which this
#                       script is running, defaults to ``0``
#       :type BUILD_ID: int
#       :var  WORKSPACE: Location where build is started, defaults to ``.``
#       :type WORKSPACE: path
#
#   .. requirements::
#
#       * ci-lab
#       * git
#       * sed
#
#
#   .. entrypoint:: main
#
#
#   .. affects::
#       :directory ci-lab: directory to checkout ci-lab code
#       :directory ci-lab-tmp: temporary directory with python environment
#
#
#   .. seealso:: https://mirantis.jira.com/browse/PROD-1017
#   .. warnings:: can't be run multiple times per once

set -ex

BUILD_ID="${BUILD_ID:-0}"
WORKSPACE="${WORKSPACE:-.}"
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

main () {
    #   .. function:: main
    #
    #       Main function to handle VM creation and testing
    #
    #       :stdin: not used
    #       :stdout: useless debug information
    #       :stderr: not used
    #
    #   .. note:: https://mirantis.jira.com/browse/PROD-1017
    #

    # define base directory with prefix
    BASE_DIR="${WORKSPACE}/${PREFIX}"

    echo "FORCE=1" \
    "BASE_DIR=${BASE_DIR}" \
    "TMP_DIR=${BASE_DIR}/virtualenv" \
    "GERRIT_REFSPEC=\"${GERRIT_REFSPEC}\"" \
    "DNS1=${DNS1}" \
    "DNS2=${DNS2}" \
    "OS_FLAVOR_NAME=${OS_FLAVOR_NAME}" \
    "OS_IMAGE_NAME=${OS_IMAGE_NAME}" \
    "OS_OPENRC_PATH=${OS_OPENRC_PATH}" \
    "GLOBAL_PREFIX=${PREFIX}" > "${BASE_DIR}/config_local"

    # prepare environment and delete all VMs
    cd "${BASE_DIR}"
    ./tools/prepare_env.sh
    ./tools/openstack_clean_all_vms.sh

    # re-initialize openstack environment
    if [[ "${INITIALIZE}" == 'true' ]]; then
        cd "${BASE_DIR}"
        # remove configuration if available
        ./tools/openstack_clean_config.sh || true
        # apply new configuration
        ./tools/openstack_prepare.sh
    fi

    # prepare hiera data
    cd "${BASE_DIR}/hiera"
    ./gen_ssl review.test.local
    ./gen_ssh gerrit_root
    ./gen_ssh gerrit_ssh_rsa
    ./gen_ssh gerrit_ssh_dsa dsa
    ./gen_ssh jenkins_master_rsa
    ./gen_ssh jenkins_publisher_rsa
    ./gen_ssh zuul_rsa
    ./gen_ssh jenkins_slave_osci_rsa
    ./gen_ssh jenkins_slave_rsa
    ./gen_ssl test-ci.test.local
    ./gen_gpg perestroika_gpg

    # prepare base VMs
    cd "${BASE_DIR}"
    ./lab-vm create ns1
    ./lab-vm create puppet-master

    # check each role
    # WORKAROUND (second pass Puppet run) https://bugs.launchpad.net/bugs/1578766
    cd "${BASE_DIR}"

    # get blacklist
    ./lab-vm exec puppet-master cat /etc/puppet/blacklist.txt | \
      grep -v '^$\|^\s*\#' > "${BASE_DIR}/blacklist.txt"

    # generate nodes and covered roles list
    ./lab-vm exec puppet-master ls -1 /var/lib/hiera/nodes/ 2>/dev/null | \
      sed 's/.test.local.yaml//g' | sed 's/-/_/g' | \
      tee "${BASE_DIR}/selected.txt" | sed 's/[0-9]*//g' | sort -u \
      > "${BASE_DIR}/covered.txt"

    # generate roles (without roles already covered by nodes list)
    ./lab-vm exec puppet-master ls -1 /var/lib/hiera/roles/ 2>/dev/null | \
      sed 's/.yaml//g' | grep -v -w -f "${BASE_DIR}/covered.txt" \
      >> "${BASE_DIR}/selected.txt"

    # generate a file with role to image name mapping
    ./lab-vm exec puppet-master "grep -RPo '^#.*(?<=image:)[^\s]+' \
      /var/lib/hiera/roles" | awk -F '/|image:|.yaml:#' '{print $6, $8}' \
      > "${BASE_DIR}/mapping.txt"

    # iterate all the filtered roles
    grep -v -w -f "${BASE_DIR}/blacklist.txt" "${BASE_DIR}/selected.txt" | \
      egrep "${INCLUDE}" | egrep -v -w "${EXCLUDE}" | sed 's/_/-/g' | \
      xargs -n1 -P"${PARALLELISM}" -I '%' bash -c "
        # generate role name
        ROLE=\$(echo % | sed 's/-/_/g' | sed 's/[0-9]*//g')
        # check if image name set in mapping file
        IMAGE=\$(awk -v role=\${ROLE} '{if (\$1 == role) { print \$2 }}' \
          ${BASE_DIR}/mapping.txt)
        # create new VM and perform first puppet run
        ./lab-vm create % \${IMAGE} 2>&1 | (sed 's/^/%: /') | \
          tee -a ${BASE_DIR}/first_run.txt
        # stop tests when got exit code of 1, 4 or 6 on second puppet run
        ./lab-vm exec % puppet agent --detailed-exitcodes --test 2>&1 | \
          (sed 's/^/%: /') | tee -a ${BASE_DIR}/second_run.txt
        # save exit code
        STATUS=\${PIPESTATUS}
        # remove VM as it's no longer required
        if [[ ${KEEP} != 'true' ]]; then
          ./lab-vm remove %
        fi
        # check if status code is 1, 4 or 6
        if [[ '146' =~ \${STATUS} ]]; then
            printf '${RED}Failure at %: second run deployment failed!${NC}\n' | \
              tee -a ${BASE_DIR}/summary.txt
        else
            printf '${GREEN}Success at %: second run deployment success!${NC}\n' | \
              tee -a ${BASE_DIR}/summary.txt
        fi
      "

    # disable script trace from here to form clear output
    set +x

    # prepare and display deployment summary
    printf '\n\n========== FIRST RUN ERRORS =========\n\n'
    grep 'Error:' "${BASE_DIR}/first_run.txt" | egrep -v "${IGNORED}" | \
      sort -s -k 1,1

    printf '\n\n========== SECOND RUN ERRORS =========\n\n'
    grep 'Error:' "${BASE_DIR}/second_run.txt" | egrep -v "${IGNORED}" | \
      sort -s -k 1,1

    printf '\n\n========== SUMMARY =========\n\n'
    sort "${BASE_DIR}/summary.txt" -s -k 1,1

    # delete the rest of VMs
    if [[ "${KEEP}" != 'true' ]]; then
      ./tools/openstack_clean_all_vms.sh
    fi

    # return exit code '1' if failure was registered
    if grep -q 'Failure' "${BASE_DIR}/summary.txt"; then
        exit 1
    else
        exit 0
    fi
}

if [ "$0" == "${BASH_SOURCE}" ] ; then
    main "${@}"
fi
