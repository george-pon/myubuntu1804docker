#!/bin/bash
#
# git操作共通関数
#

function f_git() {
    echo "git $@"
    git "$@"
    local RC=$?
    if [ $RC -ne 0 ]; then
        echo "ERROR: git $@ failed."
    fi
    return $RC
}

function git-user-name() {
    # GIT_IDを取得する
    local GIT_ID=`git config --global --list|grep user.name| sed 's/user.name=//g'`
    if [ -z "$GIT_ID" ]; then
        echo user.name is null.
        return 1
    fi
    # スペースはアンダースコアに変換
    GIT_ID=$( echo $GIT_ID | sed -e 's/ /_/g' )
    echo $GIT_ID
}

function git-status-check() {
    if git status | grep "nothing to commit, working tree clean" 1>/dev/null 2>/dev/null ; then
        echo "CLEAN"
    else
        echo "DURTY"
    fi
}

function git-lol() {
    f_git log --graph --decorate --pretty=oneline --abbrev-commit
}

function git-lola() {
    f_git log --graph --decorate --pretty=oneline --abbrev-commit --all
}

function git-branch-a() {
    f_git branch -a
}

# よくあるgitの初期化を実施する
function git-initialize() {
    # コミットする時に保存されるユーザー名とメールアドレス
    git config --global user.name "Jun Obama"
    git config --global user.email "george@yk.rim.or.jp"

    # 日本語パス名の文字化け対策
    git config --global core.quotepath false

    # 改行コードの自動変換の無効化。
    git config --global core.autocrlf false

    # push を upstreamに限定する
    git config --global push.default upstream

    # ページャーは使用しない
    # git config --global core.pager ''

    # 自己署名な証明書を許可する
    git config --global http.sslVerify false

    # gitの認証情報を保存する
    git config --global credential.helper store

    # ファイル名の大文字小文字の変動を追尾する
    # これはリポジトリ毎設定なのでここでは実行しない
    # git config core.ignorecase false

    # git pull した時の戦略。マージする。(rebaseはしない)
    git config pull.rebase false

}

function git-dirs() {
    # 全階層のgit clone のリストを作成する。
    local GIT_CLONE_DIR_LIST=`find .  -name ".git" |  egrep -v '\bpkg\b' | egrep -v '\bdep\b' | sed -e 's%.git$%%g' | sed -e 's%/$%%g' `
    echo $GIT_CLONE_DIR_LIST
    if [ -z "$GIT_CLONE_DIR_LIST" ]; then
        return 1
    fi
}

