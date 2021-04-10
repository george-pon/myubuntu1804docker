#!/bin/bash
#
#  kube get all で表示されない Secret / ConfigMap / Ingress なども全部表示する
#

#
# 全namespaceで何か操作する
#
function f-kube-get-maji-all() {
    kubectl get $(kubectl api-resources --namespaced=true --verbs=list -o name | tr '\n' ',' | sed -e 's%,$%%g')
}

# if source this file, define function only ( not run )
# echo "BASH_SOURCE count is ${#BASH_SOURCE[@]}"
# echo "BASH_SOURCE is ${BASH_SOURCE[@]}"
if [ ${#BASH_SOURCE[@]} = 1 ]; then
    f-kube-get-maji-all "$@"
    RC=$?
    exit $RC
else
    echo "source from $0. define function only. not run." > /dev/null
fi

#
# end of file
#
