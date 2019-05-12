#!/bin/bash
#
#  色々なツールを helm でガンガンインストールしていく
#
#
# http://master.default.svc.k8s.local/
# http://kubernetes-dashboard.minikube.local/
# http://grafana.minikube.local/                admin  prom-operator
# http://kjwikigdocker.minikube.local/kjwikigdocker/
# http://growi.minikube.local/
#

#
# download kube-run-v.sh
#
function f-download-kube-run-v-sh() {
    pushd /usr/local/bin
    curl -LO https://raw.githubusercontent.com/george-pon/mycentos7docker/master/bin/kube-run-v.sh
    chmod +x kube-run-v.sh
    curl -LO https://raw.githubusercontent.com/george-pon/mycentos7docker/master/bin/kube-all.sh
    chmod +x kube-all.sh
    curl -LO https://raw.githubusercontent.com/george-pon/mycentos7docker/master/bin/kube-helm-client-init.sh
    chmod +x kube-helm-client-init.sh
    curl -LO https://raw.githubusercontent.com/george-pon/mycentos7docker/master/bin/docker-run-ctop.sh
    chmod +x docker-run-ctop.sh
    curl -LO https://raw.githubusercontent.com/george-pon/mycentos7docker/master/bin/docker-clean.sh
    chmod +x docker-clean.sh
    curl -LO https://raw.githubusercontent.com/george-pon/mycentos7docker/master/bin/kube-helm-tools-setup.sh
    chmod +x docker-clean.sh
    popd
}


# PATHに追加する。
# 既にある場合は何もしない。
function f-path-add() {
    local addpath=$1
    if [ -z "$addpath" ]; then
        echo "f-path-add  path"
        return 0
    fi
    if [ ! -d "$addpath" ]; then
        echo "not a directory : $addpath"
        return 1
    fi
    local result=$( echo "$PATH" | sed -e 's/:/\n/g' | awk -v va=$addpath '{ if ( $0 == va ) { print $0 } }' )
    if [ -z "$result" ]; then
        export PATH="$PATH:$addpath"
        echo "PATH add $addpath"
    fi
}

f-path-add  /usr/local/bin




#
# ingress
#
function f-helm-ingress() {
curl -LO https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/mandatory.yaml
curl -LO https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/provider/cloud-generic.yaml
curl -LO https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/provider/baremetal/service-nodeport.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/mandatory.yaml
# kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/provider/cloud-generic.yaml
# kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/provider/baremetal/service-nodeport.yaml

# nodeport版だとポート番号30000になってしまうな。80とか443が使えない。
if false; then
cat > service-nodeport-my.yaml << "EOF"
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
  labels:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/part-of: ingress-nginx
spec:
  type: NodePort
  ports:
    - name: http
      port: 80
      targetPort: 80
      nodePort: 30000
      protocol: TCP
    - name: https
      port: 443
      targetPort: 443
      nodePort: 30443
      protocol: TCP
  selector:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/part-of: ingress-nginx
EOF
kubectl apply -f service-nodeport-my.yaml
# kubectl delete -f service-nodeport-my.yaml
fi

#
# type loadbalancer, externalIPsを使うのが良い模様。nodeが複数ある場合はexternalIPsを複数指定しておく
# externalTrafficPolicy: Localの場合、着信したnodeの内部にあるpodにしか転送しない変なingressになる。
# 1 node = 1 ingressで、通信相手が daemonset なら externalTrafficPolicy: Local でも良いけど
# https://thinkit.co.jp/article/13738?page=0%2C1 KubernetesのDiscovery＆LBリソース（その1） | Think IT（シンクイット）
# また、master node は通常 worker pod は起動できないので、node1, node2 の IPアドレスを書くのが良い
#
cat > cloud-generic-my.yaml << "EOF"
kind: Service
apiVersion: v1
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
  labels:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/part-of: ingress-nginx
spec:
  externalTrafficPolicy: Cluster
  type: LoadBalancer
  externalIPs:
    - 192.168.33.11
  selector:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/part-of: ingress-nginx
  ports:
    - name: http
      port: 80
      targetPort: http
    - name: https
      port: 443
      targetPort: https
EOF
kubectl apply -f cloud-generic-my.yaml
# kubectl delete -f cloud-generic-my.yaml
}




