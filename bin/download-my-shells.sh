#!/bin/bash
#
# オレの作業シェルをダウンロードする
#
mkdir -p /usr/local/bin
pushd /usr/local/bin
for i in kube-run-v.sh  kube-all.sh  docker-clean.sh  kube-helm-client-init.sh  kube-helm-tools-setup.sh  docker-run-ctop.sh  curl-no-proxy.sh
do
    curl -fLO https://gitlab.com/george-pon/my-helm-chart/raw/master/bin/$i
    chmod +x $i
done
popd
