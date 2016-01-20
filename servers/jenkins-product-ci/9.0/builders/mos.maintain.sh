#!/bin/bash

set -o xtrace
set -o errexit

main () {
    local WRKDIR=$(pwd)/perestroika
    [ -d "${WRKDIR}/docker-builder" ] && local _dpath="${WRKDIR}/docker-builder" || exit 1

    # Aborted containers cleanup
    docker ps -a | grep -F -e "Exited" -e "Dead" | cut -d ' ' -f 1 | xargs -I% docker rm %

    # Unpublished packages cleanup
    rm -rf "${HOME}"/built_packages/

    # Create images
    local _images="$(docker images | grep -F -e "build" | cut -d ' ' -f 1)"
    for image in mockbuild sbuild ; do
        [ $(echo "${_images}" | grep -Fc -e "${image}") -eq 0 ] && docker build -t "${image}" "${_dpath}/${image}/"
    done

    # Create or update chroots
    local _rpmchroots="$(ls -1 /var/cache/docker-builder/mock/cache/)"
    for target in 7 ; do
        if [ $(echo "${_rpmchroots}" | grep -Fc -e "-${target}-") -eq 0 ] ; then
            env "DIST=${target}" bash "${_dpath}/create-rpm-chroot.sh"
        else
            env "DIST=${target}" bash "${_dpath}/update-rpm-chroot.sh"
        fi
    done

    local _debchroots="$(ls -1 /var/cache/docker-builder/sbuild/)"
    for target in trusty ; do
        if [ $(echo "${_debchroots}" | grep -Fc -e "${target}") -eq 0 ] ; then
            env "DIST=${target}" bash "${_dpath}/create-deb-chroot.sh"
        else
            env "DIST=${target}" bash "${_dpath}/update-deb-chroot.sh"
        fi
    done
}

main "${@}"

# clean old mirrors
# path to the custom mirrors on node
PATH_TO_CUSTOM_MIRROR=/var/www/custom_mirrors/custom_9.0_packages
# for how many days keep the custom mirror
DAYS_TO_KEEP=7
echo "Cleaning old mirrors"
/usr/bin/find "${PATH_TO_CUSTOM_MIRROR}" -maxdepth 1 -mtime +"${DAYS_TO_KEEP}" -regextype posix-extended -regex '.*[[:digit:]]' -exec rm -rf {} \;

exit 0
