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
 A tool for updating a private repo based on a public one (for now only
 git-based)

OPTIONS
 -h, --help                   : This message
 -e, --edit-branches "X"      : Space-separated list of branches to drop to
                                subshell for editing/committing extra edits to
 -d, --deploy-branches "X"    : Space-separated list of deploy-branch(es) to
                                also update, if any (default: ${DEPLOY_BRANCHES:-[none]})
 -p, --push                   : Push each branch to the remote repo as we go
 -i, --interactive            : Make rebase of the deploy-branch interactive
                                (needed for rebasing local commits back in
                                time)
 -b, --version-branch         : Name of branch with upstream version stamp-file
                                in it (default: $VERSION_BRANCH)
 -f, --version-file           : Name of upstream version stamp-file
                                (default: $VERSION_FILE)
 -r, --remote-repo            : The VCS's name for the remote repo (default:
                                $REMOTE_REPO)
 -s, --safe-deploy-branch "X" : Which of the deploy-branches has same upstream
                                base-revision as the non-deploy-branches and is
                                built from merge-commits (the others are built
                                by cherry-picking - default: $SAFE_DEPLOY_BRANCH)

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
        -e|--edit-branches)
            EDIT_BRANCHES="$2"
            shift 2
            continue
            ;;
        -d|--deploy-branches)
            DEPLOY_BRANCHES="$2"
            shift 2
            continue
            ;;
        -p|--push)
            PUSH=1
            shift
            continue
            ;;
        -i|--interactive)
            INTERACTIVE=1
            shift
            continue
            ;;
        -b|--version-branch)
            VERSION_BRANCH="$2"
            shift 2
            continue
            ;;
        -f|--version-file)
            VERSION_FILE="$2"
            shift 2
            continue
            ;;
        -r|--remote-repo)
            REMOTE_REPO="$2"
            shift 2
            continue
            ;;
        -s|--safe-deploy-branch)
            SAFE_DEPLOY_BRANCH="$2"
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

# sanity-checks
_all_in "$DEPLOY_BRANCHES" $POSSIBLE_DEPLOY_BRANCHES || \
    _die_u 'Invalid deploy-branch in "%s". Possible values are "%s". Aborting.\n' \
        "$DEPLOY_BRANCHES" "$POSSIBLE_DEPLOY_BRANCHES"
_in "$SAFE_DEPLOY_BRANCH" $DEPLOY_BRANCHES || \
    _die_u 'Invalid safe-deploy-branch "%s". Possible values are "%s". Aborting.\n' \
        "$SAFE_DEPLOY_BRANCH" "$DEPLOY_BRANCHES"

# make temporary backup just in case (race condition, but should *never* matter...)
tempbackup=`mktemp -u update-private-code-XXXXXX` || \
    _die 'Failed to get a temp-filename for tempbackup directory'
cp -axi . "$tempbackup"

# setup
git checkout "$VERSION_BRANCH"
for _branch in $DEPLOY_BRANCHES; do
    eval "upstream_${_branch}_rev=\`sed -r -n -e '/^$_branch /!b; s/^.* ([^ ]+)/\\1/; p; q' \"$VERSION_FILE\"\`"
done
feature_and_fix_branches=`
    git branch --list --no-color --no-column -r | \
        sed -r -n -e "
            s:^[ \\t]*${REMOTE_REPO}/::;
            t PRINT;
            b;
            : PRINT;
            /^master${DEPLOY_BRANCHES:+|${DEPLOY_BRANCHES// /|}}\$/ b;
            p;
        "
`
_all_in "$EDIT_BRANCHES" $feature_and_fix_branches || \
    _die_u 'Invalid edit-branch in "%s". Possible values are "%s". Aborting.\n' \
        "$EDIT_BRANCHES" "$feature_and_fix_branches"

# update master branch
git checkout master
git pull upstream master
test 0 -eq $PUSH || git push "$REMOTE_REPO" master

# update feature/fix branches
for _branch in $feature_and_fix_branches; do
    git checkout "$_branch"
    git pull -f "$REMOTE_REPO" "$_branch" # must use -f to allow for rebasing
    eval "git rebase \`test 0 -eq \$INTERACTIVE || printf '-i'\` \"\$upstream_${SAFE_DEPLOY_BRANCH}_rev\""
done
for _branch in $EDIT_BRANCHES; do
    git checkout "$_branch"
    _warn 'Dropping to shell for you to add/commit any edits for "%s" branch ("exit" to continue).\n' "$_branch"
    ${SHELL:-/bin/sh}
done
for _branch in $feature_and_fix_branches; do
    test 0 -eq $PUSH || git push -f "$REMOTE_REPO" "$_branch"
done

# update deploy-branches
for _deploybranch in $DEPLOY_BRANCHES; do
    git checkout "$_deploybranch"
    eval "git reset --hard \"\$upstream_${_deploybranch}_rev\""
    for _branch in $feature_and_fix_branches; do
        case "$_deploybranch" in
            "$SAFE_DEPLOY_BRANCH")
                git merge --no-ff --no-edit "$_branch"
                ;;
            *)
                eval "_commits_to_cherrypick=\`
                    {
                        git log --pretty=format:%H \\\"\${upstream_${_deploybranch}_rev}..\$_branch\\\"
                        printf '\\n'
                    } | tac
                \`"
                git cherry-pick -x $_commits_to_cherrypick
                ;;
        esac
    done
    test 0 -eq $PUSH || git push -f "$REMOTE_REPO" "$_deploybranch"
done

# output about tempbackup
_warn 'A tempbackup of the repository (before any changes were made) is at "%s".\nRemember to remove it after a while.\n' \
      "$tempbackup"
