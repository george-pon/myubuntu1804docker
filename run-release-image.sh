#!/bin/bash
#
# test run image
#
function docker-run-myubuntu1804docker() {
    docker pull georgesan/myubuntu1804docker:latest
    ${WINPTY_CMD} docker run -i -t --rm \
        -e http_proxy=${http_proxy} -e https_proxy=${https_proxy} -e no_proxy="${no_proxy}" \
        georgesan/myubuntu1804docker:latest
}
docker-run-myubuntu1804docker
