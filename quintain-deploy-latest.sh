#!/bin/sh

# © Copyright 2015 Rowan Thorpe
#
# This file is part of Quintain
#
# Quintain is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Quintain is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Quintain. If not, see <http://www.gnu.org/licenses/>.

#TODO: add more verbose/explicit error-handling in places (although
#      "set -e" should save us at all points, it isn't very instructive)

set -e

# vars
SCRIPTNAME="$(basename "$0")"
SCRIPTDIR="$(dirname "$0")"
LIB_FILE="${SCRIPTDIR}/quintain-lib.sh"
CONFIG_FILE="${SCRIPTDIR}/quintain.conf"
REMOTE_REPO='origin'
POSSIBLE_DEPLOY_BRANCHES='production staging testing'
DEPLOY_BRANCHES='production staging'
SAFE_DEPLOY_BRANCH='production'
VERSION_BRANCH='version-base-stampfile'
VERSION_FILE='PRESENT_VERSION_BASE'
PUSH=0
INTERACTIVE=0
KEEP_MAINT_MODE=0
FQDN_HASH=''
EDIT_BRANCHES=''
BASE_DIR=''
REPO_DIR=''
REPO_AUX_DIR=''
MAINT_MODE_FILE=''
RESTART_SERVERS=''
! test -e "$CONFIG_FILE" || . "$CONFIG_FILE"

# functions
. "$LIB_FILE"
_usage() {
    cat <<EOF
Usage: $SCRIPTNAME [OPTIONS] [--] [ARGS]

DESCRIPTION
 A tool for deploying code to production/staging servers (for now only
 git-based, on debian-based servers...)

OPTIONS
 -h, --help                : This message
 -k, --keep-maint-mode     : Don't remove maintenance-mode flagfile after pivot
 -M, --maint-mode-file "X" : Name of the maintenance-mode flagfile to use for
                             pivot, if any (default: ${MAINT_MODE_FILE:-[none]})
 -R, --restart-servers "X" : Space-separated list of servers to restart after
                             deployment, if any (default: ${RESTART_SERVERS:-[none]})
 -f, --fqdn-hash "X"       : A pseudo-hash of FQDNs of server to match (e.g.
                             "production:aa.com staging:bb.org", default: ${FQDN_HASH:-[none]})
 -b, --base-dir "X"        : The base dirpath for the app (default: ${BASE_DIR:-[none]})
                             - this will be a symlink to a commit-dir of the
                             form /opt/myapp-[COMMIT_HASH]
 -r, --repo-dir "X"        : The path to the repo (default: ${REPO_DIR:-[none]})
 -a, --repo-aux-dir "X"    : The path to an auxiliary repo, for things you want
                             to keep separate like gitignored files from the
                             main repo, private data, etc (default: ${REPO_AUX_DIR:-[none]})

ARGS
 For now there are no non-opt args.
EOF
}

# getopts/args
while test $# -ne 0; do
    case "$1" in
        -h|--help)
            _usage
            exit 0
            ;;
        -k|--keep-maint-mode)
            KEEP_MAINT_MODE=1
            shift
            continue
            ;;
        -M|--maint-mode-file)
            MAINT_MODE_FILE="$2"
            shift 2
            continue
            ;;
        -R|--restart-servers)
            RESTART_SERVERS="$2"
            shift 2
            continue
            ;;
        -f|--fqdn-hash)
            FQDN_HASH="$2"
            shift 2
            continue
            ;;
        -b|--base-dir)
            BASE_DIR="$2"
            shift 2
            continue
            ;;
        -r|--repo-dir)
            REPO_DIR="$2"
            shift 2
            continue
            ;;
        -a|--repo-aux-dir)
            REPO_AUX_DIR="$2"
            shift 2
            continue
            ;;
        --)
            shift
            break
            ;;
        -*)
            _die_u 'Unknown option "%s". Aborting.\n' "$1"
            ;;
        *)
            break
            ;;
    esac