# pull request が全部消化された時に、developに戻す際に使う
# ユーザー名が含まれており、ローカルにだけあるブランチは消す （！注意！）
# dep,pkgというディレクトリの下の.gitは無視する。depコマンドで拾った依存ライブラリはgit pullしない。
function git-branch-clean-all() {
    local GIT_ID=$( git-user-name )
    local GIT_CLONE_DIR_LIST=$( git-dirs )
    echo "#"
    echo "# delete ${GIT_ID}'s branches"
    echo "#"

    # リスト毎に"$GIT_ID/#*"ブランチを削除する。
    for GIT_CLONE_DIR in $GIT_CLONE_DIR_LIST
    do
        local GIT_DEFAULT_BRANCH_NAME=develop
        SAVED_PWD=$PWD
        cd ${GIT_CLONE_DIR}
        echo "------------------------------"
        echo "----- ${GIT_CLONE_DIR} "
        echo "------------------------------"
        # fetch する。リモートリポジトリでは削除されているブランチは、削除する。
        f_git fetch --prune
        RC=$? ; if [ $RC -ne 0 ]; then return 1; fi
        # カレントブランチを取得する
        CUR_BRANCH=`git branch | grep '^*' | sed -e 's/^\*/ /g' -e 's/^  //g'`
        # ブランチ一覧を取得する
        BR_LIST=`git branch | sed 's/^\*/ /g'`
        # リモートブランチ一覧取得
        BR_LIST_2=$( git branch -a | sed 's/^\*/ /g' | grep remotes/origin )
        # リモートブランチにdevelopがない場合は、デフォルトブランチ名はmasterとする
        BR_LIST_3=$( echo $BR_LIST_2 | grep develop )
        if [ -z "$BR_LIST_3" ]; then
            GIT_DEFAULT_BRANCH_NAME=master
        fi
        echo "GIT_DEFAULT_BRANCH_NAME is $GIT_DEFAULT_BRANCH_NAME"
        # カレントブランチがdirtyではなく、developまたはmasterの場合は、git pullを行う
        STATUS=$( git status | grep "nothing to commit" )
        if [ ! -z "$STATUS" ]; then
            if [ x"$CUR_BRANCH"x = x"master"x -o x"$CUR_BRANCH"x = x"develop"x ]; then
                f_git pull
                RC=$? ; if [ $RC -ne 0 ]; then return 1; fi
            else
                echo "workspace is not master nor develop branch.  skip git pull."
            fi
        else
            echo "workspace is durty.  skip git pull."
        fi

        # ローカルブランチの掃除
        for BR in ${BR_LIST};
        do
            # 自分のユーザー名を含むブランチのみお掃除対象
            if [ `echo "${BR}" | grep "$GIT_ID"` ] ; then
                STATUS=$( git status | grep "nothing to commit" )
                if [ -z "$STATUS" ]; then
                    # カレントブランチがdirtyな場合は掃除しない
                    echo "directory: $GIT_CLONE_DIR , branch: $CUR_BRANCH is not clean. skip git branch -d $BR."
                elif [ ! -z "$( echo $BR_LIST_2 | grep $BR )" ]; then
                    # remoteブランチに残っている場合は残す
                    echo "directory: $GIT_CLONE_DIR , branch: $BR has remote branch. skip git branch -d $BR."
                elif [ x"$BR"x == x"$CUR_BRANCH"x ]; then
                    # currentブランチがリモートにない場合はデフォルトブランチ名(developまたはmaster)に戻してブランチは削除する
                    f_git checkout $GIT_DEFAULT_BRANCH_NAME
                    RC=$? ; if [ $RC -ne 0 ]; then return 1; fi
                    f_git pull
                    RC=$? ; if [ $RC -ne 0 ]; then return 1; fi
                    f_git branch -d ${BR}
                    RC=$? ; if [ $RC -ne 0 ]; then return 1; fi
                else
                    f_git branch -d ${BR}
                    RC=$? ; if [ $RC -ne 0 ]; then return 1; fi
                fi
            fi
        done
        echo ""
        cd $SAVED_PWD
    done
}

