#!/usr/bin/env bash
(return 0 2>/dev/null) && sourced=1 || sourced=0
[ -n "${HAM_DEBUG:-}" ] && set -o xtrace

if [ -n "${BAUDRATE+x}" ]; then
    echo "You've already sourced this file."
    return 0
fi

set -o errexit
set -o nounset
set -o pipefail

# Only trap if sourced is true
if [ "$sourced" -eq "0" ]; then
    trap '_cleanup $?' EXIT
    trap '_cleanup $?' SIGINT
    trap '_errexit $? ${BASH_SOURCE[0]} $LINENO' ERR
fi

########################################################################
# ANSI escape sequences
#

ANSI_RESET="$(echo -e '\033[0m')"

# Standard ANSI colors
ANSI_RED="$(echo -e '\033[31m')"
ANSI_GREEN="$(echo -e '\033[32m')"
ANSI_YELLOW="$(echo -e '\033[33m')"

# ANSI bright colors using the bold attribute
# (sequences 90-97 are not part of the standard)


# Invalidate color codes if the terminal doesn't support them
if [ "$(tput colors)" -lt 16 ]; then
    for _color in ANSI_RED ANSI_GREEN ANSI_YELLOW ; do
        eval "${_color}=''"
    done
fi
readonly ANSI_RESET ANSI_RED ANSI_GREEN ANSI_YELLOW

########################################################################
# Error handling
#

# Define an empty _cleanup function if it is not already defined.
# This should be redefined in the script that sources this file.
if [ "$(type -t _cleanup)" != "function" ]; then
    _cleanup() {
        debug "Cleaning up... '$1'"
        code="$1"
        # Check error code for a successful exit
        if [ "$code" -ne 0 ]; then
            true # nothing for now
        fi

        if [ "$sourced" -eq "1" ]; then
            return "$code"
        else
            exit "$code"
        fi
    }
fi

boolTest() {
    local _value
    [ "$#" -eq 1 ] || err 'boolTest() requires exactly one argument'
    _value="$*"
    _value="${_value,,}"      # Convert to lowercae
    _value="${_value##*( )}"  # Strip leading whitespace
    _value="${_value%%*( )}"  # Strip trailing whitespace
    case "$_value" in
        1 | true | yes | y | on)
            return 0
            ;;
        0 | false | no | n | off | '')
            return 1
            ;;
        *)
            warn "Invalid boolean value in boolTest(${1})"
            return 1
            ;;
    esac
}

_errexit() {
    set +o errexit
    set +o nounset
    set +o pipefail

    local _i

    >&2 printf "${ANSI_RED}ERROR${ANSI_RESET}: %s:%s: %s\n" "${2}" "${3}" "${4:-Uncaught exception}"

    if boolTest "${HAM_DEBUG_SHELL:-0}";then
        >&2 info "Entering debug shell"
        bash
    fi

    _cleanup "$1"
    if [ "$sourced" -eq "1" ]; then
        return "$1"
    else
        exit "$1"
    fi
}

_fail() {
    _errexit 1 "${BASH_SOURCE[1]}" "${BASH_LINENO[0]}" "$*"
}

err() {
    HAM_DEBUG=
    _errexit 1 "${BASH_SOURCE[1]}" "${BASH_LINENO[0]}" "$*"
}

warn() {
    >&2 printf "${ANSI_YELLOW}WARNING${ANSI_RESET}: %s %s\n" "$*"
}

info() {
    >&2 printf "${ANSI_GREEN}INFO${ANSI_RESET}: %s %s\n" "$*"
}

debug() {
    if boolTest "${HAM_DEBUG:-}"; then
        >&2 printf "${ANSI_RED}DEBUG${ANSI_RESET}: %s\n" "$*"
    fi
}

########################################################################
# Utility functions
#
isLinux() {
    [ "$(uname -s)" = 'Linux' ]
}

isDarwin() {
    [ "$(uname -s)" = 'Darwin' ]
}

isArmv7l() {
    [ "$(uname -m)" = 'armv7l' ]
}

