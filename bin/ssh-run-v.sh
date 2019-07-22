#!/bin/bash
#
#  カレントディレクトリをtarでまとめてscpコピーしてからsshでログインする。
#  ログアウト時にはscpでコピーして手元に持ってくる。
#
#  接続先情報は、カレントディレクトリにssh-configファイルがあればそれを参照する
#  ssh-config が無い場合は、 ~/.ssh/config の中の Host から名前を一つ指定して使用する
#
#  ~/.ssh/config の記述例
# Host master1
#   HostName 127.0.0.1
#   User vagrant
#   Port 2200
#   UserKnownHostsFile /dev/null
#   StrictHostKeyChecking no
#   PasswordAuthentication no
#   IdentityFile C:/home/git/vagrant/02_centos7_kubernetes_with_kubeadm_1node/.vagrant/machines/master1/virtualbox/private_key
#   IdentitiesOnly yes
#   LogLevel FATAL
# 

# エラーがあったら停止
set -e

# 初期化
alias rm=rm
alias cp=cp
alias mv=mv
unalias rm
unalias cp
unalias mv

function f-ssh-run-v() {
    # rsyncコマンド存在チェック
    if type rsync 1>/dev/null 2>/dev/null ; then
        echo "rsync found." > /dev/null
    else
        echo "rsync not found. abort."
        return 1
    fi

    # 引数の先頭１個は、~/.ssh/config または ./ssh-config に記載されたホスト名と解釈する
    SSH_CMD_HOST=$1
    if [ -z "$SSH_CMD_HOST" ]; then
        echo "ssh-run-v  needs hostname.  abort."
        return 1
    fi

    # カレントディレクトリに ssh-config があれば、それを使う
    SSH_CMD_CONFIG_OPT=""
    if [ -r ./ssh-config ]; then
        SSH_CMD_CONFIG_OPT=" -F ./ssh-config "
    fi

    SSH_CMD_COMMON_OPT=" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
    YMD_HMS=$( date +%Y%m%d_%H%M%S )
    ARC_FILE_PATH=$( mktemp ../ssh-run-v-archive-$YMD_HMS-XXXXXXXXXXXX.tar.gz )
    ARC_FILE_NAME=$( basename $ARC_FILE_PATH )
    RC_FILE_PATH=$( echo $ARC_FILE_PATH | sed -e 's/.tar.gz/.sh/g' )
    RC_FILE_NAME=$( echo $ARC_FILE_NAME | sed -e 's/.tar.gz/.sh/g' )
    CURRENT_DIR_NAME=$( basename $PWD )
    tar czf  $ARC_FILE_PATH  .
    scp $SSH_CMD_CONFIG_OPT $SSH_CMD_COMMON_OPT $ARC_FILE_PATH  $SSH_CMD_HOST:$ARC_FILE_NAME
    ssh $SSH_CMD_CONFIG_OPT $SSH_CMD_COMMON_OPT $SSH_CMD_HOST -- mkdir -p $CURRENT_DIR_NAME
    ssh $SSH_CMD_CONFIG_OPT $SSH_CMD_COMMON_OPT $SSH_CMD_HOST -- tar xzf $ARC_FILE_NAME -C $CURRENT_DIR_NAME
    ssh $SSH_CMD_CONFIG_OPT $SSH_CMD_COMMON_OPT $SSH_CMD_HOST -- ls -l $ARC_FILE_NAME
    ssh $SSH_CMD_CONFIG_OPT $SSH_CMD_COMMON_OPT $SSH_CMD_HOST -- rm  $ARC_FILE_NAME
    rm $ARC_FILE_PATH
    echo "#!/bin/bash" > $RC_FILE_PATH
    echo 'source ~/.bashrc' >> $RC_FILE_PATH
    echo "cd $CURRENT_DIR_NAME" >> $RC_FILE_PATH
    echo "" >> $RC_FILE_PATH
    scp $SSH_CMD_CONFIG_OPT $SSH_CMD_COMMON_OPT $RC_FILE_PATH  $SSH_CMD_HOST:$RC_FILE_NAME
    rm $RC_FILE_PATH

    # ssh でログイン
    ssh $SSH_CMD_CONFIG_OPT $SSH_CMD_COMMON_OPT -tt  $SSH_CMD_HOST bash --rcfile $RC_FILE_NAME

    RECV_DIR_PATH=$( mktemp -d ../ssh-run-v-receive-$YMD_HMS-XXXXXXXXXXXX )
    ssh $SSH_CMD_CONFIG_OPT $SSH_CMD_COMMON_OPT $SSH_CMD_HOST  tar czf  $ARC_FILE_NAME  $CURRENT_DIR_NAME
    scp $SSH_CMD_CONFIG_OPT $SSH_CMD_COMMON_OPT   $SSH_CMD_HOST:$ARC_FILE_NAME  $ARC_FILE_PATH
    ssh $SSH_CMD_CONFIG_OPT $SSH_CMD_COMMON_OPT $SSH_CMD_HOST  rm  $ARC_FILE_NAME  $RC_FILE_NAME
    tar xzf  $ARC_FILE_PATH  -C  $RECV_DIR_PATH
    rsync -rcv  $RECV_DIR_PATH/$CURRENT_DIR_NAME/  ./
    rm -rf $RECV_DIR_PATH  $ARC_FILE_PATH
}


f-ssh-run-v "$@"

#
# end of file
#
