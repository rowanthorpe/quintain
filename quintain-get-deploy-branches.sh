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
 A tool for getting the latest deploy-branches from the remote repo (for now
 only git-based...)

OPTIONS
 -h, --help        : This message
 -r, --remote-repo : The VCS's name for the remote repo (default: $REMOTE_REPO)

ARGS
 Which deploy-branch(es) to get.
EOF
}

# sanity-checks
_all_in "$*" $POSSIBLE_DEPLOY_BRANCHES || \
    _die_u 'Invalid deploy-branch in "%s". Possible values are "%s". Aborting.\n' \
        "$DEPLOY_BRANCHES" "$POSSIBLE_DEPLOY_BRANCHES"

# get latest deploy-branches
for _deploybranch do
    _reset_deploybranch_to_remote "$_deploybranch" "$REMOTE_REPO"
done
