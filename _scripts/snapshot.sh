#!/bin/bash

# Take screenshots of very HTML page in the site

set -euo pipefail

echov () {
    eval 'echo $1=$'"$1"
}

cleanup() {
    if [[ -n ${SERVERPID-} ]]; then
        echo "Killing http-server pid $SERVERPID"
        kill "$SERVERPID"
    fi
}

trap cleanup EXIT

SITE_REL=${1-./_site}
SITE_ABS=$(readlink -f "$SITE_REL")
echov SITE_ABS
WORKDIR=$(readlink -f ./snapshot-workdir)

if [[ ! -d "$SITE_ABS" ]]; then
    echo "site directory does not exist: $SITE_ABS"
    exit 1
fi

mkdir -p "$WORKDIR"
cd "$WORKDIR"

npm init -y
npm install "github:travisdowns/snap-site" http-server

NODEBIN=./node_modules/.bin

"$NODEBIN/http-server" -p0 "$SITE_ABS" > http.stdout 2> http.stderr &
SERVERPID=$!
echo "Server pid: $SERVERPID"
secs=0
until lsof -P -a -p$SERVERPID -itcp; do
    if [[ $secs -gt 60 ]]; then
        echo "http-server failed to come up after 60s"
        exit 1
    fi
    sleep 1
    secs=$((secs+1))
    echo "Waited ${secs}s so far for server to come up"
done

port=$(lsof -P -a -p$SERVERPID -itcp | grep -o 'TCP \*:[0-9]*' | grep -o '[0-9]*')
echo "http-server seems to be up on port $port"

echo "repo           : ${SNAPSHOT_REPO:=$(git config --get remote.origin.url)}"
if [[ $SNAPSHOT_REPO_AUTH ]]; then
    echo "repo auth      : (set)";
else
    echo "repo auth      : (unset)";
fi
echo "branch         : ${SNAPSHOT_BRANCH:=screenshots}"
echo "Github user    : ${SNAPSHOT_USER-(unset)}"
echo "Github email   : ${SNAPSHOT_EMAIL-(unset)}"
echo "Commit message : ${SNAPSHOT_COMMIT_MSG:=screenshots}"

rm -rf dest-repo
git clone "$SNAPSHOT_REPO" dest-repo --single-branch --branch "$SNAPSHOT_BRANCH"


if [[ "${SKIP_SNAP-0}" -eq 0 ]]; then
    "$(npm bin)/snap-site" --site="$SITE_ABS" --out=dest-repo --excludes=debug.html '--include=**/vector-inc.html'
fi

set -x

gitcmd="git -C dest-repo"

if [[ $SNAPSHOT_USER ]]; then
    $gitcmd config user.name "$SNAPSHOT_USER"
fi
if [[ $SNAPSHOT_EMAIL ]]; then
    $gitcmd config user.email "$SNAPSHOT_EMAIL"
fi
$gitcmd add .
$gitcmd commit --allow-empty -m "$SNAPSHOT_COMMIT_MSG"
$gitcmd push

cd -
# rm -rf "$WORKDIR"

echo "Success"
