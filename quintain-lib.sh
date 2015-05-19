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

_info() { printf "$@" | sed -e "s/^/${SCRIPTNAME}: /"; }

_warn() { _info "$@" >&2; }

_die() { _warn "$@"; exit 1; }

_die_u() { _usage >&2; _die "$@"; }

_in() {
    _item="$1"
    for _test do
        ! test "x$_item" = "x$_test" || return 0
    done
    return 1
}

_all_in() {
    _items="$1"
    shift
    for _item in "$_items"; do
        _in "$1" "$_item" "$@" || return 1
    done
    return 0
}

_reset_deploybranch_to_remote() {
    # TODO: there must be a more elegant way to achieve this pivot...
    git checkout --detach
    git branch --set-upstream -f "$1" "${2}/$1"
    git checkout --quiet "$1" # --quiet to silence misleading warnings
}

