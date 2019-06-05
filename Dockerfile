FROM ubuntu:18.04

ENV MYUBUNTU1804DOCKER_VERSION build-target
ENV MYUBUNTU1804DOCKER_VERSION latest
ENV MYUBUNTU1804DOCKER_VERSION stable
ENV MYUBUNTU1804DOCKER_IMAGE myubuntu1804docker

# set locale
RUN apt-get update && \
    apt-get install -y locales  apt-transport-https  ca-certificates  language-pack-ja  software-properties-common && \
    localedef -i ja_JP -c -f UTF-8 -A /usr/share/locale/locale.alias ja_JP.UTF-8 && \
    apt-get clean
ENV LANG ja_JP.utf8

# set timezone
RUN ln -fs /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
ENV TZ Asia/Tokyo

# Do not exclude man pages & other documentation
RUN rm /etc/dpkg/dpkg.cfg.d/excludes

# re-install packages with manual
RUN dpkg -l | grep ^ii | cut -d' ' -f3 | xargs apt-get install -y --reinstall
RUN apt-get install -y man-db  manpages && apt-get clean

# install etc utils
RUN apt-get update && apt-get install -y --fix-missing \
        ansible \
        bash-completion \
        connect-proxy \
        curl \
        dnsutils \
        expect \
        gettext \
        git \
        gnupg2 \
        iproute2 \
        jq \
        lsof \
        make \
        mongodb-clients \
        netcat \
        net-tools \
        postgresql-client \
        rsync \
        sudo \
        tcpdump \
        traceroute \
        tree \
        unzip \
        vim \
        wget \
        zip \
    && apt-get clean all

# install docker client
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - && \
    add-apt-repository  "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" && \
    apt-get update && \
    apt-get install -y docker-ce-cli containerd.io && \
    apt-get clean all

# install docker-compose
RUN apt-get install -y docker-compose && apt-get clean

# install kubectl CLI
RUN curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - && \
    echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" >/etc/apt/sources.list.d/kubernetes.list && \
    apt-get update && \
    apt-get install -y kubectl && apt-get clean
# RUN apt-mark hold kubectl

# install helm CLI v2.9.1
ENV HELM_CLIENT_VERSION v2.9.1
RUN curl -fLO https://storage.googleapis.com/kubernetes-helm/helm-${HELM_CLIENT_VERSION}-linux-amd64.tar.gz && \
    tar xzf  helm-${HELM_CLIENT_VERSION}-linux-amd64.tar.gz && \
    /bin/cp  linux-amd64/helm   /usr/bin && \
    /bin/rm -rf rm helm-${HELM_CLIENT_VERSION}-linux-amd64.tar.gz linux-amd64

# install kompose v1.18.0
ENV KOMPOSE_VERSION v1.18.0
RUN curl -fLO https://github.com/kubernetes/kompose/releases/download/${KOMPOSE_VERSION}/kompose-linux-amd64.tar.gz && \
    tar xzf kompose-linux-amd64.tar.gz && \
    chmod +x kompose-linux-amd64 && \
    mv kompose-linux-amd64 /usr/bin/kompose && \
    rm kompose-linux-amd64.tar.gz

# install stern
ENV STERN_VERSION 1.10.0
RUN curl -fLO https://github.com/wercker/stern/releases/download/${STERN_VERSION}/stern_linux_amd64 && \
    chmod +x stern_linux_amd64 && \
    mv stern_linux_amd64 /usr/bin/stern

# install kustomize
ENV KUSTOMIZE_VERSION 1.0.11
RUN curl -fLO https://github.com/kubernetes-sigs/kustomize/releases/download/v${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_amd64 && \
    chmod +x kustomize_${KUSTOMIZE_VERSION}_linux_amd64 && \
    mv kustomize_${KUSTOMIZE_VERSION}_linux_amd64 /usr/bin/kustomize

# install kubectx, kubens. see https://github.com/ahmetb/kubectx
RUN curl -fLO https://raw.githubusercontent.com/ahmetb/kubectx/master/kubectx && \
    curl -fLO https://raw.githubusercontent.com/ahmetb/kubectx/master/kubens && \
    chmod +x kubectx kubens && \
    mv kubectx kubens /usr/local/bin

# install kubeval ( validate Kubernetes yaml file to Kube-API )
ENV KUBEVAL_VERSION 0.7.3
RUN curl -fLO https://github.com/garethr/kubeval/releases/download/$KUBEVAL_VERSION/kubeval-linux-amd64.tar.gz && \
    tar xf kubeval-linux-amd64.tar.gz && \
    cp kubeval /usr/local/bin && \
    /bin/rm kubeval-linux-amd64.tar.gz

# install kubetest ( lint kubernetes yaml file )
ENV KUBETEST_VERSION 0.1.1
RUN curl -fLO https://github.com/garethr/kubetest/releases/download/$KUBETEST_VERSION/kubetest-linux-amd64.tar.gz && \
    tar xf kubetest-linux-amd64.tar.gz && \
    cp kubetest /usr/local/bin && \
    /bin/rm kubetest-linux-amd64.tar.gz

# install yamlsort
ENV YAMLSORT_VERSION v0.1.16
RUN curl -fLO https://github.com/george-pon/yamlsort/releases/download/${YAMLSORT_VERSION}/linux_amd64_yamlsort_${YAMLSORT_VERSION}.tar.gz && \
    tar xzf linux_amd64_yamlsort_${YAMLSORT_VERSION}.tar.gz && \
    chmod +x linux_amd64_yamlsort && \
    mv linux_amd64_yamlsort /usr/bin/yamlsort && \
    rm linux_amd64_yamlsort_${YAMLSORT_VERSION}.tar.gz



ADD docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ADD bashrc /root/.bashrc
ADD bash_profile /root/.bash_profile
ADD vimrc /root/.vimrc
ADD bin /usr/local/bin
RUN chmod +x /usr/local/bin/*.sh

ENV HOME /root
ENV ENV $HOME/.bashrc

# add sudo user
# https://qiita.com/iganari/items/1d590e358a029a1776d6 Dockerコンテナ内にsudoユーザを追加する - Qiita
# ユーザー名 ubuntu
# パスワード hogehoge
RUN groupadd -g 1000 ubuntu && \
    useradd  -g      ubuntu -G sudo -m -s /bin/bash ubuntu && \
    echo 'ubuntu:hogehoge' | chpasswd && \
RUN echo 'Defaults visiblepw'            >> /etc/sudoers && \
RUN echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# use normal user ubuntu
# USER ubuntu

CMD ["/usr/local/bin/docker-entrypoint.sh"]

