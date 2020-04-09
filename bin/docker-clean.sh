#!/bin/bash

function f-docker-clean() {
    docker container prune -f
    docker system prune -f
    docker volume prune -f
}

f-docker-clean

