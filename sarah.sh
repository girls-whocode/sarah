#!/usr/bin/env bash
# shellcheck disable=SC2034 # Unused variables
# shellcheck disable=SC2068 # Double quote array warning
# shellcheck disable=SC2086 # Double quote warning
# shellcheck disable=SC2140 # Word form warning
# shellcheck disable=SC2162 # Read without -r
# shellcheck disable=SC2206 # Word split warning
# shellcheck disable=SC2178 # Array to string warning
# shellcheck disable=SC2102 # Ranges only match single
# shellcheck disable=SC2004 # arithmetic brackets warning
# shellcheck disable=SC2017 # arithmetic precision warning
# shellcheck disable=SC2207 # split array warning
# shellcheck disable=SC2154 # variable referenced but not assigned
# shellcheck disable=SC1003 # info: single quote escape
# shellcheck disable=SC2179 # array append warning
# shellcheck disable=SC2128 # expanding array without index warning

# Declare initial variables
declare app_name app_ver time_left timestamp_start timestamp_end timestamp_input_start timestamp_input_end
declare script_dir time_string prev_screen pause_screen filter input_to_filter curled git_version
declare wkr_user tab backspace sleepy late_update skip_process_draw winches quitting theme_int notifier 
declare wkr_config config_file dir log_level logging log_date log_file saved_stty resized
declare size_error clock tty_width tty_height hex swap_on draw_out esc_character boxes_out last_screen 
declare clock_out update_string sleeping
declare -A log_levels
declare -a saved_key themes menu_options 
declare -a menu_help menu_quit options_array folders
declare -x LC_MESSAGES="C" LC_NUMERIC="C" LC_ALL=""

app_name="SARAH"
script_dir="$(dirname "$0")"
wkr_user=${USER}
wkr_config_dir="${script_dir}/var/conf"
wkr_config="sa.${wkr_user}.conf"
config_file="${config_dir}/${wkr_config}"
log_date=$(date +"%Y-%m-%d")
trace_time=$(date +"%H-%M-%S")
log_file="${script_dir}/var/logs/${log_date}.log"
trace_file="${script_dir}/var/logs/trace-${log_date}-${trace_time}.log"
log_levels=(["die"]=1 ["critical"]=1 ["error"]=2 ["warning"]=3 ["notice"]=4 ["info"]=5 ["debug"]=6)
log_level=${log_levels["debug"]}
logging="warning"
resized=1
swap_on=1
hex="16#"
options_array=(
	"color_theme" 
	"language" 
	"default_editor" 
	"color_output" 
	"username" 
	"identity_file" 
	"port"
	"logging" 
	"update_ms" 
	"draw_clock" 
	"background_update" 
	"error_logging"
	"update_check"
)
sleeping=0 
folders=(
    "${script_dir}/bin"
    "${script_dir}/bin/data/" # the primary application data folder
    "${script_dir}/bin/views/" # the primary application data folder
    "${script_dir}/mods" # modules for expansion
    "${script_dir}/mods/languages" # multilanguage support
    "${script_dir}/var" # the variable folder for storing information
    "${script_dir}/var/logs" # the logs folder
    "${script_dir}/var/cache" # the temporary folder for storing data
    "${script_dir}/var/conf" # the configuration folder
	"${script_dir}/var/conf/themes" # The theme's folder
	"${script_dir}/var/conf/user_themes" # The user's theme's folder
)

# Start default variables------------------------------------------------------------------------------>
# These values are used to create "$HOME/.config/bashtop/bashtop.cfg"
# Any changes made here will be ignored if config file exists
aaa_config() { : ; } #! Do not remove this line!

color_theme="Default"
language="en"
default_editor="nano"
color_output="true"
username="${USER}"
identity_file=""
port="22"
logging="info"
update_ms="2500" # Update time in milliseconds, increases automatically if set below internal loops processing time, recommended 2000 ms or above for better sample times for graphs
draw_clock="%X" # Draw a clock at top of screen, formatting according to strftime, empty string to disable
background_update="true" # Update main ui when menus are showing, set this to false if the menus is flickering too much for comfort
error_logging="true" # Enable error logging to "$HOME/.config/bashtop/error.log", "true" or "false"
update_check="true" # Enable check for new version from github.com/aristocratos/bashtop at start

aaz_config() { : ; } #! Do not remove this line!
#? End default variables-------------------------------------------------------------------------------->

#* Fail if running on unsupported OS
case "$(uname -s)" in
    Linux*)
        system=Linux;;
	*BSD)
        system=BSD;;
	Darwin*)
        system=MacOS;;
	CYGWIN*)
        system=Cygwin;;
	MINGW*)
        system=MinGw;;
	*)
        system="Other";;
esac

if [[ ! $system =~ Linux|MacOS|BSD ]]; then
	echo "This version of ${app_name} does not support $system platform."
	exit 1
fi

# Fail if Bash version is below 4.4
bash_version_major=${BASH_VERSINFO[0]}
bash_version_minor=${BASH_VERSINFO[1]}
if [[ "$bash_version_major" -lt 4 ]] || [[ "$bash_version_major" == 4 && "$bash_version_minor" -lt 4 ]]; then
	echo "ERROR: Bash 4.4 or later is required (you are using Bash $bash_version_major.$bash_version_minor)."
	exit 1
fi

shopt -qu failglob nullglob
shopt -qs extglob globasciiranges globstar

# Do all of the required folders exist? If they don't exist then they need to be created
# Usually some folders will not exist when the directories are empty and using GIT
for folder in "${folders[@]}"; do
    if [ ! -e "${folder}" ]; then
        # This can only be in English because the language file cannot be loaded yet
        mkdir -p "./${folder}" || { echo "Error: Failed to create directory ${folder}"; exit 1; }
    fi
done

# Source all bin, mod, languages and theme files
for folder in "${folders[@]}"; do
    if [[ -d ${folder} ]]; then
        for file in "${folder}"/sarah.*; do
            if [[ -f "${file}" ]]; then
                # This can only be in English because the language file cannot be loaded yet
                source "${file}" || { echo "Error: Failed to source file ${file}"; exit 1; }
            fi
        done
    fi
done

# Start the actual program by calling the config to create or load the user's configuration
config
# Load the appropriate language file.
language_loader
utf8

# Logging and languages are now available
# Start the preflight and set additional vars
preflight

#* Check for UTF-8 locale and set LANG variable if not set
if [[ ! $LANG =~ UTF-8 ]]; then
	if [[ -n $LANG && ${LANG::1} != "C" ]]; then old_lang="${LANG%.*}"; fi
	for set_lang in $(locale -a); do
		if [[ $set_lang =~ utf8|UTF-8 ]]; then
			if [[ -n $old_lang && $set_lang =~ ${old_lang} ]]; then
				declare -x LANG="${set_lang/utf8/UTF-8}"
				set_lang_search="found"
				break
			elif [[ -z $first_lang ]]; then
				first_lang="${set_lang/utf8/UTF-8}"
				set_lang_first="found"
			fi
			if [[ -z $old_lang ]]; then break; fi
		fi
	done
	if [[ $set_lang_search != "found" && $set_lang_first != "found" ]]; then
		echo "ERROR: No UTF-8 locale found!"
		exit 1
	elif [[ $set_lang_search != "found" ]]; then
			declare -x LANG="${first_lang/utf8/UTF-8}"
	fi
	unset old_lang set_lang first_lang set_lang_search set_lang_first
fi

# Call init function
init_
# sarah


# Quit cleanly even if false starts being true...
quit_