#
#  helm client 初期化
#
/usr/local/bin/kube-helm-client-init.sh





function f-helm-heapster() {
if true; then
#
#  heapster
#  heapster-0.3.2
#
# --namespace kube-system にしないといけない
#
#  認証なしで接続できる kubelet port 10255 がkube 1.13系で廃止されたので、heapster対応待ち。 2019.03.24
#  今後はサービスアカウントを使うようにして、認証ありでkubelet port 10250に接続して情報を取得するようになる
#  amazon 向け kubernetes では、readonly port 10255は廃止されているので、kubectl top nodeは heapsterが対応するまで利用できない
#  https://github.com/awslabs/amazon-eks-ami/issues/128
#

# アクセス用のロールを作成
cat > heapster-role.yaml << "EOF"
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: node-stats-full
rules:
- apiGroups: [""]
  resources: ["nodes/stats"]
  verbs: ["get", "watch", "list", "create"]
EOF
kubectl apply -f heapster-role.yaml

# kubeletアクセス用のアカウントを作成。heapster-heapsterという名前になってしまうのでその名前で作る
cat > heapster-account.yaml << "EOF"
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: heapster-node-stats
subjects:
- kind: ServiceAccount
  name: heapster-heapster
  namespace: kube-system
roleRef:
  kind: ClusterRole
  name: node-stats-full
  apiGroup: rbac.authorization.k8s.io
EOF
kubectl apply -f heapster-account.yaml

# heapsterのインストール
helm inspect stable/heapster
helm fetch   stable/heapster
helm install stable/heapster \
    --name heapster \
    --namespace kube-system  \
    --values - << "EOF"
command:
- /heapster
- --source=kubernetes:kubernetes:https://kubernetes.default?useServiceAccount=true&kubeletHttps=true&kubeletPort=10250&insecure=true
rbac:
  create: true
  serviceAccountName: heapster
service:
  annotations:
    prometheus.io/path: /metrics
    prometheus.io/port: "8082"
    prometheus.io/scrape: "true"
EOF
helm upgrade heapster stable/heapster \
    --values - << "EOF"
command:
- /heapster
- --source=kubernetes:kubernetes:https://kubernetes.default?useServiceAccount=true&kubeletHttps=true&kubeletPort=10250&insecure=true
rbac:
  create: true
  serviceAccountName: heapster
service:
  annotations:
    prometheus.io/path: /metrics
    prometheus.io/port: "8082"
    prometheus.io/scrape: "true"
EOF

# 情報が集まるまで60秒以上待機する
kubectl top node
kubectl top pod --all-namespaces
fi
}



#
#  nginx sample
#
function f-nginx-sample() {
# ベースとなるdocker-composeファイルを用意
export NGINX_NAME=sample-nginx
helm delete --purge $NGINX_NAME
cat > ${NGINX_NAME}.yml << EOF
#
# docker-compose file for ${NGINX_NAME}
#
version: '3'
services:
  ${NGINX_NAME}:
    image: "nginx:latest"
    ports:
     - "80:80"
EOF
kompose convert --chart --controller deployment --file ${NGINX_NAME}.yml
helm install $NGINX_NAME --name $NGINX_NAME
kubectl rollout status deploy/$NGINX_NAME
}



#
# kjwikigdocker
#
function f-helm-kjwikigdocker() {
if true; then
    helm repo add kjwikigdockerrepo  https://raw.githubusercontent.com/george-pon/kjwikigdocker/master/helm-chart/charts
    helm repo update
    helm search kjwikigdocker
    helm inspect kjwikigdockerrepo/kjwikigdocker
    helm delete --purge kjwikigdocker
    sleep 5
    helm install kjwikigdockerrepo/kjwikigdocker \
        --name kjwikigdocker \
        --set ingress.hosts="{kjwikigdocker.minikube.local}"
    kubectl rollout status deploy/kjwikigdocker
fi
}