function git-branch-new() {
    #
    # 新しいブランチを作成する
    # git-branch-new  branch-name
    #
    # 新しいブランチを作成する。 obama-jyun/#20180417_163658_subbranchname というブランチ名をつける。 
    # git-branch-new  -n  subbranchname
    #
    # 新しいブランチを作成して git add . ; git commit ; git push を一気に行う
    # git-branch-new  -m  "commit message"
    #
    # 新しいブランチ branch_sub_name を作成して git add . ; git commit ; git push を一気に行う
    # git-branch-new  -m  "commit message"  -n branch_sub_name
    #

    # GIT_IDを取得する
    local GIT_ID=$( git-user-name )

    local YMD_HMS=$( date +%Y%m%d_%H%M%S )
    local DEFAULT_BRANCH_NAME="$GIT_ID/#$YMD_HMS"
    local BRANCH_NAME=$DEFAULT_BRANCH_NAME
    local COMMIT_COMMENT=""

    # 引数解析
    while true
    do
        if [ $# -eq 0 ]; then
            break
        fi

        if [ "$1" = "-m" ]; then
            # -m comment があった場合は、コミットコメントとして採用。pushまで自動で行う。
            COMMIT_COMMENT=$2
            echo "auto commit mode. commit comment : $COMMIT_COMMENT"
            shift
        elif [ "$1" = "-n" ]; then
            BRANCH_NAME="${DEFAULT_BRANCH_NAME}_$2"
            echo "named branch mode. new branch name : $BRANCH_NAME"
            shift
        else
            # 引数があった場合はブランチ名として採用
            BRANCH_NAME=$1
            echo "named branch mode. new branch name : $BRANCH_NAME"
        fi
        shift
    done

    echo "create new branch $BRANCH_NAME"

    # developに戻す
    # f_git checkout develop

    # pullする
    # f_git pull
    # RC=$? ; if [ $RC -ne 0 ]; then return 1; fi

    # リモートリポジトリでは削除されているブランチは、削除する
    f_git fetch --prune
    RC=$? ; if [ $RC -ne 0 ]; then return 1; fi

    # branchを新しく作成する
    f_git branch $BRANCH_NAME
    RC=$? ; if [ $RC -ne 0 ]; then return 1; fi

    # 作成したブランチに切り替え
    f_git checkout $BRANCH_NAME
    RC=$? ; if [ $RC -ne 0 ]; then return 1; fi

    # ブランチの一覧を表示
    f_git branch -a
    RC=$? ; if [ $RC -ne 0 ]; then return 1; fi

    # 現在のステータスを表示
    f_git status
    RC=$? ; if [ $RC -ne 0 ]; then return 1; fi

    echo ""
    echo "  run below commands:"
    echo "    git add <file> ..."
    echo "    git commit -m comment"
    echo "    git push --set-upstream origin $BRANCH_NAME"
    echo ""

    # コミットコメントがある場合は、add / commit / push まで行う
    if [ ! -z "$COMMIT_COMMENT" ]; then
        f_git add .
        RC=$? ; if [ $RC -ne 0 ]; then return 1; fi
        f_git commit -m "$COMMIT_COMMENT"
        RC=$? ; if [ $RC -ne 0 ]; then return 1; fi
        f_git push --set-upstream origin $BRANCH_NAME
        RC=$? ; if [ $RC -ne 0 ]; then return 1; fi
    fi
}

function git-branch-status-all() {
    local GIT_ID=$( git-user-name )
    local GIT_CLONE_DIR_LIST=$( git-dirs )
    for GIT_CLONE_DIR in $GIT_CLONE_DIR_LIST
    do
        SAVED_PWD=$PWD
        cd ${GIT_CLONE_DIR}
        echo "------------------------------"
        echo "----- ${GIT_CLONE_DIR}  "
        echo "------------------------------"
        # git fetch --prune
        f_git status
        echo ""
        cd $SAVED_PWD
    done
}


# ローカルでtagをつけて、それをpushする
# git tagには -m でメッセージを付けないと git describe で表示時にエラーになる
function git-branch-tag-and-push() {
    if [ $# -eq 0 ]; then
        echo "git-branch-tag-and-push [-m tag_message] tag-name [tag-name]"
        return 1
    fi
    local ARG_MESSAGE="add tag"
    if [ x"$1"x = x"-m"x ]; then
        ARG_MESSAGE="$2"
        shift
        shift
    fi
    local ARG_TAG
    for ARG_TAG in "$@"
    do
        # 現在のタグ一覧を取得。一致しているものがあったら、削除する。
        local CUR_TAG_LIST=$( git tag -l )
        local i
        for i in $CUR_TAG_LIST ;
        do
            if [ x"$i"x = x"$ARG_TAG"x ]; then
                echo "git-branch-tag-and-push: tag $ARG_TAG is already set."
                echo "git-branch-tag-and-push: at first , remove tag $ARG_TAG."
                f_git tag -d $ARG_TAG
                RC=$? ; if [ $RC -ne 0 ]; then echo "ERROR. abort." ; return 1; fi
                f_git push origin :$ARG_TAG
                RC=$? ; if [ $RC -ne 0 ]; then echo "ERROR. abort." ; return 1; fi
                break
            fi
        done
        # タグをつけて、originにpushする。
        f_git tag -m "$ARG_MESSAGE" $ARG_TAG
        RC=$? ; if [ $RC -ne 0 ]; then echo "ERROR. abort." ; return 1; fi
        f_git push origin $ARG_TAG
        RC=$? ; if [ $RC -ne 0 ]; then echo "ERROR. abort." ; return 1; fi
    done
}

# ローカルでtagを削除して、それをpushする
function git-branch-tag-remove-and-push() {
    if [ $# -eq 0 ]; then
        echo "git-branch-tag-remove-and-push tag-name"
        return 1
    fi
    local ARG_TAG=$1
    # 現在のタグ一覧を取得。一致しているものがあったら、削除する。
    local CUR_TAG_LIST=$( git tag -l )
    for i in $CUR_TAG_LIST ;
    do
        if [ x"$i"x = x"$ARG_TAG"x ]; then
            echo "git-branch-tag-remove-and-push: remove tag $ARG_TAG."
            f_git tag -d $ARG_TAG
            RC=$? ; if [ $RC -ne 0 ]; then echo "ERROR. abort." ; return 1; fi
            f_git push origin :$ARG_TAG
            RC=$? ; if [ $RC -ne 0 ]; then echo "ERROR. abort." ; return 1; fi
            break
        fi
    done
}

# developからmasterにマージする
function git-branch-merge-master() {

    # pullする
    f_git pull
    RC=$? ; if [ $RC -ne 0 ]; then return 1; fi

    # masterをチェックアウトする
    f_git checkout master
    RC=$? ; if [ $RC -ne 0 ]; then return 1; fi

    # pullする
    f_git pull
    RC=$? ; if [ $RC -ne 0 ]; then return 1; fi

    # developをマージする
    f_git merge develop
    RC=$? ; if [ $RC -ne 0 ]; then return 1; fi

    # commitする
    #f_git commit -m "merge from develop"
    #RC=$? ; if [ $RC -ne 0 ]; then return 1; fi

    # pushする
    f_git push
    RC=$? ; if [ $RC -ne 0 ]; then return 1; fi

    # developをチェックアウトする
    f_git checkout develop
    RC=$? ; if [ $RC -ne 0 ]; then return 1; fi

}

# コミットしてpushする
function git-branch-add() {
    local COMMIT_COMMENT=
    local ARG_TAG_LIST=

    # 引数解析
    if [ $# -eq 0 ]; then
        echo "git-branch-add   [] -m commit-comment ]   [ -t tag ]"
    fi
    # 引数解析
    while true
    do
        if [ $# -eq 0 ]; then
            break
        fi

        if [ "$1" = "-m" ]; then
            # -m comment があった場合は、コミットコメントとして採用。pushまで自動で行う。
            COMMIT_COMMENT=$2
            echo "auto commit mode. commit comment : $COMMIT_COMMENT"
            shift
        fi
        if [ "$1" = "-t" ]; then
            # -t tag があった場合は、タグ付けまで自動で行う。
            ARG_TAG_LIST="$ARG_TAG_LIST $2"
            echo "auto tag mode. tag : $ARG_TAG_LIST"
            shift
        fi
        shift
    done

    f_git diff
    f_git status

    local GIT_STATUS=$( git-status-check )
    if [ x"$GIT_STATUS"x = x"DURTY"x ]; then

        f_git add .
        if [ -z "$COMMIT_COMMENT" ]; then
            return 0
        fi

        f_git commit -m "$COMMIT_COMMENT"
        RC=$? ; if [ $RC -ne 0 ]; then return 1; fi

        f_git push
        RC=$? ; if [ $RC -ne 0 ]; then return 1; fi

    fi

    for i in $ARG_TAG_LIST
    do
        git-branch-tag-and-push $i
        RC=$? ; if [ $RC -ne 0 ]; then return 1; fi
    done
}

#
#  １コミットの内容だけを他のブランチで取り込みたい場合
#
function git-branch-cherry-pick() {
    local COMMIT_IDS="$@"
    if [ -z "$COMMIT_IDS" ]; then
        echo "git-branch-cherry-pick  commit-id1 [commit-id2...]"
        return 0
    fi

    git cherry-pick  --allow-empty    "$COMMIT_IDS"
    RC=$? ; if [ $RC -ne 0 ]; then return 1; fi

}

#
# 「ええーいリモートが合ってるんだからアイツに合わせたいんだよ！」
# とイライラしたら下記。
#
function git-branch-force-master-pull() {
    f-git checkout master
    RC=$? ; if [ $RC -ne 0 ]; then return 1; fi
    f-git fetch origin
    RC=$? ; if [ $RC -ne 0 ]; then return 1; fi
    f-git reset --hard origin/master
    RC=$? ; if [ $RC -ne 0 ]; then return 1; fi
}

