#!/bin/bash
#
#  コピーペーストしやすい形にファイルを標準出力に出力する
#


#
# ファイルがテキストかどうか判定する。 0 ならテキスト。
#
function f_is_text_file() {
    local file=$1
    local fileType=$( file -i -b $file )
    local bText=false
    if echo $fileType | grep text/plain > /dev/null ; then
        return 0
    elif echo $fileType | grep text/x-shellscript > /dev/null ; then
        return 0
    elif echo $fileType | grep text/html > /dev/null ; then
        return 0
    fi
    return 1
}

#
#  コピーペーストしやすい形にファイルを標準出力に出力する
#
function f-shar-cat() {
    if [ $# -eq 0 ]; then
        echo "f-shar-cat  [options] directory-name or file-name"
        echo "    options"
        echo "        --binary ... base64 encode when binary file"
        echo "        --newer file ... find newer file"
        return 0
    fi

    # オプション
    local allow_binary=
    local allow_newer_opt=
    # 引数解析
    while [ $# -gt 0 ];
    do
        if [ x"$1"x = x"--binary"x ]; then
            allow_binary=true
            shift
            continue
        fi
        if [ x"$1"x = x"--newer"x ]; then
            allow_newer_opt=" -newer $2 "
            if [ ! -r "$2" ]; then
                echo "file can not found. $2. abort."
                return 1
            fi
            shift
            shift
            continue
        fi
        break
    done

    local target_dir="$@"
    local file_list=$( find $target_dir $allow_newer_opt | grep -v ".git/"  )
    local i=
    for i in $file_list
    do
        if [ -d "$i" ]; then
            echo "mkdir -p $i"
        fi
        if [ -f "$i" ]; then
            f_is_text_file "$i"
            local bText=$?
            if [ $bText -ne 0 ]; then
                echo "#"
                echo "# file $i is binary file. "
                echo "#"
                if [ x"$allow_binary"x = x"true"x ]; then
                    echo "mkdir -p $( dirname $i )"
                    echo 'cat > '"$i".base64' << "SCRIPTSHAREOF"'
                    cat "$i" | base64
                    echo "SCRIPTSHAREOF"
                    echo 'cat '"$i".base64' | base64 -d > '"$i"
                else
                    echo "# skip"
                fi
            else
                echo "#"
                echo "# $i"
                echo "#"
                echo "mkdir -p $( dirname $i )"
                echo 'cat > '"$i"' << "SCRIPTSHAREOF"'
                expand -t 4 $i
                echo "SCRIPTSHAREOF"
                echo ""
                echo ""
            fi
        fi
    done
}

# if source this file, define function only ( not run )
if [ ${#BASH_SOURCE[@]} = 1 ]; then
    f-shar-cat "$@"
    RC=$?
    exit $RC
else
    echo "source from $0. define function only. not run." > /dev/null
fi

#
# end of file
#
