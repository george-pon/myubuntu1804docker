#!/bin/bash
#
# kube-run-v.sh  自作イメージ(mycentos7docker/mydebian9docker)を起動する
#
#   bashが入っているイメージなら、centosでもdebianでもubuntuでも動く
#
#   pod起動後、カレントディレクトリの内容をPodの中にコピーしてから、kubectl exec -i -t する
#
#   podからexitした後、ディレクトリの内容をPodから取り出してカレントディレクトリに上書きする。
#
#   お気に入りのコマンドをインストール済みのdockerイメージを使って作業しよう
#
#   docker run -v $PWD:$( basename $PWD ) centos  みたいなモノ
#

# set WINPTY_CMD environment variable when it need. (for Windows MSYS2)
function f-check-winpty() {
    if type tty.exe  1>/dev/null 2>/dev/null ; then
        if type winpty.exe 1>/dev/null 2>/dev/null ; then
            local ttycheck=$( tty | grep "/dev/pty" )
            if [ ! -z "$ttycheck" ]; then
                export WINPTY_CMD=winpty
                return 0
            else
                export WINPTY_CMD=
                return 0
            fi
        fi
    fi
    return 0
}

#
# MSYS2 黒魔術
#
# MSYS2では、実行するコマンドが Windows用のexeで、
# コマンドの引数が / からはじまったらファイル名だと思って C:\Program Files\ に変換をかける
# コマンドの引数がファイルならこれで良いのだが、 /C=JP/ST=Tokyo/L=Tokyo みたいなファイルではないパラメータに変換がかかると面倒
# ここでは、条件によってエスケープをかける
#
#   1. cmdがあって、/CがProgram Filesに変換されれば、Windows系 MSYS
#   1. / から始まる場合、MSYS
#
function f-msys-escape() {
    local args="$@"
    export MSYS_FLAG=

    # check cmd is found
    if type cmd 2>/dev/null 1>/dev/null ; then
        # check msys convert
        local result=$( cmd //c echo "/CN=Name")
        if echo $result | grep "Program Files" > /dev/null ; then
            MSYS_FLAG=true
        else
            MSYS_FLAG=
        fi
    fi

    # if not MSYS, normal return
    if [ x"$MSYS_FLAG"x = x""x ]; then
        echo "$@"
        return 0
    fi

    # if MSYS mode...
    # MSYSの場合、/から始まり、/の数が1個の場合は、先頭に / を加えれば望む結果が得られる
    # MSYSの場合、/から始まり、/の数が2個以上の場合は、先頭に // を加え、文中の / を \ に変換すれば望む結果が得られる (UNCファイル指定と誤認させる)
    local i=""
    for i in "$@"
    do
        # if argument starts with /
        local startWith=$( echo $i | awk '/^\// { print $0  }' )
        local slashCount=$( echo $i | awk '{ for ( i = 1 ; i < length($0) ; i++ ) { ch = substr($0,i,1) ; if (ch=="/") { count++; print count }  }  }' | wc -l )
        if [ -n "$startWith"  ]; then
            if [ $slashCount -eq 1 ]; then
                echo "/""$i"
            fi
            if [ $slashCount -gt 1 ]; then
                echo "//"$( echo $i | sed -e 's%^/%%g' -e 's%/%\\%g' )
            fi
        else
            echo "$i"
        fi
    done
}


# Windows環境のみ。rsync.exeは、 Git Bash for Windows から実行した場合、/hoge のような絶対パス表記を受け付けない
# ( 内部で C:/tmp に変換されて C というホストの /hoge にアクセスしようとする)ため、PWDからの相対パスに変更する；；
function f-rsync-escape-relative() {
    realpath --relative-to="$PWD" "$1"
}

#
# ../*-recover.sh ファイルがあれば実行する
#
function f-check-and-run-recover-sh() {
    local i
    local ans
    for i in ../*-recover.sh
    do
        if [ -f "$i" ]; then
            while true
            do
                echo    "  warning. found $i file.  run $i and remove it before run kube-run-v."
                echo -n "  do you want to run $i ? [y/n] : "
                read ans
                if [ x"$ans"x = x"y"x  -o  x"$ans"x = x"yes"x ]; then
                    bash -x "$i"
                    /bin/rm -f "$i"
                    break
                fi
                if [ x"$ans"x = x"n"x  -o  x"$ans"x = x"no"x ]; then
                    /bin/rm -f "$i"
                    break
                fi
            done
        fi
    done
}


# kubernetes server version文字列(1.11.6)をechoする
# k3s環境だと1.14.1-k3s.4なので、-k3s.4の部分はカットする
function f-kubernetes-server-version() {
    local RESULT=$( kubectl version | grep "Server Version" | sed -e 's/^.*GitVersion://g' -e 's/, GitCommit.*$//g' -e 's/"//g' -e 's/^v//g' -e 's/-.*$//g' )
    echo $RESULT
}

# kubernetes version 文字列(1.11.6)を比較する
# ピリオド毎に4桁の整数(000100110006)に変換してechoする
function f-version-convert() {
    local ARGVAL=$( echo $1 | sed -e 's/\./ /g' )
    local i
    local RESULT=""
    for i in $ARGVAL
    do
        if [ -z "$RESULT" ]; then
            RESULT="$(printf "%04d" $i)"
        else
            RESULT="${RESULT}$(printf "%04d" $i)"
        fi
    done
    echo $RESULT
}

# kubernetes 1.10, 1.11ならcarry-on-kubeconfigする必要がある
# kubernetes 1.13.4ならcarry-on-kubeconfigしなくて良い可能性がある
function f-check-kubeconfig-carry-on() {
    export KUBE_SERV_VERSION=$( f-kubernetes-server-version )
    if [ -z "$KUBE_SERV_VERSION" ]; then
        echo "yes"
    fi
    local NOW_KUBE_SERV_VERSION=$( f-version-convert $KUBE_SERV_VERSION )
    local CMP_KUBE_SERV_VERSION=$( f-version-convert "1.13.0" )
    if [ $CMP_KUBE_SERV_VERSION -le $NOW_KUBE_SERV_VERSION ]; then
        echo "no"
    else
        echo "yes"
    fi
}

#
# 自作イメージを起動して、カレントディレクトリのファイル内容をPod内部に持ち込む
#   for kubernetes  ( Linux Bash or Git-Bash for Windows MSYS2 )
#
# カレントディレクトリのディレクトリ名の末尾(basename)の名前で、
# Pod内部のルート( / )にディレクトリを作ってファイルを持ち込む
# 
# Podの中のシェル終了後、Podからファイルの持ち出しをやる。rsyncがあればrsync -crvを使う。無ければtarで上書き展開する。
#
#   https://hub.docker.com/r/georgesan/mycentos7docker/  docker hub に置いてあるイメージ(default)
#
#   https://github.com/george-pon/mycentos7docker  イメージの元 for centos
#   https://gitlab.com/george-pon/mydebian9docker  イメージの元 for debian
#
#
# パスの扱いがちとアレすぎるので kubectl cp は注意。
# ファイルの実行属性を落としてくるので kubectl cp は注意。
#
function f-kube-run-v() {

    # check PWD ( / で実行は許可しない )
    if [ x"$PWD"x = x"/"x ]; then
        echo "kube-run-v: can not run. PWD is / . abort."
        return 1
    fi
    # check PWD ( /tmp で実行は許可しない )
    if [ x"$PWD"x = x"/tmp"x ]; then
        echo "kube-run-v: can not run. PWD is /tmp . abort."
        return 1
    fi

    # check rsync command present.
    local RSYNC_MODE=true
    if type rsync  2>/dev/null 1>/dev/null ; then
        echo "command rsync OK" > /dev/null
    else
        echo "command rsync not found." > /dev/null
        RSYNC_MODE=false
    fi

    # check sudo command present.
    local DOCKER_SUDO_CMD=sudo
    if type sudo 2>/dev/null 1>/dev/null ; then
        echo "command sudo OK" > /dev/null
    else
        echo "command sudo not found." > /dev/null
        DOCKER_SUDO_CMD=
    fi

    # check kubectl version
    kubectl version > /dev/null
    RC=$? ; if [ $RC -ne 0 ]; then echo "kubectl version error. abort." ; return $RC; fi

    local namespace=
    local kubectl_cmd_namespace_opt=
    local interactive=
    local tty=
    local i_or_tty=
    local image=georgesan/mycentos7docker:latest
    local pod_name_prefix=
    local pod_timeout=600
    local imagePullOpt=
    local command_line=
    local env_opts=
    local pseudo_volume_bind=true
    local pseudo_volume_list=
    local pseudo_volume_left=
    local pseudo_volume_right=
    local add_hosts_list=
    local docker_pull=
    # kubectl v 1.11 なら ~/.kube/config をpod内部に持ち込む必要があるかもしれない
    # kubectl v 1.13.4 なら ~/.kube/config をpod内部に持ち込む必要は無い
    # https://qiita.com/sotoiwa/items/aff12291957d85069a76 Kubernetesクラスター内のPodからkubectlを実行する - Qiita
    local carry_on_kubeconfig=
    local carry_on_kubeconfig_file=
    local pseudo_workdir=/$( basename $PWD )
    local pseudo_profile=
    local volume_carry_out=true
    local image_pull_secrets_opt=
    local image_pull_secrets_json=
    local node_select_opt=
    local node_select_json=
    f-check-winpty 2>/dev/null

    # environment variables
    if [ ! -z "$KUBE_RUN_V_IMAGE" ]; then
        image=${KUBE_RUN_V_IMAGE}
    fi
    if [ ! -z "$KUBE_RUN_V_ADD_HOST_1" ]; then
        add_hosts_list="$add_hosts_list $KUBE_RUN_V_ADD_HOST_1"
    fi
    if [ ! -z "$KUBE_RUN_V_ADD_HOST_2" ]; then
        add_hosts_list="$add_hosts_list $KUBE_RUN_V_ADD_HOST_2"
    fi
    if [ ! -z "$KUBE_RUN_V_ADD_HOST_3" ]; then
        add_hosts_list="$add_hosts_list $KUBE_RUN_V_ADD_HOST_3"
    fi
    if [ ! -z "$KUBE_RUN_V_ADD_HOST_4" ]; then
        add_hosts_list="$add_hosts_list $KUBE_RUN_V_ADD_HOST_4"
    fi
    if [ ! -z "$KUBE_RUN_V_ADD_HOST_5" ]; then
        add_hosts_list="$add_hosts_list $KUBE_RUN_V_ADD_HOST_5"
    fi

    # parse argument option
    while [ $# -gt 0 ]
    do
        if [ x"$1"x = x"--add-host"x ]; then
            add_hosts_list="$add_hosts_list $2"
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"-n"x -o x"$1"x = x"--namespace"x ]; then
            namespace=$2
            kubectl_cmd_namespace_opt="--namespace $namespace"
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"-w"x -o x"$1"x = x"--workdir"x ]; then
            pseudo_workdir=$2
            if echo "$pseudo_workdir" | egrep -e '^/.*$' > /dev/null ; then 
                echo "OK. workdir is absolute path." > /dev/null
            else
                echo "OK. workdir is NOT absolute path. abort."
                return 1
            fi
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"--source-profile"x ]; then
            pseudo_profile=$2
            if [ -r "$pseudo_profile" ] ; then 
                echo "OK. pseudo_profile is readable." > /dev/null
            else
                echo "OK. pseudo_profile is NOT readable. abort." > /dev/null
                return 1
            fi
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"-e"x -o x"$1"x = x"--env"x ]; then
            local env_key_val=$2
            local env_key=${env_key_val%%=*}
            local env_val=${env_key_val#*=}
            if [ -z "$env_opts" ]; then
                env_opts="--env $env_key=$env_val"
            else
                env_opts="$env_opts --env $env_key=$env_val"
            fi
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"-i"x -o x"$1"x = x"--interactive"x ]; then
            interactive="-i"
            i_or_tty=yes
            shift
            continue
        fi
        if [ x"$1"x = x"-t"x -o x"$1"x = x"--tty"x ]; then
            tty="-t"
            i_or_tty=yes
            shift
            continue
        fi
        if [ x"$1"x = x"--no-rsync"x ]; then
            RSYNC_MODE=false
            shift
            continue
        fi
        if [ x"$1"x = x"-v"x -o x"$1"x = x"--volume"x ]; then
            pseudo_volume_bind=true
            pseudo_volume_left=${2%%:*}
            pseudo_volume_right=${2##*:}
            if [ x"$pseudo_volume_left"x = x"$2"x ]; then
                echo "  volume list is hostpath:destpath.  : is not found. abort."
                return 1
            elif [ -f "$pseudo_volume_left" ]; then
                echo "OK" > /dev/null
            elif [ -d "$pseudo_volume_left" ]; then
                echo "OK" > /dev/null
            else
                echo "  volume list is hostpath:destpath.  hostpath $pseudo_volume_left is not a directory nor file. abort."
                return 1
            fi
            pseudo_volume_list="$pseudo_volume_list $2"
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"+v"x -o x"$1"x = x"++volume"x ]; then
            pseudo_volume_bind=
            shift
            continue
        fi
        if [ x"$1"x = x"--image"x ]; then
            image=$2
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"--image-centos"x ]; then
            image=georgesan/mycentos7docker:latest
            shift
            continue
        fi
        if [ x"$1"x = x"--image-debian"x ]; then
            image=registry.gitlab.com/george-pon/mydebian9docker:latest
            shift
            continue
        fi
        if [ x"$1"x = x"--image-ubuntu"x ]; then
            image=georgesan/myubuntu1804docker:latest
            shift
            continue
        fi
        if [ x"$1"x = x"--docker-pull"x ]; then
            docker_pull=yes
            shift
            continue
        fi
        if [ x"$1"x = x"--carry-on-kubeconfig"x ]; then
            carry_on_kubeconfig=yes
            shift
            continue
        fi
        if [ x"$1"x = x"++carry-on-kubeconfig"x ]; then
            carry_on_kubeconfig=no
            shift
            continue
        fi
        if [ x"$1"x = x"--read-only"x ]; then
            volume_carry_out=
            shift
            continue
        fi
        if [ x"$1"x = x"--name"x ]; then
            pod_name_prefix=$2
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"--timeout"x ]; then
            pod_timeout=$2
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"--pull"x ]; then
            imagePullOpt=" --image-pull-policy=Always "
            shift
            continue
        fi
        if [ x"$1"x = x"--image-pull-secrets"x ]; then
            image_pull_secrets_opt=" --overrides "
            image_pull_secrets_json=' { "apiVersion": "v1", "spec" : { "imagePullSecrets" : [ { "name" : "'$2'" } ] } } '
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"--node-selector"x ]; then
            node_select_opt=" --overrides "
            node_select_json=' { "apiVersion": "v1", "spec" : { "nodeSelector" : { "kubernetes.io/hostname" : "'$2'" } } } '
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"--help"x ]; then
            echo "kube-run-v"
            echo "    -n, --namespace  namespace        set kubectl run namespace"
            echo "        --image  image-name           set kubectl run image name. default is $image "
            echo "        --image-centos                set image to georgesan/mycentos7docker:latest (default)"
            echo "        --image-ubuntu                set image to georgesan/myubuntu1804docker:latest (default)"
            echo "        --image-debian                set image to registry.gitlab.com/george-pon/mydebian9docker:latest"
            echo "        --carry-on-kubeconfig         carry on kubeconfig file into pod"
            echo "        --docker-pull                 docker pull image before kubectl run"
            echo "        --pull                        always pull image"
            echo "        --image-pull-secrets name     image pull secrets name"
            echo "        --node-selector nodename      set nodeSelector kubernetes.io/hostname label value"
            echo "        --add-host host:ip            add a custom host-to-IP to /etc/hosts"
            echo "        --name pod-name               set pod name prefix. default: taken from image name"
            echo "    -e, --env key=value               set environment variables"
            echo "        --timeout seconds             set pod run timeout (default 300 seconds)"
            echo "    -i, --interactive                 Keep stdin open on the container(s) in the pod"
            echo "    -t, --tty                         Allocated a TTY for each container in the pod."
            echo "    -v, --volume hostpath:destpath    pseudo volume bind (copy current directory) to/from pod."
            echo "    +v, ++volume                      stop automatic pseudo volume bind PWD to/from pod."
            echo "        --read-only                   carry on volume files into pod, but not carry out volume files from pod"
            echo "    -w, --workdir pathname            set pseudo working directory (must be absolute path name)"
            echo "        --source-profile file.sh      set pseudo profile shell name in workdir"
            echo ""
            echo "    ENVIRONMENT VARIABLES"
            echo "        KUBE_RUN_V_IMAGE              set default image name"
            echo "        KUBE_RUN_V_ADD_HOST_1         set host:ip for apply --add-host option"
            echo "        DOCKER_HOST                   pass to pod when kubectl run"
            echo "        http_proxy                    pass to pod when kubectl run"
            echo "        https_proxy                   pass to pod when kubectl run"
            echo "        no_proxy                      pass to pod when kubectl run"
            echo ""
            return 0
        fi
        if [ -z "$command_line" ]; then
            command_line="$1"
        else
            command_line="$command_line $1"
        fi
        shift
    done

    # after argument check
    if [ -z "$namespace" ]; then
        namespace="default"
        kubectl_cmd_namespace_opt="--namespace $namespace"
    fi
    if [ -z "$pod_name_prefix" ]; then
        pod_name_prefix=${image##*/}
        pod_name_prefix=${pod_name_prefix%%:*}
    fi
    if [ -z "$pseudo_volume_list" ]; then
        # current directory copy into pod.
        pseudo_volume_list="$PWD:/$( basename $PWD )"
    fi
    if [ -z "$command_line" ]; then
            interactive="-i"
            tty="-t"
            i_or_tty=yes
    fi
    if [ ! -z "$docker_pull" ]; then
        $DOCKER_SUDO_CMD docker pull $image
    fi

    # check ../*-recover.sh file when volume carry out is true
    if [ x"$volume_carry_out"x = x"true"x ]; then
        f-check-and-run-recover-sh
    fi

    # carry_on_kubeconfig
    if [ -z "$carry_on_kubeconfig" ]; then
        # automatic detect
        local kubectl_current_context=$( kubectl config current-context )
        if [ x"$kubectl_current_context"x = x"docker-for-desktop"x ]; then
            carry_on_kubeconfig=no
        else
            carry_on_kubeconfig=$( f-check-kubeconfig-carry-on )
        fi
    fi
    if [ x"$carry_on_kubeconfig"x = x"yes"x  ]; then
        carry_on_kubeconfig_file=$( realpath $( mktemp "$PWD/../kube-run-v-kubeconfig-XXXXXXXXXXXX" ) )
        kubectl config view --raw > $carry_on_kubeconfig_file
        RC=$? ; if [ $RC -ne 0 ]; then echo "  kubectl config view failed. abort." ; return 1; fi
        pseudo_volume_list="$pseudo_volume_list $carry_on_kubeconfig_file:~/.kube/config"
    fi

    # setup namespace
    if kubectl get namespace $namespace ; then
        echo "namespace $namespace is found."
    else
        echo "namespace $namespace is not found. create it."
        kubectl create namespace $namespace
        RC=$? ; if [ $RC -ne 0 ]; then echo "create namespace error. abort." ; return $RC; fi
    fi

    # setup service account
    if  kubectl ${kubectl_cmd_namespace_opt} get serviceaccount mycentos7docker-${namespace} > /dev/null ; then
        echo "  service account mycentos7docker-${namespace} found."
    else
        kubectl ${kubectl_cmd_namespace_opt} create serviceaccount mycentos7docker-${namespace}
        RC=$? ; if [ $RC -ne 0 ]; then echo "create serviceaccount error. abort." ; return $RC; fi

        kubectl create clusterrolebinding mycentos7docker-${namespace} \
            --clusterrole cluster-admin \
            --serviceaccount=${namespace}:mycentos7docker-${namespace}
        RC=$? ; if [ $RC -ne 0 ]; then echo "create clusterrolebinding error. abort." ; return $RC; fi
    fi

    local TMP_RANDOM=$( date '+%Y%m%d%H%M%S' )
    local POD_NAME="${pod_name_prefix}-$TMP_RANDOM"
    if  kubectl ${kubectl_cmd_namespace_opt} get pod/${POD_NAME} > /dev/null 2>&1 ; then
        echo "  already running pod/${POD_NAME}"
    else
        if true ; then
            # dry run
            echo "  "
            echo "  dry-run : Pod yaml info start"
            kubectl run ${POD_NAME} --restart=Never \
                --image=$image \
                $imagePullOpt \
                --overrides  "${image_pull_secrets_json}${node_select_json}" \
                --serviceaccount=mycentos7docker-${namespace} \
                ${kubectl_cmd_namespace_opt} \
                --env="http_proxy=${http_proxy}" --env="https_proxy=${https_proxy}" --env="no_proxy=${no_proxy}" \
                --env="DOCKER_HOST=${DOCKER_HOST}" \
                ${env_opts} \
                --dry-run -o yaml
            RC=$? ; if [ $RC -ne 0 ]; then echo "kubectl dry-run error. abort." ; return $RC; fi
            echo "  dry-run : Pod yaml info end"
            echo "  "
        fi

        # run
        kubectl run ${POD_NAME} --restart=Never \
            --image=$image \
            $imagePullOpt \
            --overrides  "${image_pull_secrets_json}${node_select_json}" \
            --serviceaccount=mycentos7docker-${namespace} \
            ${kubectl_cmd_namespace_opt} \
            --env="http_proxy=${http_proxy}" --env="https_proxy=${https_proxy}" --env="no_proxy=${no_proxy}" \
            --env="DOCKER_HOST=${DOCKER_HOST}" \
            ${env_opts} \
            --command -- tail -f $(  f-msys-escape '/dev/null' )
        RC=$? ; if [ $RC -ne 0 ]; then echo "kubectl run error. abort." ; return $RC; fi

        # wait for pod Running
        local count=0
        while true
        do
            sleep 2
            local STATUS=$(kubectl ${kubectl_cmd_namespace_opt} get pod/${POD_NAME} | awk '{print $3}' | grep Running)
            RC=$? ; if [ $RC -ne 0 ]; then echo "error. abort." ; return $RC; fi
            if [ ! -z "$STATUS" ]; then
                echo ""
                break
            fi
            echo -n -e "\r  waiting for running pod ... $count / $pod_timeout seconds ..."
            sleep 3
            count=$( expr $count + 5 )
            if [ $count -gt ${pod_timeout} ]; then
                echo "timeout for pod Running. abort."
                return 1
            fi
        done
    fi

    # archive current directory
    local TMP_ARC_FILE=$( mktemp  "../${POD_NAME}-XXXXXXXXXXXX.tar.gz" )
    local TMP_ARC_FILE_RECOVER=${TMP_ARC_FILE}-recover.sh
    local TMP_ARC_FILE_IN_POD=$( echo $TMP_ARC_FILE | sed -e 's%^\.\./%%g' )
    local TMP_DEST_FILE=${namespace}/${POD_NAME}:${TMP_ARC_FILE}
    local TMP_DEST_MSYS2=$( echo $TMP_DEST_FILE | sed -e 's%:\.\./%:%g' )

    # pseudo volume bind
    if [ ! -z "$pseudo_volume_bind" ]; then
        # volume list
        for volarg in $pseudo_volume_list
        do
            # parse argument
            pseudo_volume_left=${volarg%%:*}
            pseudo_volume_right=${volarg##*:}
            if [ x"$pseudo_volume_left"x = x"$volarg"x ]; then
                echo "  volume list is hostpath:destpath.  : is not found. abort."
                return 1
            elif [ -f "$pseudo_volume_left" ]; then
                echo "OK" > /dev/null
            elif [ -d "$pseudo_volume_left" ]; then
                echo "OK" > /dev/null
            else
                echo "  volume list is hostpath:destpath.  hostpath $pseudo_volume_left is not a directory nor file. abort."
                return 1
            fi
            echo "  process ... $pseudo_volume_left : $pseudo_volume_right ..."

            # create archive file
            echo "  creating archive file : $TMP_ARC_FILE"
            if [ -f "$pseudo_volume_left" ]; then
                ( cd $( dirname $pseudo_volume_left ) ; tar czf - $( basename $pseudo_volume_left ) ) > $TMP_ARC_FILE
                RC=$? ; if [ $RC -ne 0 ]; then echo "tar error. abort." ; return $RC; fi
            elif [ -d "$pseudo_volume_left" ]; then
                ( cd $pseudo_volume_left ; tar czf - . ) > $TMP_ARC_FILE
                RC=$? ; if [ $RC -ne 0 ]; then echo "tar error. abort." ; return $RC; fi
            else
                echo "path $pseudo_volume_left is not a directory nor file. abort."
                return 1
            fi

            # kubectl cp
            echo "  kubectl cp into pod"
            kubectl cp  ${kubectl_cmd_namespace_opt}  ${TMP_ARC_FILE}  ${TMP_DEST_MSYS2}
            RC=$? ; if [ $RC -ne 0 ]; then echo "kubectl cp error. abort." ; return $RC; fi

            # kubectl exec ... import and extract archive
            echo "  kubectl exec extract archive in pod"
            if [ -f "$pseudo_volume_left" ]; then
                # ファイルの場合は特例。一度tmpで展開してからターゲットにmvする。
                kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " mkdir -p $( dirname $pseudo_volume_right )"
                kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " mkdir -p /tmp/kube-run-v-tmp"
                kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " tar xzf $TMP_ARC_FILE_IN_POD -C /tmp/kube-run-v-tmp"
                kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " alias mv=mv ; mv /tmp/kube-run-v-tmp/$( basename $pseudo_volume_left ) $pseudo_volume_right "
                kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " alias rm=rm ; rm -rf /tmp/kube-run-v-tmp"
            elif [ -d "$pseudo_volume_left" ]; then
                kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " mkdir -p $pseudo_volume_right "
                kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " tar xzf $TMP_ARC_FILE_IN_POD -C $pseudo_volume_right "
            fi
            kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " alias rm=rm ; rm $TMP_ARC_FILE_IN_POD "
        done
    fi

    if [ ! -z "$add_hosts_list" ] ; then
        local i=
        for i in $add_hosts_list
        do
            local tmp_host=${i%%:*}
            local tmp_ip=${i##*:}
            # kubectl exec ... add /etc/hosts
            echo "  kubectl exec add $tmp_ip $tmp_host to /etc/hosts"
            kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " echo $tmp_ip $tmp_host >> /etc/hosts "
        done
    fi

    if [ ! -z "$pseudo_workdir" ]; then
        # kubectl exec ... set workdir
        kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " mkdir -p /etc/profile.d "
        kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " echo cd $pseudo_workdir >> /etc/profile.d/workdir.sh "
        kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " mkdir -p $pseudo_workdir "
    fi

    if [ ! -z "$pseudo_profile" ]; then
        # kubectl exec ... set profile
        kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " mkdir -p /etc/profile.d "
        kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " echo source $pseudo_profile >> /etc/profile.d/workdir.sh "
    fi

    # create recover shell , when terminal is suddenly gone.
    if [ ! -z "$pseudo_volume_bind" ]; then
        if [ ! -z "$volume_carry_out" ]; then
            echo "  create recover shell ${TMP_ARC_FILE_RECOVER}"
            echo "#!/bin/bash" >> ${TMP_ARC_FILE_RECOVER}
            echo "#" >> ${TMP_ARC_FILE_RECOVER}
            echo "# recover shell when terminal is abort, but pod is running." >> ${TMP_ARC_FILE_RECOVER}
            echo "#" >> ${TMP_ARC_FILE_RECOVER}
            echo "" >> ${TMP_ARC_FILE_RECOVER}
            echo "set -ex" >> ${TMP_ARC_FILE_RECOVER}
            echo "" >> ${TMP_ARC_FILE_RECOVER}
            echo "cd $PWD" >> ${TMP_ARC_FILE_RECOVER}
            echo "" >> ${TMP_ARC_FILE_RECOVER}
            for volarg in $pseudo_volume_list
            do
                # parse argument
                pseudo_volume_left=${volarg%%:*}
                pseudo_volume_right=${volarg##*:}
                if [ x"$pseudo_volume_left"x = x"$volarg"x ]; then
                    echo "  volume list is hostpath:destpath.  : is not found. abort."
                    return 1
                elif [ -f "$pseudo_volume_left" ]; then
                    echo "OK" > /dev/null
                elif [ -d "$pseudo_volume_left" ]; then
                    echo "OK" > /dev/null
                else
                    echo "  volume list is hostpath:destpath.  hostpath is not a directory nor file. abort."
                    return 1
                fi

                # kubectl exec ... create archive and kubectl cp to export
                if [ -d "$pseudo_volume_left" ]; then
                    echo "kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c \" ( cd $pseudo_volume_right && tar czf - . ) > $TMP_ARC_FILE_IN_POD \"" >> ${TMP_ARC_FILE_RECOVER}
                elif [ -f "$pseudo_volume_left" ]; then
                    echo "kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c \" ( cd $( dirname $pseudo_volume_right ) && tar czf - $( basename $pseudo_volume_right ) ) > $TMP_ARC_FILE_IN_POD \"" >> ${TMP_ARC_FILE_RECOVER}
                else
                    echo "volume list $pseudo_volume_list is not a directory for file. aobrt."
                    return 1
                fi

                # kubectl cp get archive file
                echo "/bin/rm -f $TMP_ARC_FILE" >> ${TMP_ARC_FILE_RECOVER}
                echo "kubectl cp  ${kubectl_cmd_namespace_opt}  ${TMP_DEST_MSYS2}  .." >> ${TMP_ARC_FILE_RECOVER}

                # if rsync is present, use rsync
                if [ x"$RSYNC_MODE"x = x"true"x ]; then
                    # extract archive file into temp directory
                    local TMP_EXT_DIR=$( mktemp -d ../${POD_NAME}-tmp-XXXXXXXXXXXX )
                    echo "mkdir -p ${TMP_EXT_DIR}" >> ${TMP_ARC_FILE_RECOVER}
                    echo "tar xzf $TMP_ARC_FILE -C $TMP_EXT_DIR" >> ${TMP_ARC_FILE_RECOVER}
                    echo "/bin/rm -f $TMP_ARC_FILE" >> ${TMP_ARC_FILE_RECOVER}

                    # rsync data copy
                    if [ -f "$pseudo_volume_left" ]; then
                        echo "rsync -rvc --delete $TMP_EXT_DIR/$( basename $pseudo_volume_right )  $( f-rsync-escape-relative $pseudo_volume_left )" >> ${TMP_ARC_FILE_RECOVER}
                    elif [ -d "$pseudo_volume_left" ]; then
                        echo "rsync -rvc --delete $TMP_EXT_DIR/  $( f-rsync-escape-relative $pseudo_volume_left/ )" >> ${TMP_ARC_FILE_RECOVER}
                    fi
                    # remove temp dir
                    echo "/bin/rm -rf $TMP_EXT_DIR" >> ${TMP_ARC_FILE_RECOVER}
                    /bin/rm -rf $TMP_EXT_DIR
                else
                    # rsync is not present.  tar overwrite
                    if [ -f "$pseudo_volume_left" ]; then
                        echo "tar xzf $TMP_ARC_FILE -C $( dirname $pseudo_volume_left )" >> ${TMP_ARC_FILE_RECOVER}
                    elif [ -d "$pseudo_volume_left" ]; then
                        echo "( tar xzf $TMP_ARC_FILE -C $pseudo_volume_left )" >> ${TMP_ARC_FILE_RECOVER}
                    fi
                    echo "/bin/rm -f $TMP_ARC_FILE" >> ${TMP_ARC_FILE_RECOVER}
                fi

                # delete pod
                echo "if kubectl ${kubectl_cmd_namespace_opt} delete pod ${POD_NAME} --grace-period 3 ; then" >> ${TMP_ARC_FILE_RECOVER}
                echo "    echo pod delete success." >> ${TMP_ARC_FILE_RECOVER}
                echo "else" >> ${TMP_ARC_FILE_RECOVER}
                echo "    echo pod delete failure." >> ${TMP_ARC_FILE_RECOVER}
                echo "fi" >> ${TMP_ARC_FILE_RECOVER}
            done
        fi
    fi
    if [ x"$carry_on_kubeconfig"x = x"yes"x ]; then
        echo "/bin/rm -f $carry_on_kubeconfig_file" >> ${TMP_ARC_FILE_RECOVER}
    fi


    # exec into pod
    if [ ! -z "$i_or_tty" ]; then
        # interactive mode
        echo "  base workdir name : $pseudo_workdir"
        echo "  interactive mode"
        echo "  ${WINPTY_CMD} kubectl exec ${interactive}  ${tty}  ${kubectl_cmd_namespace_opt} ${POD_NAME}  -- bash --login"
        ${WINPTY_CMD} kubectl exec ${interactive}  ${tty}  ${kubectl_cmd_namespace_opt} ${POD_NAME}  -- bash --login
    else
        echo "  base workdir name : $pseudo_workdir"
        echo "  running command : $command_line"
        echo "  ${WINPTY_CMD} kubectl exec                         ${kubectl_cmd_namespace_opt} ${POD_NAME}  -- bash --login -c  $command_line"
        ${WINPTY_CMD} kubectl exec                         ${kubectl_cmd_namespace_opt} ${POD_NAME}  -- bash --login -c  "$command_line"
    fi

    # after pod exit
    if [ ! -z "$pseudo_volume_bind" ]; then
        if [ ! -z "$volume_carry_out" ]; then
            for volarg in $pseudo_volume_list
            do
                # parse argument
                pseudo_volume_left=${volarg%%:*}
                pseudo_volume_right=${volarg##*:}
                if [ x"$pseudo_volume_left"x = x"$volarg"x ]; then
                    echo "  volume list is hostpath:destpath.  : is not found. abort."
                    return 1
                elif [ -f "$pseudo_volume_left" ]; then
                    echo "OK" > /dev/null
                elif [ -d "$pseudo_volume_left" ]; then
                    echo "OK" > /dev/null
                else
                    echo "  volume list is hostpath:destpath.  hostpath is not a directory nor file. abort."
                    return 1
                fi
                echo "  processing volume list ... $pseudo_volume_left : $pseudo_volume_right "

                # kubectl exec ... create archive and kubectl cp to export
                echo "  creating archive file in pod : $TMP_ARC_FILE_IN_POD"
                if [ -d "$pseudo_volume_left" ]; then
                    kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " ( cd $pseudo_volume_right && tar czf - . ) > $TMP_ARC_FILE_IN_POD "
                    RC=$? ; if [ $RC -ne 0 ]; then echo "kubectl exec error. abort." ; return $RC; fi
                elif [ -f "$pseudo_volume_left" ]; then
                    kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " ( cd $( dirname $pseudo_volume_right ) && tar czf - $( basename $pseudo_volume_right ) ) > $TMP_ARC_FILE_IN_POD "
                    RC=$? ; if [ $RC -ne 0 ]; then echo "kubectl exec error. abort." ; return $RC; fi
                else
                    echo "volume list $pseudo_volume_list is not a directory for file. aobrt."
                    return 1
                fi

                # kubectl cp get archive file
                echo "  kubectl cp from pod"
                /bin/rm -f $TMP_ARC_FILE
                kubectl cp  ${kubectl_cmd_namespace_opt}  ${TMP_DEST_MSYS2}  ../
                RC=$? ; if [ $RC -ne 0 ]; then echo "kubectl cp error. abort." ; return $RC; fi

                # if rsync is present, use rsync
                if [ x"$RSYNC_MODE"x = x"true"x ]; then
                    # extract archive file into temp directory
                    local TMP_EXT_DIR=$( mktemp -d "../${POD_NAME}-tmp-XXXXXXXXXXXX" )
                    echo "  tar extracting in $TMP_EXT_DIR"
                    tar xzf $TMP_ARC_FILE -C $TMP_EXT_DIR
                    RC=$? ; if [ $RC -ne 0 ]; then echo "tar error. abort." ; return $RC; fi
                    /bin/rm -f $TMP_ARC_FILE

                    # rsync data copy
                    if [ -f "$pseudo_volume_left" ]; then
                        # ファイルの場合は特例。一度テンポラリで展開してmvする。
                        echo "  rsync -rvc --delete $TMP_EXT_DIR/$( basename $pseudo_volume_right )  $( f-rsync-escape-relative $pseudo_volume_left )"
                        rsync -rvc --delete $TMP_EXT_DIR/$( basename $pseudo_volume_right )  $( f-rsync-escape-relative $pseudo_volume_left )
                        RC=$? ; if [ $RC -ne 0 ]; then echo "  rsync error. abort." ; return $RC; fi
                    elif [ -d "$pseudo_volume_left" ]; then
                        echo "  rsync -rvc --delete $TMP_EXT_DIR/  $( f-rsync-escape-relative $pseudo_volume_left/ ) "
                        rsync -rvc --delete $TMP_EXT_DIR/  $( f-rsync-escape-relative $pseudo_volume_left/ )
                        RC=$? ; if [ $RC -ne 0 ]; then echo "  rsync error. abort." ; return $RC; fi
                    fi
                    # remove temp dir
                    /bin/rm -rf $TMP_EXT_DIR
                else
                    # rsync is not present.  tar overwrite
                    echo "  tar extract from : $TMP_ARC_FILE "
                    if [ -f "$pseudo_volume_left" ]; then
                        tar xzf $TMP_ARC_FILE -C $( dirname $pseudo_volume_left )
                        RC=$? ; if [ $RC -ne 0 ]; then echo "tar error. abort." ; return $RC; fi
                    elif [ -d "$pseudo_volume_left" ]; then
                        ( tar xzf $TMP_ARC_FILE -C $pseudo_volume_left )
                        RC=$? ; if [ $RC -ne 0 ]; then echo "tar error. abort." ; return $RC; fi
                    fi
                    /bin/rm -f $TMP_ARC_FILE
                fi
            done
        fi
    fi

    if [ x"$carry_on_kubeconfig"x = x"yes"x ]; then
        /bin/rm -f $carry_on_kubeconfig_file
    fi

    # delete pod
    echo "  delete pod ${POD_NAME} ${kubectl_cmd_namespace_opt}"
    kubectl delete pod ${POD_NAME} ${kubectl_cmd_namespace_opt} --grace-period 3
    RC=$? ; if [ $RC -ne 0 ]; then echo "kubectl delete error. abort." ; return $RC; fi

    # delete recover shell
    echo "  delete recover shell ${TMP_ARC_FILE_RECOVER}"
    /bin/rm -f ${TMP_ARC_FILE_RECOVER}
}

# if source this file, define function only ( not run )
if [ ${#BASH_SOURCE[@]} = 1 ]; then
    f-kube-run-v "$@"
    RC=$?
    exit $RC
else
    echo "source from $0. define function only. not run." > /dev/null
fi

#
# end of file
#
