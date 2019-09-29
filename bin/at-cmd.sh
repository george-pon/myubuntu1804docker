#!/bin/bash
#
#  指定時刻まで待ってコマンドラインのコマンドを実行する
#
#  使用例  at-cmd.sh 1830  ls -la
#
#  時刻は HHMM 形式で指定する
#

function f-at-cmd-usage() {
    echo "at-cmd.sh  time  command ..."
}

function f-at-cmd() {

    local curtime=
    local curtime2=
    local targettime=

    # 引数解析
    while [ $# -gt 0 ];
    do
        if [ x"$targettime"x = x""x ]; then
            targettime=$1
            shift
            continue
        fi

        break
    done

    # チェック
    if [ -z "$targettime" ]; then
        f-at-cmd-usage
        return 0
    fi

    # 時間待ち
    while true
    do
        curtime=$( date +%H%M )
        curtime2=$( date +%H%M )
        echo -n -e  "\rtarget time : $targettime    current time : $curtime2    command: $@"
        if [ x"$curtime"x = x"$targettime"x ] ; then
            echo " ... found."
            break
        fi
        sleep 20
    done

    # コマンド実行
    "$@"

}

f-at-cmd  "$@"

#
# end of file
#
