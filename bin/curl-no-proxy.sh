#!/bin/bash

export http_proxy=
export https_proxy=
export no_proxy=

curl "$@"