#
# growi
#  あれ？なぜか動かなくなった？？
#
function f-helm-growi() {
if true; then
    helm repo add  growirepo  https://raw.githubusercontent.com/george-pon/growi-helm-chart/master/helm-chart/charts
    helm repo update
    helm search growi
    helm inspect growirepo/growi
    helm delete growi --purge
    sleep 15
helm install growirepo/growi \
    --name growi  \
    --values - << "EOF"
    settings:
      appsiteurl: http://growi.minikube.local
    ingress:
      enabled: true
      hosts:
        - growi.minikube.local
      paths:
        - /
EOF
    kubectl rollout status deploy/growi
fi
}



#
#  kubernetes dashboard
#  kubernetes-dashboard-1.2.2
#
# helm inspect stable/kubernetes-dashboard
#
function f-helm-kubernetes-dashboard() {
helm install stable/kubernetes-dashboard \
    --name kubernetes-dashboard \
    --namespace kube-system \
    --values - << "EOF"
enableSkipLogin: true
enableInsecureLogin: true
rbac:
  clusterAdminRole: true
ingress:
  enabled: true
  hosts:
  - kubernetes-dashboard.minikube.local
EOF
kubectl --namespace kube-system rollout status deploy/kubernetes-dashboard
}



#
#  prometheus
#
function f-helm-prometheus() {
if false ; then
    helm inspect stable/prometheus
    helm fetch   stable/prometheus
helm install stable/prometheus \
    --name prometheus \
    --values - << "EOF"
server:
  ingress:
    enabled: true
    hosts:
    - promethus.minikube.local
EOF
fi
}


#
#  prometheus-operator
#
function f-helm-prometheus-operator() {
if false ; then
#
#  prometheus-operator
#  prometheus-operator-5.0.2
#  prometheus-operatorがあれば、prometheus不要かもしれない
#  prometheusがインストール済みだと "prometheusrules.monitoring.coreos.com" が重複してインストールできない
#  prometheus-operatorを一回インストールしてしまうと、helm delete しても "prometheusrules.monitoring.coreos.com" が重複してインストールできない
# 
# これインストールすると load average が 28とかになる；；なんだこれ；；
#
#    --set kubelet.serviceMonitor.https=false \
#    --set kubeControllerManager.enabled=false \
#    --set kubeScheduler.enabled=false \
#    --set defaultRules.rules.kubernetesSystem=false \
#
#  aksでkubeletのreadOnlyPort 10255が封鎖された。kubeletの認証付き 10250にアクセスして情報を取得する必要がある。
#    --set kubelet.serviceMonitor.https=true にする必要がある。
#  https://github.com/awslabs/amazon-eks-ami/issues/128
#
# prometheus-operator-5.0.3
# app version 0.29.0
# Error: object is being deleted: customresourcedefinitions.apiextensions.k8s.io "prometheuses.monitoring.coreos.com" already exists
#
helm inspect stable/prometheus-operator
helm fetch   stable/prometheus-operator
helm install stable/prometheus-operator \
    --name prometheus-operator \
    --namespace kube-system \
    --values - << "EOF"
prometheusOperator:
  crdApiGroup: "myprometheus.monitoring.coreos.com"
kubelet:
  serviceMonitor:
    https: true
kubeControllerManager:
  enabled: false
kubeScheduler:
  enabled: false
defaultRules:
  rules:
    kubernetesSystem: false
grafana:
  enabled: true
  ingress:
    enabled: true
    hosts:
    - grafana.minikube.local
EOF
fi


if false ; then
helm upgrade  prometheus-operator stable/prometheus-operator \
    --values - << "EOF"
kubelet:
  serviceMonitor:
    https: true
kubeControllerManager:
  enabled: false
kubeScheduler:
  enabled: false
defaultRules:
  rules:
    kubernetesSystem: false
grafana:
  enabled: true
  ingress:
    enabled: true
    hosts:
    - grafana.minikube.local
EOF
fi

}




