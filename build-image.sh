#!/bin/bash

function car() {
    echo $1
}

function cdr() {
    shift
    echo "$@"
}

function f_docker_build() {
    TAG_LIST=$(awk '/^ENV MYUBUNTU1804DOCKER_VERSION/ {print $3;}' Dockerfile)
    TAG_LIST="$TAG_LIST monthly$(date +%Y%m) "
    TAG_CAR=$(car $TAG_LIST)
    TAG_CDR=$(cdr $TAG_LIST)
    echo $TAG_CDR
    IMAGE_NAME=${PREFIX}$(awk '/^ENV MYUBUNTU1804DOCKER_IMAGE/ {print $3;}' Dockerfile)

    if [ ! -z "$HTTP_PROXY" ]; then
        BUILD_OPT="$BUILD_OPT  --build-arg HTTP_PROXY=$HTTP_PROXY"
    fi
    if [ ! -z "$HTTPS_PROXY" ]; then
        BUILD_OPT="$BUILD_OPT  --build-arg HTTPS_PROXY=$HTTPS_PROXY"
    fi
    if [ ! -z "$http_proxy" ]; then
        BUILD_OPT="$BUILD_OPT  --build-arg http_proxy=$http_proxy"
    fi
    if [ ! -z "$https_proxy" ]; then
        BUILD_OPT="$BUILD_OPT  --build-arg https_proxy=$https_proxy"
    fi
    if [ ! -z "$NO_PROXY" ]; then
        BUILD_OPT="$BUILD_OPT  --build-arg NO_PROXY=$NO_PROXY"
    fi
    if [ ! -z "$no_proxy" ]; then
        BUILD_OPT="$BUILD_OPT  --build-arg no_proxy=$no_proxy"
    fi

    if [ ! -z "$no_cache" ]; then
        BUILD_OPT="$BUILD_OPT  --no-cache=$no_cache"
    fi

    echo docker build -t ${IMAGE_NAME}:${TAG_CAR} .
    $SUDO_DOCKER docker build $BUILD_OPT -t ${IMAGE_NAME}:${TAG_CAR} .
    RC=$?
    if [ $RC -ne 0 ]; then
        echo "ERROR: docker build failed."
        return 1
    fi

    for i in $TAG_CDR
    do
        echo docker tag ${IMAGE_NAME}:$TAG_CAR ${IMAGE_NAME}:$i
        $SUDO_DOCKER docker tag ${IMAGE_NAME}:$TAG_CAR ${IMAGE_NAME}:$i
    done

    return 0
}

f_docker_build