done
test 0 -eq $# || _die_u '* There should be no non-opt args, but there are %d. Aborting.\n' $#

# opt-deps and sanity-check
if test 1 -eq $KEEP_MAINT_FILE; then
    if test -n "$MAINT_MODE_FILE"; then
        RESTART_SERVERS=''
    else
        _die_u 'Conflicting optflags used. Aborting.\n'
    fi
fi

# main

hostname="$(hostname -f)"
deploy_branch=''
for _keyval in $FQDN_HASH; do
    _branch="${_keyval%%:*}"
    _fqdn="${_keyval#*:}"
    if test "x$hostname" = "x$_fqdn"; then
        deploy_branch="$_branch"
        break
    fi
done
test -n "$deploy_branch" || _die 'Failed to find the FQDN "%s" in the FQDN hash "%s". Aborting.\n' "$hostname" "$FQDN_HASH"

cd "$REPO_DIR"
git fetch origin
_reset_deploybranch_to_remote "$deploy_branch" "$REMOTE_REPO"
git submodule init
git submodule update
top_commit=`git log --pretty=format:%H HEAD | head -n 1`
test -n "$top_commit" || \
    _die 'Couldn'\''t get a commit-hash from the git log. Aborting.\n'
if test -n "$REPO_AUX_DIR"; then
    cd "$REPO_AUX_DIR"
    git fetch "$REMOTE_REPO"
    _reset_deploybranch_to_remote "$deploy_branch" "$REMOTE_REPO"
fi
! test -e "${BASE_DIR}-$top_commit" || \
    _die 'Destination directory "%s-%s" already exists! Aborting.\n' "$BASE_DIR" "$top_commit"
mkdir "${BASE_DIR}-$top_commit"
#NB: If the basedir ever includes dotfiles other than VCS ones the below line should be updated
#    accordingly
cp -axiv "$REPO_DIR"/* "${BASE_DIR}-$top_commit"
if test -n "$REPO_AUX_DIR"; then
    for _file in `find "$REPO_AUX_DIR" ! -path '*/.travis.yml' ! -path '*/.git*' -type f`; do
        _dir="`dirname "$_file" | sed -e "1 s:^${REPO_AUX_DIR}:${BASE_DIR}-$top_commit:"`"
        mkdir -p "$_dir"
        cp -axiv "$_file" "$_dir"
    done
fi

{
    cat <<EOF
The below should only show expected changes (uses "less", press q to exit)
==========================================================================
EOF
    diff -Naur --exclude=.travis.yml --exclude=.git --exclude=.gitignore --exclude=.gitmodules \
        "$BASE_DIR" "${BASE_DIR}-$top_commit"
} | less -S

_warn 'If the diff was OK (or even empty), type "yes" to pivot to the new version\n'
read temp

if test yes = "$temp"; then
    test -h "$BASE_DIR" || \
        _die '"%s" should be a symlink but isn'\''t. Aborting.\n' "$BASE_DIR"
    if test 1 -eq $USE_MAINT_MODE; then
        touch "${BASE_DIR}-${top_commit}/$MAINT_MODE_FILE"
        touch "${BASE_DIR}/$MAINT_MODE_FILE"
    fi
    ln -sfnv "${BASE_DIR}-${top_commit}" "$BASE_DIR"
    for _restart in $RESTART_SERVERS; do
        service "$_restart" restart
    done
    test 0 -eq $USE_MAINT_MODE || test 1 -eq $KEEP_MAINT_MODE || \
        rm -fv "${BASE_DIR}/$MAINT_MODE_FILE"
else
    _die 'NOT pivoting to the new directory "%s". Symlink "%s" still points to "%s".\nDelete the new version if you don'\''t want it. Aborting.\n' \
        "${BASE_DIR}-$top_commit" "$BASE_DIR" "$(readlink -e "$BASE_DIR")"
fi
