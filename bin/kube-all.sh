#!/bin/bash
#
#  --all-namespaces を打つのが大変なので
#

#
# 全namespaceで何か操作する
#
function f-kube-all() {
    if [ $# -eq 0 ]; then
        echo "ex:f-kube-all get pod"
        return 0
    fi
    echo kubectl "$@" --all-namespaces -o wide
    kubectl "$@" --all-namespaces -o wide
}

# if source this file, define function only ( not run )
# echo "BASH_SOURCE count is ${#BASH_SOURCE[@]}"
# echo "BASH_SOURCE is ${BASH_SOURCE[@]}"
if [ ${#BASH_SOURCE[@]} = 1 ]; then
    f-kube-all "$@"
    RC=$?
    exit $RC
else
    echo "source from $0. define function only. not run." > /dev/null
fi

#
# end of file
#
