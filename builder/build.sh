#!/bin/bash

function show_help() {
    cat << EOF
Usage: ${0##*/} [-lr] [-b branch] [-u user] [-p password]
    -b      git branch to build
    -l      tag images as lastest
    -r      push images to a registry
    -u      username for authentication on registry
    -p      password for authentication on registry
EOF
}

#we want to be able to interupt the build, see: http://veithen.github.io/2014/11/16/sigterm-propagation.html
function run() {
    trap 'kill -TERM $PID' TERM INT
    $@ &
    PID=$!
    wait $PID
    trap - TERM INT
    wait $PID
    return $?
}

branch=dev
tag_latest=0
push=0
user=''
password=''
components='jormungandr kraken tyr-beat tyr-worker tyr-web'

while getopts "lrb:u:p:" opt; do
    case $opt in
        b)
            branch=$OPTARG
            ;;
        p)
            password=$OPTARG
            ;;
        u)
            user=$OPTARG
            ;;
        l)
            tag_latest=1
            ;;
        r)
            push=1
            ;;
        h|\?)
            show_help
            exit 1
            ;;
    esac
done

set -e

echo "building branch $branch"


run git pull && git checkout $branch && git submodule update --init
run cmake -DCMAKE_BUILD_TYPE=Release source
run make -j$(nproc) kraken ed_executables

git describe

version=$(git describe)

for component in $components; do
    run docker build -t navitia/$component:$version -f  Dockerfile-$component .
    if [ $tag_latest -eq 1 ]; then
        docker tag navitia/$component:$version navitia/$component:latest
    fi
done

if [ $push -eq 1 ]; then
    if [ -n $user ]; then docker login -u $user -p $password; fi
    for component in $components; do
        docker push navitia/$component:$version
    if [ $tag_latest -eq 1 ]; then
        docker push navitia/$component:latest
    fi
    done
    if [ -n $user ]; then docker logout; fi
fi
