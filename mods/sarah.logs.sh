#!/usr/bin/env bash

function die () {
  if [ "${log_level}" -ge 1 ]; then
    local _message="${*} ** ${lang_log_exit} **";
    if [[ -z $lang_log_critical_fail ]]; then lang_log_critical_fail="CRITICAL FAIL"; fi
    echo "[$(LC_ALL=C date +"%Y-%m-%d %H:%M:%S")]:[${wkr_user}]:[${lang_log_critical_fail}]:[${_message}]" >> "${log_file}"
  fi
}

function critical () {
  if [ "${log_level}" -ge 1 ]; then
    local _message="${*}";
    if [[ -z $lang_log_critical ]]; then lang_log_critical="CRITICAL"; fi
    echo "[$(LC_ALL=C date +"%Y-%m-%d %H:%M:%S")]:[${wkr_user}]:[${lang_log_critical}]:[${_message}]" >> "${log_file}"
  fi
}

function error () {
  if [ "${log_level}" -ge 2 ]; then
    local _message="${*}";
    if [[ -z $lang_log_error ]]; then lang_log_error="ERROR"; fi
    echo "[$(LC_ALL=C date +"%Y-%m-%d %H:%M:%S")]:[${wkr_user}]:[${lang_log_error}]:[${_message}]" >> "${log_file}"
  fi
}

function warning () {
  if [ "${log_level}" -ge 3 ]; then
    local _message="${*}";
    if [[ -z $lang_log_warning ]]; then lang_log_warning="WARNING"; fi
    echo "[$(LC_ALL=C date +"%Y-%m-%d %H:%M:%S")]:[${wkr_user}]:[${lang_log_warning}]:[${_message}]" >> "${log_file}"
  fi
}

function notice () {
  if [ "${log_level}" -ge 4 ]; then
    local _message="${*}";
    if [[ -z $lang_log_notice ]]; then lang_log_notice="NOTICE"; fi
    echo "[$(LC_ALL=C date +"%Y-%m-%d %H:%M:%S")]:[${wkr_user}]:[${lang_log_notice}]:[${_message}]" >> "${log_file}"
  fi
}

function info () {
  if [ "${log_level}" -ge 5 ]; then
    _message="${*}";
    if [[ -z $lang_log_info ]]; then lang_log_info="INFO"; fi
    echo "[$(LC_ALL=C date +"%Y-%m-%d %H:%M:%S")]:[${wkr_user}]:[${lang_log_info}]:[${_message}]" >> "${log_file}"
  fi
}

function debug () {
  if [ "${log_level}" -ge 6 ]; then
    _message="${*}";
    if [[ -z $lang_log_debug ]]; then lang_log_debug="DEBUG"; fi
    echo "[$(LC_ALL=C date +"%Y-%m-%d %H:%M:%S")]:[${wkr_user}]:[${lang_log_debug}]:[${_message}]" >> "${log_file}"
  fi
}

function success () {
  if [ "${log_level}" -ge 1 ]; then
    _message="${*}";
    if [[ -z $lang_log_success ]]; then lang_log_success="SUCCESS"; fi
    echo "[$(LC_ALL=C date +"%Y-%m-%d %H:%M:%S")]:[${wkr_user}]:[${lang_log_success}]:[${_message}]" >> "${log_file}"
  fi
}

function log() { 
  printf '%s\n' "$*" >> "${log_file}"
}

function fatal() { 
  error "$@";
  exit 1; 
}

# Shows error message if terminal size is below 80x25
function size_error_msg() {
	local width=$tty_width
	local height=$tty_height
	echo -en "${clear_screen}"
	create_box -full -lc "#EE2020" -title "resize window"
	print -rs -m $((tty_height/2-1)) 2 -fg ${theme[title]} -c -l 11 "Current size: " -bg "#00" -fg "#dd2020" -d 1 -c "${tty_width}x${tty_height}" -rs
	print -d 1 -fg ${theme[title]} -c -l 15 "Need to be atleast:" -bg "#00" -fg "#30dd50" -d 1 -c "80x24" -rs
	while [[ $(${stty} size) == "$tty_height $tty_width" ]]; do ${sleep} 0.2; if [[ -n $quitting ]]; then quit_; fi ; done
}

# Function for reporting error line numbers
function traperr() {
	local match len trap_muted err="${BASH_LINENO[0]}"

	len=$((${#trace_array[@]}))
	if ((len-->=1)); then
		while ((len>=${#trace_array[@]}-2)); do
			if [[ $err == "${trace_array[$((len--))]}" ]]; then ((++match)) ; fi
		done

		if ((match==2 & len != -2)); then return
		elif ((match>=1)); then trap_muted="[MUTED]"
		fi

	fi
	if ((len>100)); then unset 'trace_array[@]'; fi
	trace_array+=("$err")
	error "On line ${err} ${trap_muted}"
}

function logging_level() {
  case "${logging}" in
    debug)
      log_level=6
      ;;
    info)
      log_level=5
      ;;
    notice)
      log_level=4
      ;;
    warning)
      log_level=3
      ;;
    error)
      log_level=2
      ;;
    critical)
      log_level=1
      ;;
    none)
      log_level=0
      ;;
  esac

  export log_level
  debug "${lang_log_level} ${logging}"
}

# Does a log file exist for today
if [ ! -e "${log_file}" ]; then
    touch ${log_file} || { echo "${log_create_error} ${log_file}"; exit 1; }
	log "================================================== ${app_name} LOGGING for ${log_date} =================================================="
else
  log "================================================== ${app_name} new instance =================================================="
fi

info "New instance of ${app_name} version: ${sarah_version} Pid: $$"

#* Set up error logging to file if enabled
if [[ $error_logging == true ]]; then
  set -o errtrace
  trap 'traperr' ERR
  exec 2>>"${log_file}"
  if [[ $1 == "--debug" ]]; then
    exec 19>>"${trace_file}"
    BASH_XTRACEFD=19
    set -x
  fi
else
  exec 2>/dev/null
fi