isBBB() {
    grep -qF 'am335x-bone-blackti' /sys/firmware/devicetree/base/compatible &>/dev/null && grep -qF am3356-pru /sys/bus/platform/devices/*.pru/modalias &>/dev/null
}

isDebian10() {
    [ "$OS_RELEASE_PRETTY_NAME" = 'Debian GNU/Linux 10 (buster)' ]
}

capitalize() {
    local string
    string="$1"
    echo "$(tr '[:lower:]' '[:upper:]' <<< "${string:0:1}")""${string:1}"
}
########################################################################

HAM_GET_COMMANDS=(
    'intro'
    'state'
    'logs'
    'diskspace'
    'ramstats'
    'system-logs'
    'system-logs-ham'
)
HAM_CMD_COMMANDS=(
    'shutdown'
    'system_reset'
)

ttyFile='./.tty'
TTY=

DEFAULT_BAUDRATE=9600
readonly DEFAULT_BAUDRATE

STATE_TABLE_FILE='./stateTable.json'
readonly STATE_TABLE_FILE
SIMULATED_PORT=$(2>/dev/null realpath "$HOME/carport" || echo "$HOME/carport")
readonly SIMULATED_PORT
DEFAULT_SCREEN_NAME=hamScreen
readonly DEFAULT_SCREEN_NAME
MSG_READ_DELAY_SEC=0.2
readonly MSG_READ_DELAY_SEC


_getTTYBaudRate() {
    local tty
    tty="$1"
    2>/dev/null stty < "$tty" | grep speed | cut -d" " -f2
}

_setTTYBaudRate() {
    local tty
    local baudrate

    tty="$1"
    baudrate=${2:-"$DEFAULT_BAUDRATE"}
    if isDarwin; then
        stty -f "$tty" "$baudrate"
    else
        stty -F "$tty" "$baudrate"
    fi
}

_configureTTY() {
    local tty
    local baudrate

    tty="$1"
    if isDarwin; then
        stty -f "$tty" "raw"
        stty -f "$tty" "-echo"
    else
        stty -F "$tty" "raw"
        stty -F "$tty" "-echo"
    fi
}

_sendMsg() {
    local cmd
    local tty
    local msgDelay

    cmd="$1"
    tty=${2:-"$TTY"}
    msgDelay=${3:-"$MSG_READ_DELAY_SEC"}

    { sleep 0.02 ; printf "%s" "$cmd" > "$tty" 2>/dev/null ; } &
    _readData "$tty" "$msgDelay"
}

_testConnection() {
    local tty
    tty=${1:-"$TTY"}
    if [ -n "$(_sendMsg '{"get":"intro"}' "$tty" 1)" ]; then
        return 0
    else
        return 1
    fi
}

_getAllTTYs() {
    local -n tl=$1
    local tty

    #mapfile -t tl < <(find /dev -not -group tty -name 'tty*' 2>/dev/null)
    if [ -e "$SIMULATED_PORT" ]; then
        tl=("$SIMULATED_PORT" "${tl[@]}")
    fi
    if [ -e "$ttyFile" ]; then
        read -r tty < "$ttyFile"
        if [ -e "$tty" ]; then
            tl=("$tty" "${tl[@]}")
        fi
    fi
}

_readData() {
    local tty
    local buf
    local msgDelay

    buf=''

    tty=${1:-"$TTY"}
    msgDelay=${2:-"$MSG_READ_DELAY_SEC"}

    # https://linuxcommand.org/lc3_man_pages/readh.html
    # -n nchars
    #   read returns after reading nchars characters rather than waiting for a complete line of input, but honor a delimiter if fewer than nchars characters are read before the delimiter.
    # -N nchars
    #   read returns after reading exactly nchars characters rather than waiting for a complete line of input, unless EOF is encountered or read times out.
    # -t timeout
    #   Cause read to time out and return failure if a complete line of input (or a specified number of characters) is not read within timeout seconds. timeout may be a decimal number with a fractional portion following the decimal point.
    # -d delim
    #   The first character of delim is used to terminate the input line, rather than newline.
    # -r
    #   do not allow backslashes to escape any characters
    # -s
    #   do not echo input coming from a terminal
    # -u fd
    #    read from file descriptor FD instead of the standard input
    read -rs -t "$msgDelay" buf < "$tty"
    echo "$buf"
}

_readJSON() {
    local tty
    local buf
    local failedAttempts

    tty=${1:-"$TTY"}
    buf=''
    failedAttempts=0

    while true; do
        buf+=$(_readData "$tty")
        if jq --exit-status . >/dev/null <<< "$buf"; then
            echo "Valid JSON '$buf'"
            break
        else
            failedAttempts=$((failedAttempts + 1))
        fi

        if [ "$failedAttempts" -gt 3 ]; then
            warn "Failed to read JSON data from '$tty'"
            _readData "$tty"
            buf=''
            failedAttempts=0
        fi
    done

    echo "$buf"
}

_findAndOpenHAMConnection() {
    set +o pipefail
    set +o errexit
    local tty
    local ttyList
    local intro
    local version
    local result
    local baudrate
    local state_table
    local initial_state

    result=
    ttyList=()

    info 'Searching for a HAM...'
    info 'This may take a few minutes'

    _getAllTTYs ttyList
    debug "Ports '${ttyList[*]}'"
    for tty in "${ttyList[@]}"; do
        debug "Checking '$tty'..."

        intro=$(_sendMsg '{"get":"intro"}' "$tty" 2)
        debug "Intro: '$intro'"
        version=$(jq -r '.version' <<< "$intro")
        debug "Version: '$version'"
        if [ -n "$version" ] && [ "$version" != 'null' ]; then
            result="$tty"
            if [ ! -f "$STATE_TABLE_FILE" ]; then
                state_table=$(2>/dev/null jq -r '.state_table' <<< "$intro")
                initial_state=$(2>/dev/null jq -r '.current_state' <<< "$intro")
                cat << EOF > "$STATE_TABLE_FILE"
                    {
                      "stateMachine": {
                        "initial_state": "$initial_state",
                        "state_table": $state_table
                      }
                    }
EOF
            fi
            info "Connected to HAM on '$tty'"
            break
        fi
        debug "Invalid response from '$tty'. Closing connection..."
    done
    set -o pipefail
    set -o errexit

    echo "$result"
}

_generate_cmds() {
    local cmd
    local cleanCmd
    for cmd in "${HAM_GET_COMMANDS[@]}"; do
        cleanCmd=${cmd//-/_} 
        cleanCmd=$(capitalize "$cleanCmd")
        eval "ham.get$cleanCmd() {
            ham.send '{\"get\":\"$cmd\"}'
        }"
    done

    for cmd in "${HAM_CMD_COMMANDS[@]}"; do
        cleanCmd=${cmd//-/_} 
        cleanCmd=$(capitalize "$cleanCmd")
        eval "ham.cmd$cleanCmd() {
            ham.send '{\"command\":\"$cmd\"}'
        }"
    done
}

_generate_events() {
    local events
    local cleanEvent

    events=()
    if [ -f "$STATE_TABLE_FILE" ]; then
        mapfile -t events < <(jq -r '.stateMachine.state_table.any | keys | join("\n")' "$STATE_TABLE_FILE")
    fi
    for event in "${events[@]}"; do
        cleanEvent=${event//-/_} 
        cleanEvent=$(capitalize "$cleanEvent")
        eval "ham.event$cleanEvent() {
            local params
            params=\"\$1\"
            if [ -n \"\$params\" ]; then
                ham.send '{\"event\":\"$event\",\"params\":\"\$params\"}'
            else
                ham.send '{\"event\":\"$event\"}'
            fi
        }"
    done
}

_printAllHAMFunctions() {
    echo "Avaiable HAM functions:"
    if isDarwin; then
       declare -F | grep -oE 'ham\..*' | sort
    else
       declare -F | grep -oP 'ham\..*' | sort
    fi
}

# set -a

ham.send() {
    local cmd
    cmd="$1"

    if [ -z "$TTY" ]; then
        warn "Checking connection to HAM..."
        TTY=$(_findAndOpenHAMConnection)
        debug "Found '$TTY'"
        if [ -z "$TTY" ]; then
            err "Could not find a valid HAM connection"
        else
            echo "$TTY" > "$ttyFile"
        fi
    fi
    _sendMsg "$cmd"
}

ham.setState() {
    local state
    state="$1"
    ham.send '{"set":"'"${state}"'"}'
}

ham.sendConfig() {
    local config
    local cmd

    config=${1:-$(cat "$STATE_TABLE_FILE")}
    cmd='{"config":'"${config}"'}'

    _sendMsg "$cmd" "$TTY" 7
}

# set +a

if [ "$sourced" -eq "0" ]; then
    info 'Cycling motor'
    ham.send '{"event":"start-test-motor-cycle-reset"}'
    info
    info 'Close session with: screen -X -rmS '"$DEFAULT_SCREEN_NAME" 'quit'
else
    msg=$(cat <<-'EOF'
        You will need to be running bash version >= 4.0 to source this script
        Execute:
        declare -p BASH_VERSION
        to see which version you are running.
        <TODO: Explain how to change it in terminal settings>
EOF
)
    if [ "${BASH_VERSION%%.*}" -lt 4 ]; then
        echo "$msg"
        return 0
    fi
    set +o errexit
    set +o nounset
    set +o pipefail
   _generate_cmds
   _generate_events
   _printAllHAMFunctions
fi
