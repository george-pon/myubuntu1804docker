#!/bin/bash

function f-docker-clean() {

    docker system prune -f
    docker volume prune -f

}

f-docker-clean

