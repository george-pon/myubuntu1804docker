#!/bin/bash
#
# Docker Desktop for Windows で docker コンテナを起動する
#
# ホスト側のWindowsマシンに OpenSSH で接続可能な設定をしてあれば、
# DOCKER_HOST に ssh://username@host.docker.internal を設定することで
# 起動された側のコンテナの中から docker コマンドを使用可能になる
#
# DEFAULT_IPV4_ADDR には ホスト側Windows PCのIPv4アドレスを定義しておくこと。環境依存。
#

function f-docker-desktop-run-v() {

    # DEFAULT_IPV4_ADDR には ホスト側Windows PCのIPv4アドレスを定義しておくこと。環境依存。
    if [ -z "${DEFAULT_IPV4_ADDR}" ] ; then
        echo "ERROR: environment variable DEFAULT_IPV4_ADDR is not set.  set Windows PC IP v4 Address."
        return 1
    fi

    # SSH 用のパラメータを設定する
    DOCKER_SSH_HOST=${DOCKER_SSH_HOST:-host.docker.internal}
    DOCKER_SSH_USER=${DOCKER_SSH_USER:-${USER}}
    DOCKER_SSH_PORT=${DOCKER_SSH_PORT:-22}
    DOCKER_SSH_KEYFILE=${DOCKER_SSH_KEYFILE:-id_rsa}

    # 秘密鍵ファイルを現在のディレクトリに持ってくる
    if [ -f ~/.ssh/${DOCKER_SSH_KEYFILE} ] ; then
        cp ~/.ssh/id_rsa  ${DOCKER_SSH_KEYFILE}
    fi

    # コンテナの中でsshの初期化ファイルを作成する
cat > init-ssh-config.sh << "SCRIPTEOF"
#!/bin/bash

# copy ~/.ssh/config
mkdir -p $HOME/.ssh
if [ ! -f $HOME/.ssh/config ] ; then
# ssh configファイルを作成する
cat > $HOME/.ssh/config << EOF
Host $DOCKER_SSH_HOST
  HostName $DOCKER_SSH_HOST
  User $DOCKER_SSH_USER
  Port $DOCKER_SSH_PORT
  StrictHostKeyChecking no
  PasswordAuthentication no
  IdentityFile $PWD/$DOCKER_SSH_KEYFILE
  IdentitiesOnly yes
  LogLevel FATAL
  ServerAliveInterval 30
  ServerAliveCountMax 60
  ForwardX11 yes
  ForwardX11Trusted yes
  XAuthLocation /usr/bin/xauth
EOF
fi

# chmod 0600 id_rsa file
if [ -f ${DOCKER_SSH_KEYFILE} ] ; then
    chmod 0600 ${DOCKER_SSH_KEYFILE}
fi

SCRIPTEOF

    # 起動する
    bash  docker-run-v.sh \
        --no-docker-host  \
        --env  DOCKER_HOST=ssh://${DOCKER_SSH_USER}@${DOCKER_SSH_HOST}  \
        --env  DOCKER_SSH_HOST=${DOCKER_SSH_HOST}  \
        --env  DOCKER_SSH_USER=${DOCKER_SSH_USER}  \
        --env  DOCKER_SSH_PORT=${DOCKER_SSH_PORT}  \
        --env  DOCKER_SSH_KEYFILE=${DOCKER_SSH_KEYFILE}  \
        --source-initfile init-ssh-config.sh  \
        --add-host "${DOCKER_SSH_HOST}:${DEFAULT_IPV4_ADDR}"  \
        --docker-pull  \
        --image-debian  \
        "$@"

}

f-docker-desktop-run-v "$@"

