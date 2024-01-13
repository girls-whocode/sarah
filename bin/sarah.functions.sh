#!/usr/bin/env bash
# shellcheck disable=SC2034 #Unused variables

function preflight() {
    # Set correct names for GNU tools depending on OS
    if [[ $system != "Linux" ]]; then
        debug "Linux not detected, using GNU tools"
        tool_prefix="g";
    fi

    for tool in "dd" "df" "stty" "tail" "realpath" "wc" "rm" "mv" "sleep" "stdbuf" "mkfifo" "date" "kill" "sed"; do
        declare -n set_tool="${tool}"
        set_tool="${tool_prefix}${tool}"
        debug "Setting ${tool} to ${set_tool}"
    done

    if ! command -v ${dd} >/dev/null 2>&1; then
        error "${gnu_error}"
        echo "${gnu_error}"
        exit 1
    elif ! command -v ${sed} >/dev/null 2>&1; then
        error "${gnu_sed_error}"
        echo "${gnu_sed_error}"
        exit 1
    fi

    read tty_height tty_width < <(${stty} size)
    debug "Terminal size: ${tty_height}x${tty_width}"
    printf -v esc_character "\u1b"
    printf -v tab "\u09"
    printf -v backspace "\u7F" # Backspace set to DELETE
    printf -v backspace_real "\u08" # Real backspace
    #printf -v enter_key "\uA"
    printf -v enter_key "\uD"
    printf -v ctrl_c "\u03"
    printf -v ctrl_z "\u1A"

    hide_cursor='\033[?25l'		# Hide terminal cursor
    show_cursor='\033[?25h'		# Show terminal cursor
    alt_screen='\033[?1049h'	# Switch to alternate screen
    normal_screen='\033[?1049l'	# Switch to normal screen
    clear_screen='\033[2J'		# Clear screen

    #* Symbols for create_box function
    box[single_hor_line]="─"
    box[single_vert_line]="│"
    box[single_left_corner_up]="┌"
    box[single_right_corner_up]="┐"
    box[single_left_corner_down]="└"
    box[single_right_corner_down]="┘"
    box[single_title_left]="├"
    box[single_title_right]="┤"

    box[double_hor_line]="═"
    box[double_vert_line]="║"
    box[double_left_corner_up]="╔"
    box[double_right_corner_up]="╗"
    box[double_left_corner_down]="╚"
    box[double_right_corner_down]="╝"
    box[double_title_left]="╟"
    box[double_title_right]="╢"

    #* Set up traps for ctrl-c, soft kill, window resize, ctrl-z and resume from ctrl-z
    trap 'quitting=1; time_left=0' SIGINT SIGQUIT SIGTERM
    trap 'resized=1; time_left=0' SIGWINCH
    trap 'sleepy=1; time_left=0' SIGTSTP
    trap 'resume_' SIGCONT
    trap 'failed_pipe=1; time_left=0' PIPE

    # If using bash version 5, set timestamps with EPOCHREALTIME variable
    if [[ -n $EPOCHREALTIME ]]; then
        get_ms() { #? Set given variable to current epoch millisecond with EPOCHREALTIME varialble
            local -n ms_out=$1
            ms_out=$((${EPOCHREALTIME/[.,]/}/1000))
        }

    # Else use date command
    else
        get_ms() { #? Set given variable to current epoch millisecond with date command
            local -n ms_out=$1
            ms_out=""
            read ms_out < <(${date} +%s%3N)
        }
    fi

    debug "Preflight complete"
    #* If we have been sourced by another shell, quit. Allows sourcing only function definition.
    [[ "${#BASH_SOURCE[@]}" -gt 1 ]] && { return 0; }
}

function sleep_() { #? Restore terminal options, stop and send to background if caught SIGTSTP (ctrl+z)
	echo -en "${clear_screen}${normal_screen}${show_cursor}"
	${stty} "${saved_stty}"
	echo -en "\033]0;\a"
	${kill} -s SIGSTOP $$
}

function resume_() { #? Set terminal options and resume if caught SIGCONT ('fg' from terminal)
	sleepy=0
	echo -en "${alt_screen}${hide_cursor}${clear_screen}"
	echo -en "\033]0;${TERMINAL_TITLE} ${app_name}\a"
	${stty} -echo

	if [[ -n $pause_screen ]]; then
		echo -en "$pause_screen"
	else
		echo -en "${boxes_out}${proc_det}${last_screen}${mem_out}${proc_misc}${proc_misc2}${update_string}${clock_out}"
	fi
}

# Pause input and draw a darkened version of main ui
function pause_() {
	local pause_out ext_var
	if [[ -n $1 && $1 != "off" ]]; then local -n pause_out=${1}; ext_var=1; fi
	if [[ $1 != "off" ]]; then
		prev_screen="${boxes_out}${proc_det}${last_screen}${net_misc}${mem_out}${detail_graph[*]}${proc_out}${proc_misc}${proc_misc2}${update_string}${clock_out}"
		if [[ -n $skip_process_draw ]]; then
			prev_screen+="${proc_out}"
			unset skip_process_draw proc_out
		fi

		unset pause_screen
		print -v pause_screen -rs -b -fg ${theme[inactive_fg]}
		pause_screen+="${theme[main_bg]}m$(${sed} -E 's/\\e\[[0-9;\-]*m//g' <<< "${prev_screen}")\e[0m" #\e[1;38;5;236

		if [[ -z $ext_var ]]; then echo -en "${pause_screen}"
		else pause_out="${pause_screen}"; fi

	elif [[ $1 == "off" ]]; then
		echo -en "${prev_screen}"
		unset pause_screen prev_screen
	fi
}

function unpause_() { #? Unpause
	pause_ off
}

function sort_array_int() {	#? Copy and sort an array of integers from largest to smallest value, usage: sort_array_int "input array" "output array"
	#* Return if given array has no values
	if [[ -z ${!1} ]]; then return; fi
	local start_n search_n tmp_array

	#* Create pointers to arrays
	local -n in_arr="$1"
	local -n out_arr="$2"

	#* Create local copy of array
	local array=("${in_arr[@]}")

	#* Start sorting
	for ((start_n=0;start_n<=${#array[@]}-1;++start_n)); do
		for ((search_n=start_n+1;search_n<=${#array[@]}-1;++search_n)); do
			if ((array[start_n]<array[search_n])); then
				tmp_array=${array[start_n]}
				array[start_n]=${array[search_n]}
				array[search_n]=$tmp_array
			fi
		done
	done

	#* Write the sorted array to output array
	out_arr=("${array[@]}")
}

function split() {
   # Usage: split "string" "delimiter"
   IFS=$'\n' read -d "" -ra arr <<< "${1//$2/$'\n'}"
   echo "${arr[@]}"
}

# Function: subscript
# Description: Converts a given integer into subscript symbols.
# Parameters:
#   $1 - The integer to be converted.
# Returns:
#   The converted integer in subscript symbols.
# Usage: subscript "integer"
function subscript() {
	subscript=("₀" "₁" "₂" "₃" "₄" "₅" "₆" "₇" "₈" "₉")

	local i out int=$1
	for((i=0;i<${#int};i++)); do
		out="${out}${subscript[${int:$i:1}]}"
	done
	echo -n "${out}"
}

# Function: spaces
# Description: Prints back spaces.
# Parameters:
#   $1 - The number of spaces to print.
# Returns:
#   Nothing.
# Usage: spaces "number of spaces"
function spaces() { 
	printf "%${1}s" ""
}

# Function: cur_pos
# Description: Get cursor postion, argument "line" prints current line, argument "col" prints current column, no argument prints both in format "line column"
# Parameters:
#   $1 - "line" or "col" or nothing
# Returns:
#   Current line, column or both.
# Usage: cur_pos "line" or cur_pos "col" or cur_pos
function cur_pos() {
	local line col
	IFS=';' read -sdR -p $'\E[6n' line col
	if [[ -z $1 || $1 == "line" ]]; then echo -n "${line#*[}${1:-" "}"; fi
	if [[ -z $1 || $1 == "col" ]]; then echo -n "$col"; fi
}

# Function: init
# Description: Initialize sarah
# Parameters:
#   $1 - "reinit" if sarah has already been initialized
# Returns:
#   Nothing.
# Usage: init "reinit"
function init_() {
	local banner_out_up

	if [[ -z $1 ]]; then
		local i stx=0

		# Set terminal options, save and clear screen
		saved_stty="$(${stty} -g)"
		echo -en "${alt_screen}${hide_cursor}${clear_screen}"
		echo -en "\033]0;${TERMINAL_TITLE} ${app_name}\a"
		${stty} -echo

		# Wait for resize if terminal size is smaller then 80x24
		if (($tty_width<80 | $tty_height<24)); then 
			info "Screen too small, waiting for resize"
			resized; 
			echo -en "${clear_screen}"; 
		fi

		#* Draw banner to banner array
		local letter b_color banner_line y=0
		local -a banner_out

		for banner_line in "${banner[@]}"; do
			#* Read banner array letter by letter to set correct color for filled vs outline characters
			while read -rN1 letter; do
				if [[ $letter == "█" ]]; then 
					b_color="${banner_colors[$y]}"
				else 
					b_color="#$((80-y*6))"; 
				fi
				
				if [[ $letter == " " ]]; then
					print -v banner_out[y] -r 1
				else
					print -v banner_out[y] -fg ${b_color} "${letter}"
				fi
			done <<<"$banner_line"
			((++y))
		done
		banner=("${banner_out[@]}")

		#* Draw banner to screen and show status while running init
		draw_banner $((tty_height/2-10))
		debug "${app_name} first run initialized"
	else
		debug "${app_name} reinitialized"
	fi

	if [[ -n $1 ]]; then 
		local i stx=1; 
		print -bg "#00" -fg "#30ff50" -r 1 -t "√";
		debug "${1} reinitialized"
	fi

	#* Check if "curl" command is available, if not, disable update check and theme downloads
	if command -v curl >/dev/null 2>&1; then 
		debug "Curl found, enabling update check and theme downloads"
		curled=1
	else 
		debug "Curl not found, disabling update check and theme downloads"
		unset curled; 
	fi

	#* Check if "notify-send" command is available, if not, disable update notifier
	if [[ -n $curled ]] && command -v notify-send >/dev/null 2>&1; then 
		debug "Notify-send found, enabling update notifier"
		notifier=1; 
	else
		debug "Notify-send not found, disabling update notifier"
		unset notifier; 
	fi

	#* Check if newer version of SARAH is available from https://github.com/girls-whocode/sarah
	if [[ -n $curled && $update_check == "true" ]]; then
		debug "Checking for updates"
		print -bg "#00" -fg "#30ff50" -r 1 -t "√"
		print -m $(( (tty_height/2-3)+stx++ )) 0 -bg "#00" -fg "#cc" -c -b "${lang_update_check}"
		if ! get_value -v git_version -ss "$(curl -m 4 --raw -r 0-5000 https://raw.githubusercontent.com/girls-whocode/sarah/main/bin/data/sarah.version.sh 2>/dev/null)" -k "sarah_version=" -r "[^0-9.]"; then 
			debug "Failed to get git_version from github"
			unset git_version; 
		fi
	fi

	#* Add update notification to banner if new version is available

	print -v banner_out_up -rs -fg "#cc" -b "← esc"
	if [[ -n $git_version && $git_version != "$version" ]]; then
		info "New version available: ${git_version}"
		print -v banner_out_up -rs -fg "#80cc80" -r 15 "[${git_version} ${lang_update_available}]" -r $((9-${#git_version}))
		if [[ -n $notifier ]]; then
			debug "Sending update notification"
			notify-send -u normal\
			"${lang_sarah_update}" "${lang_sarah_update_msg} ${version}\n${lang_new_update}: ${git_version}\n${lang_download} https://github.com/girls-whocode/sarah"\
			-i face-glasses -t 10000
		fi
	else
		info "You are running the latest version"
		print -v banner_out_up -r 37
	fi

	print -v banner_out_up -fg "#cc" -i -b "${lang_version}: ${version}" -rs
	banner+=("${banner_out_up}")

	# Set up internals for quick processes sorting switching
	for ((i=0;i<${#sorting[@]};i++)); do
		if [[ ${sorting[i]} == "${proc_sorting}" ]]; then
			debug "Sorting set to ${proc_sorting}"
			proc[sorting_int]=$i
			break
		fi
	done

	#* Draw first screen
	print -bg "#00" -fg "#30ff50" -r 1 -t "√"
	print -m $(( (tty_height/2-3)+stx++ )) 0 -bg "#00" -fg "#cc" -c -b "${lang_draw_screen}"

	last_screen="${draw_out}"
	print -bg "#00" -fg "#30ff50" -r 1 -t "√" -rs
	sleep 0.5
	draw_clock
	echo -en "${clear_screen}${draw_out}${proc_out}${clock_out}"
	resized=0
	unset draw_out
}

function old_init_() {
	local main_bg="" main_fg="#cc" title="#ee" hi_fg="#90" inactive_fg="#40" cpu_box="#3d7b46" mem_box="#8a882e" net_box="#423ba5" proc_box="#923535" proc_misc="#0de756" selected_bg="#7e2626" selected_fg="#ee"
	local temp_start="#4897d4" temp_mid="#5474e8" temp_end="#ff40b6" cpu_start="#50f095" cpu_mid="#f2e266" cpu_end="#fa1e1e" div_line="#30"
	local free_start="#223014" free_mid="#b5e685" free_end="#dcff85" cached_start="#0b1a29" cached_mid="#74e6fc" cached_end="#26c5ff" available_start="#292107" available_mid="#ffd77a" available_end="#ffb814"
	local used_start="#3b1f1c" used_mid="#d9626d" used_end="#ff4769" download_start="#231a63" download_mid="#4f43a3" download_end="#b0a9de" upload_start="#510554" upload_mid="#7d4180" upload_end="#dcafde"
	local hex2rgb color_name array_name this_color main_fg_dec sourced theme_unset
	local -i i y
	local -A rgb
	local -a dec_test
	local -a convert_color=("main_bg" "temp_start" "temp_mid" "temp_end" "cpu_start" "cpu_mid" "cpu_end" "upload_start" "upload_mid" "upload_end" "download_start" "download_mid" "download_end" "used_start" "used_mid" "used_end" "available_start" "available_mid" "available_end" "cached_start" "cached_mid" "cached_end" "free_start" "free_mid" "free_end" "proc_misc" "main_fg_dec")
	local -a set_color=("main_fg" "title" "hi_fg" "div_line" "inactive_fg" "selected_fg" "selected_bg" "cpu_box" "mem_box" "net_box" "proc_box")

	#* Calculate sizes of boxes
	print -bg "#00" -fg "#30ff50" -r 1 -t "√"
	print -m $(( (tty_height/2-3)+stx++ )) 0 -bg "#00" -fg "#cc" -c -b "${lang_size_calc}"
	# calc_sizes

	#* Get theme and set colors
	print -bg "#00" -fg "#30ff50" -r 1 -t "√"
	print -m $(( (tty_height/2-3)+stx++ )) 0 -bg "#00" -fg "#cc" -c -b "${lang_color_generate}"

	for theme_unset in ${!theme[@]}; do
		unset 'theme[${theme_unset}]'
	done

	#* Check if theme set in config exists and source it if it does
	if [[ -n ${color_theme} && ${color_theme} != "Default" && ${color_theme} =~ (themes/)|(user_themes/) && -e "${config_dir}/${color_theme%.theme}.theme" ]]; then
		# shellcheck source=/dev/null
		source "${config_dir}/${color_theme%.theme}.theme"
		sourced=1
	else
		color_theme="Default"
	fi

	# main_fg_dec="${theme[main_fg]:-$main_fg}"
	# theme[main_fg_dec]="${main_fg_dec}"

	#* Convert colors for graphs and meters from rgb hexadecimal to rgb decimal if needed
	for color_name in ${convert_color[@]}; do
		if [[ -n $sourced ]]; then hex2rgb="${theme[${color_name}]}"
		else hex2rgb="${!color_name}"; fi

		hex2rgb=${hex2rgb//#/}

		if [[ ${#hex2rgb} == 6 ]] && is_hex "$hex2rgb"; then hex2rgb="$((${hex}${hex2rgb:0:2})) $((${hex}${hex2rgb:2:2})) $((${hex}${hex2rgb:4:2}))"
		elif [[ ${#hex2rgb} == 2 ]] && is_hex "$hex2rgb"; then hex2rgb="$((${hex}${hex2rgb:0:2})) $((${hex}${hex2rgb:0:2})) $((${hex}${hex2rgb:0:2}))"
		else
			dec_test=(${hex2rgb})
			if [[ ${#dec_test[@]} -eq 3 ]] && is_int "${dec_test[@]}"; then hex2rgb="${dec_test[*]}"
			else unset hex2rgb; fi
		fi

		# theme[${color_name}]="${hex2rgb}"
	done

	#* Set background color if set, otherwise use terminal default
	if [[ -n ${theme[main_bg]} ]]; then theme[main_bg_dec]="${theme[main_bg]}"; theme[main_bg]=";48;2;${theme[main_bg]// /;}"; fi

	#* Set colors from theme file if found and valid hexadecimal or integers, otherwise use default values
	# for color_name in "${set_color[@]}"; do
	# 	if [[ -z ${theme[$color_name]} ]] || ! is_hex "${theme[$color_name]}" && ! is_int "${theme[$color_name]}"; then theme[${color_name}]="${!color_name}"; fi
	# done

	# box[cpu_color]="${theme[cpu_box]}"
	# box[mem_color]="${theme[mem_box]}"
	# box[net_color]="${theme[net_box]}"
	# box[processes_color]="${theme[proc_box]}"

	# # * Create color arrays from one, two or three color gradient, 100 values in each
	# for array_name in "temp" "cpu" "upload" "download" "used" "available" "cached" "free"; do
	# 	local -n color_array="color_${array_name}_graph"
	# 	local -a rgb_start=(${theme[${array_name}_start]}) rgb_mid=(${theme[${array_name}_mid]}) rgb_end=(${theme[${array_name}_end]})
	# 	local pf_calc middle=1

	# 	rgb[red]=${rgb_start[0]}; rgb[green]=${rgb_start[1]}; rgb[blue]=${rgb_start[2]}

	# 	if [[ -z ${rgb_mid[*]} ]] && ((rgb_end[0]+rgb_end[1]+rgb_end[2]>rgb_start[0]+rgb_start[1]+rgb_start[2])); then
	# 		rgb_mid=( $(( rgb_start[0]+( (rgb_end[0]-rgb_start[0])/2) )) $((rgb_start[1]+( (rgb_end[1]-rgb_start[1])/2) )) $((rgb_start[2]+( (rgb_end[2]-rgb_start[2])/2) )) )
	# 	elif [[ -z ${rgb_mid[*]} ]]; then
	# 		rgb_mid=( $(( rgb_end[0]+( (rgb_start[0]-rgb_end[0])/2) )) $(( rgb_end[1]+( (rgb_start[1]-rgb_end[1])/2) )) $(( rgb_end[2]+( (rgb_start[2]-rgb_end[2])/2) )) )
	# 	fi

	# 	for((i=0;i<=100;i++,y=0)); do
	# 		if [[ -n ${rgb_end[*]} ]]; then
	# 			for this_color in "red" "green" "blue"; do
	# 				if ((i==50)); then rgb_start[y]=${rgb[$this_color]}; fi

	# 				if ((middle==1 & rgb[$this_color]<rgb_mid[y])); then
	# 					printf -v pf_calc "%.0f" "$(( i*( (rgb_mid[y]-rgb_start[y])*100/50*100) ))e-4"

	# 				elif ((middle==1 & rgb[$this_color]>rgb_mid[y])); then
	# 					printf -v pf_calc "%.0f" "-$(( i*( (rgb_start[y]-rgb_mid[y])*100/50*100) ))e-4"

	# 				elif ((middle==0 & rgb[$this_color]<rgb_end[y])); then
	# 					printf -v pf_calc "%.0f" "$(( (i-50)*( (rgb_end[y]-rgb_start[y])*100/50*100) ))e-4"

	# 				elif ((middle==0 & rgb[$this_color]>rgb_end[y])); then
	# 					printf -v pf_calc "%.0f" "-$(( (i-50)*( (rgb_start[y]-rgb_end[y])*100/50*100) ))e-4"

	# 				else
	# 					pf_calc=0
	# 				fi

	# 				rgb[$this_color]=$((rgb_start[y]+pf_calc))
	# 				if ((rgb[$this_color]<0)); then rgb[$this_color]=0
	# 				elif ((rgb[$this_color]>255)); then rgb[$this_color]=255; fi

	# 				y+=1
	# 				if ((i==49 & y==3 & middle==1)); then middle=0; fi
	# 			done
	# 		fi
	# 		color_array[i]="${rgb[red]} ${rgb[green]} ${rgb[blue]}"
	# 	done
	# done
}

function color_init_() { #? Check for theme file and set colors
	local main_bg="" main_fg="#cc" title="#ee" hi_fg="#90" inactive_fg="#40" cpu_box="#3d7b46" mem_box="#8a882e" net_box="#423ba5" proc_box="#923535" proc_misc="#0de756" selected_bg="#7e2626" selected_fg="#ee"
	local temp_start="#4897d4" temp_mid="#5474e8" temp_end="#ff40b6" cpu_start="#50f095" cpu_mid="#f2e266" cpu_end="#fa1e1e" div_line="#30"
	local free_start="#223014" free_mid="#b5e685" free_end="#dcff85" cached_start="#0b1a29" cached_mid="#74e6fc" cached_end="#26c5ff" available_start="#292107" available_mid="#ffd77a" available_end="#ffb814"
	local used_start="#3b1f1c" used_mid="#d9626d" used_end="#ff4769" download_start="#231a63" download_mid="#4f43a3" download_end="#b0a9de" upload_start="#510554" upload_mid="#7d4180" upload_end="#dcafde"
	local hex2rgb color_name array_name this_color main_fg_dec sourced theme_unset
	local -i i y
	local -A rgb
	local -a dec_test
	local -a convert_color=("main_bg" "temp_start" "temp_mid" "temp_end" "cpu_start" "cpu_mid" "cpu_end" "upload_start" "upload_mid" "upload_end" "download_start" "download_mid" "download_end" "used_start" "used_mid" "used_end" "available_start" "available_mid" "available_end" "cached_start" "cached_mid" "cached_end" "free_start" "free_mid" "free_end" "proc_misc" "main_fg_dec")
	local -a set_color=("main_fg" "title" "hi_fg" "div_line" "inactive_fg" "selected_fg" "selected_bg" "cpu_box" "mem_box" "net_box" "proc_box")

	for theme_unset in ${!theme[@]}; do
		unset 'theme[${theme_unset}]'
	done

	#* Check if theme set in config exists and source it if it does
	if [[ -n ${color_theme} && ${color_theme} != "Default" && ${color_theme} =~ (themes/)|(user_themes/) && -e "${config_dir}/${color_theme%.theme}.theme" ]]; then
		# shellcheck source=/dev/null
		source "${config_dir}/${color_theme%.theme}.theme"
		sourced=1
	else
		color_theme="Default"
	fi

	main_fg_dec="${theme[main_fg]:-$main_fg}"
	theme[main_fg_dec]="${main_fg_dec}"

	#* Convert colors for graphs and meters from rgb hexadecimal to rgb decimal if needed
	for color_name in ${convert_color[@]}; do
		if [[ -n $sourced ]]; then hex2rgb="${theme[${color_name}]}"
		else hex2rgb="${!color_name}"; fi

		hex2rgb=${hex2rgb//#/}

		if [[ ${#hex2rgb} == 6 ]] && is_hex "$hex2rgb"; then hex2rgb="$((${hex}${hex2rgb:0:2})) $((${hex}${hex2rgb:2:2})) $((${hex}${hex2rgb:4:2}))"
		elif [[ ${#hex2rgb} == 2 ]] && is_hex "$hex2rgb"; then hex2rgb="$((${hex}${hex2rgb:0:2})) $((${hex}${hex2rgb:0:2})) $((${hex}${hex2rgb:0:2}))"
		else
			dec_test=(${hex2rgb})
			if [[ ${#dec_test[@]} -eq 3 ]] && is_int "${dec_test[@]}"; then hex2rgb="${dec_test[*]}"
			else unset hex2rgb; fi
		fi

		theme[${color_name}]="${hex2rgb}"
	done

	#* Set background color if set, otherwise use terminal default
	if [[ -n ${theme[main_bg]} ]]; then theme[main_bg_dec]="${theme[main_bg]}"; theme[main_bg]=";48;2;${theme[main_bg]// /;}"; fi

	#* Set colors from theme file if found and valid hexadecimal or integers, otherwise use default values
	for color_name in "${set_color[@]}"; do
		if [[ -z ${theme[$color_name]} ]] || ! is_hex "${theme[$color_name]}" && ! is_int "${theme[$color_name]}"; then theme[${color_name}]="${!color_name}"; fi
	done

	box[cpu_color]="${theme[cpu_box]}"
	box[mem_color]="${theme[mem_box]}"
	box[net_color]="${theme[net_box]}"
	box[processes_color]="${theme[proc_box]}"

	#* Create color arrays from one, two or three color gradient, 100 values in each
	for array_name in "temp" "cpu" "upload" "download" "used" "available" "cached" "free"; do
		local -n color_array="color_${array_name}_graph"
		local -a rgb_start=(${theme[${array_name}_start]}) rgb_mid=(${theme[${array_name}_mid]}) rgb_end=(${theme[${array_name}_end]})
		local pf_calc middle=1

		rgb[red]=${rgb_start[0]}; rgb[green]=${rgb_start[1]}; rgb[blue]=${rgb_start[2]}

		if [[ -z ${rgb_mid[*]} ]] && ((rgb_end[0]+rgb_end[1]+rgb_end[2]>rgb_start[0]+rgb_start[1]+rgb_start[2])); then
			rgb_mid=( $(( rgb_start[0]+( (rgb_end[0]-rgb_start[0])/2) )) $((rgb_start[1]+( (rgb_end[1]-rgb_start[1])/2) )) $((rgb_start[2]+( (rgb_end[2]-rgb_start[2])/2) )) )
		elif [[ -z ${rgb_mid[*]} ]]; then
			rgb_mid=( $(( rgb_end[0]+( (rgb_start[0]-rgb_end[0])/2) )) $(( rgb_end[1]+( (rgb_start[1]-rgb_end[1])/2) )) $(( rgb_end[2]+( (rgb_start[2]-rgb_end[2])/2) )) )
		fi

		for((i=0;i<=100;i++,y=0)); do

			if [[ -n ${rgb_end[*]} ]]; then
				for this_color in "red" "green" "blue"; do
					if ((i==50)); then rgb_start[y]=${rgb[$this_color]}; fi

					if ((middle==1 & rgb[$this_color]<rgb_mid[y])); then
						printf -v pf_calc "%.0f" "$(( i*( (rgb_mid[y]-rgb_start[y])*100/50*100) ))e-4"

					elif ((middle==1 & rgb[$this_color]>rgb_mid[y])); then
						printf -v pf_calc "%.0f" "-$(( i*( (rgb_start[y]-rgb_mid[y])*100/50*100) ))e-4"

					elif ((middle==0 & rgb[$this_color]<rgb_end[y])); then
						printf -v pf_calc "%.0f" "$(( (i-50)*( (rgb_end[y]-rgb_start[y])*100/50*100) ))e-4"

					elif ((middle==0 & rgb[$this_color]>rgb_end[y])); then
						printf -v pf_calc "%.0f" "-$(( (i-50)*( (rgb_start[y]-rgb_end[y])*100/50*100) ))e-4"

					else
						pf_calc=0
					fi

					rgb[$this_color]=$((rgb_start[y]+pf_calc))
					if ((rgb[$this_color]<0)); then rgb[$this_color]=0
					elif ((rgb[$this_color]>255)); then rgb[$this_color]=255; fi

					y+=1
					if ((i==49 & y==3 & middle==1)); then middle=0; fi
				done
			fi
			color_array[i]="${rgb[red]} ${rgb[green]} ${rgb[blue]}"
		done

	done
}

function quit_() { #? Clean exit
	# Restore terminal options and screen
	echo -en "${clear_screen}${normal_screen}${show_cursor}"
	${stty} "${saved_stty}"
	echo -en "\033]0;\a"

	#* Save any changed values to config file
	if [[ $config_file != "/dev/null" ]]; then
		save_config "${save_array[@]}"
	fi

	if [[ $1 == "restart" ]]; then exec "$(${realpath} "$0")"; fi

	exit ${1:-0}
}

function help_() { #? Shows the help overlay
	local help_key from_menu col line y i help_out help_pause redraw=1 wait_string pages page=1 height
	local -a shortcuts descriptions

	shortcuts=(
		"(Esc, M, m)"
		"(F2, O, o)"
		"(F1, H, h)"
		"(Ctrl-C, Q, q)"
		"(+, A, a) (-, S, s)"
		"(Up) (Down)"
		"(Enter)"
		"(Pg Up) (Pg Down)"
		"(Home) (End)"
		"(Left) (Right)"
		"(b, B) (n, N)"
		"(E, e)"
		"(R, r)"
		"(F, f)"
		"(C, c)"
		"${lang_help_selected} (T, t)"
		"${lang_help_selected} (K, k)"
		"${lang_help_selected} (I, i)"
		" "
		" "
		" "
	)
	descriptions=(
		"${lang_help_menu}"
		"${lang_help_options}"
		"${lang_help_window}"
		"${lang_help_quit}"
		"${lang_help_ms}"
		"${lang_help_process}"
		"${lang_help_details}"
		"${lang_help_jump_page}"
		"${lang_help_jump_fl_page}"
		"${lang_help_sort_col}"
		"${lang_help_np_net_device}"
		"${lang_help_toggle_tree}"
		"${lang_help_rev_sort}"
		"${lang_help_input_string}"
		"${lang_help_clear}"
		"${lang_help_terminate}"
		"${lang_help_kill}"
		"${lang_help_interrupt}"
		" "
		"${lang_help_bug_report}"
		"\e[1mhttps://github.com/girls-whocode/sar"
	)

	if [[ -n $pause_screen ]]; then from_menu=1; fi

	until [[ -n $help_key ]]; do

		#* Put program to sleep if caught ctrl-z
		if ((sleepy==1)); then sleep_; redraw=1; fi

		if [[ $background_update == true || -n $redraw ]]; then
			draw_clock
			pause_ help_pause
		else
			unset help_pause
		fi


		if [[ -n $redraw ]]; then
			col=$((tty_width/2-36)); line=$((tty_height/2-4)); y=1; height=$((tty_height-2-line))
			if ((${#shortcuts[@]}>height)); then pages=$(( (${#shortcuts[@]}/height)+1 )); else height=${#shortcuts[@]}; unset pages; fi
			unset redraw help_out
			draw_banner "$((tty_height/2-11))" help_out
			print -d 1
			create_box -v help_out -w 72 -h $((height+3)) -l $((line++)) -c $((col++)) -fill -lc ${theme[div_line]} -title "help"

			if [[ -n $pages ]]; then
				print -v help_out -m $((line+height+1)) $((col+72-16)) -rs -fg ${theme[div_line]} -t "┤" -fg ${theme[title]} -b -t "pg" -fg ${theme[hi_fg]} -t "↑"\
				-fg ${theme[title]} -t " ${page}/${pages} " -fg ${theme[title]} -t "pg" -fg ${theme[hi_fg]} -t "↓" -rs -fg ${theme[div_line]} -t "├"
			fi
			((++col))

			print -v help_out -m $line $col -fg ${theme[title]} -b -jl 20 -t "${lang_help_key_title}:" -jl 48 -t "${lang_help_description_title}:" -m $((line+y++)) $col

			for((i=(page-1)*height;i<page*height;i++)); do
				print -v help_out -fg ${theme[main_fg]} -b -jl 20 -t "${shortcuts[i]}" -rs -fg ${theme[main_fg]} -jl 48 -t "${descriptions[i]}" -m $((line+y++)) $col
			done
		fi


		unset draw_out
		echo -en "${help_pause}${help_out}"

		get_ms timestamp_end
		time_left=$((timestamp_start+update_ms-timestamp_end))

		if ((time_left>1000)); then wait_string=10; time_left=$((time_left-1000))
		elif ((time_left>100)); then wait_string=$((time_left/100)); time_left=0
		else wait_string="0"; time_left=0; fi

		get_key -v help_key -w "${wait_string}"

		if [[ -n $pages ]]; then
			case $help_key in
				down|page_down) if ((page<pages)); then ((page++)); else page=1; fi; redraw=1; unset help_key ;;
				up|page_up) if ((page>1)); then ((page--)); else page=${pages}; fi; redraw=1; unset help_key ;;
			esac
		fi

		if [[ $(${stty} size) != "$tty_height $tty_width" ]]; then resized; fi
		if ((resized>0)); then
			${sleep} 0.5
			calc_sizes; bashtop_draw_bg quiet; redraw=1
			d_banner=1
			unset bannerd menu_out
		fi
		if ((time_left==0)); then get_ms timestamp_start; collect_and_draw; fi
		if ((resized>0)); then resized=0; fi
	done

	if [[ -n $from_menu ]]; then pause_
	else unpause_; fi
}

function options_() { #? Shows the options overlay
	local keypress from_menu col line y=1 i=1 options_out selected_int=0 ypos option_string options_misc option_value bg fg skipped start_t end_t left_t changed_cpu_name theme_int=0 page=1 pages height
	local desc_col right left enter lr inp valid updated_ms local_rez redraw_misc=1 desc_pos desc_height options_pause updated_proc inputting inputting_value inputting_key file theme_check net_totals_reset

	if ((net[reset]==1)); then net_totals_reset="On"; else net_totals_reset="Off"; fi

	#* Check theme folder for theme files
	get_themes

	if [[ -n $pause_screen ]]; then from_menu=1; fi

	until false; do

		#* Put program to sleep if caught ctrl-z
		if ((sleepy==1)); then sleep_; fi

		if [[ $background_update == true || -n $redraw_misc ]]; then
			draw_clock
			if [[ -z $inputting ]]; then pause_ options_pause; fi
		else
			unset options_pause
		fi

		if [[ -n $redraw_misc ]]; then
			unset options_misc redraw_misc
			col=$((tty_width/2-39))
			line=$((tty_height/2-4))
			height=$(( (tty_height-2-line)/2 ))
			if ((${#options_array[@]}>height)); then pages=$(( (${#options_array[@]}/height)+1 )); else height=${#options_array[@]}; unset pages; fi
			desc_col=$((col+30))
			draw_banner "$((tty_height/2-11))" options_misc
			create_box -v options_misc -w 29 -h $((height*2+2)) -l $line -c $((col-1)) -fill -lc ${theme[div_line]} -title "${lang_options_title}"
			if [[ -n $pages ]]; then
				print -v options_misc -m $((line+height*2+1)) $((col+29-16)) -rs -fg ${theme[div_line]} -t "┤" -fg ${theme[title]} -b -t "pg" -fg ${theme[hi_fg]} -t "↑"\
				-fg ${theme[title]} -t " ${page}/${pages} " -fg ${theme[title]} -t "pg" -fg ${theme[hi_fg]} -t "↓" -rs -fg ${theme[div_line]} -t "├"
			fi
		fi

		if [[ -n $keypress || -z $options_out ]]; then
			unset options_out desc_height lr inp valid
			selected="${options_array[selected_int]}"
			local -n selected_desc="desc_${selected}"
			if [[ $background_update == false ]]; then desc_pos=$line; desc_height=$((height*2+2))
			elif (( (selected_int-( (page-1)*height) )*2+${#selected_desc[@]}<height*2 )); then desc_pos=$((line+(selected_int-( (page-1)*height) )*2))
			else desc_pos=$((line+height*2-${#selected_desc[@]})); fi
			create_box -v options_out -w 50 -h ${desc_height:-$((${#selected_desc[@]}+2))} -l $desc_pos -c $((desc_col-1)) -fill -lc ${theme[div_line]} -title "description"
			for((i=(page-1)*height,ypos=1;i<page*height;i++,ypos=ypos+2)); do
				if [[ -z ${options_array[i]} ]]; then break; fi
				option_string="${options_array[i]}"
				if [[ -n $inputting && ${option_string} == "${selected}" ]]; then
					if [[ ${#inputting_value} -gt 14 ]]; then option_value="${inputting_value:(-14)}_"
					else option_value="${inputting_value}_"; fi
				else
					option_value="${!option_string}"
				fi

				if [[ ${option_string} == "${selected}" ]]; then
					if is_int "$option_value" || [[ $selected == "color_theme" && -n $curled ]]; then
						enter="↲"; inp=1
					fi
					if is_int "$option_value" || [[ $option_value =~ true|false || $selected =~ proc_sorting|color_theme ]] && [[ -z $inputting ]]; then
						left="←"; right="→"; lr=1
					else
						enter="↲"; inp=1
					fi
					bg=" -bg ${theme[selected_bg]}"
					fg="${theme[selected_fg]}"
				fi
				option_string="${option_string//_/ }:"
				if [[ $option_string == "proc sorting:" ]]; then
					option_string+=" $((proc[sorting_int]+1))/${#sorting[@]}"
				elif [[ $option_string == "color theme:" ]]; then
					option_string+=" $((theme_int+1))/${#themes[@]}"
					if [[ ${option_value::12} == "user_themes/" ]]; then option_value="*${option_value#*/}"
					else option_value="${option_value#*/}"; fi
				fi
				print -v options_out -m $((line+ypos)) $((col+1)) -rs -fg ${fg:-${theme[title]}}${bg} -b -jc 25 -t "${option_string^}"
				print -v options_out -m $((line+ypos+1)) $((col+1)) -rs -fg ${fg:-${theme[main_fg]}}${bg} -jc 25 -t "${enter:+ } ${left} \"${option_value::15}\" ${right} ${enter}"
				unset right left enter bg fg
			done

			for((i=0,ypos=1;i<${#selected_desc[@]};i++,ypos++)); do
				print -v options_out -m $((desc_pos+ypos)) $((desc_col+1)) -rs -fg ${theme[main_fg]} -jl 46 -t "${selected_desc[i]}"
			done
		fi

		echo -en "${options_pause}${options_misc}${options_out}"
		unset draw_out keypress

		if [[ -n $theme_check ]]; then
			local -a theme_index
			local git_theme new_themes=0 down_themes=0 new_theme
			unset 'theme_index[@]' 'desc_color_theme[-1]' 'desc_color_theme[-1]' 'desc_color_theme[-1]' options_out
			theme_index=($(curl -m 3 --raw https://raw.githubusercontent.com/aristocratos/bashtop/master/themes/index.txt 2>/dev/null))
			if [[ ${theme_index[*]} =~ .theme ]]; then
				for git_theme in ${theme_index[@]}; do
					unset new_theme
					if [[ ! -e "${config_dir}/themes/${git_theme}" ]]; then new_theme=1; fi
					if curl -m 3 --raw "https://raw.githubusercontent.com/aristocratos/bashtop/master/themes/${git_theme}" >"${config_dir}/themes/${git_theme}" 2>/dev/null; then
						((++down_themes))
						if [[ -n $new_theme ]]; then
							((++new_themes))
							themes+=("themes/${git_theme%.theme}")
						fi
					fi
				done
				desc_color_theme+=("Downloaded ${down_themes} theme(s).")
				desc_color_theme+=("Found ${new_themes} new theme(s)!")
			else
				desc_color_theme+=("ERROR: Couldn't get theme index!")
			fi
		fi


		get_ms timestamp_end
		if [[ -z $theme_check ]]; then time_left=$((timestamp_start+update_ms-timestamp_end))
		else unset theme_check; time_left=0; fi

		if ((time_left>500)); then wait_string=5; time_left=$((time_left-500))
		elif ((time_left>100)); then wait_string=$((time_left/100)); time_left=0
		else wait_string="0"; time_left=0; fi

		get_key -v keypress -w ${wait_string}

		if [[ -n $inputting ]]; then
			case "$keypress" in
				escape) unset inputting inputting_value ;;
				enter|backspace) valid=1 ;;
				*) if [[ ${#keypress} -eq 1 ]]; then valid=1; fi ;;
			esac
		else
			case "$keypress" in
				escape|q|backspace) break 1 ;;
				down|tab) if ((selected_int<${#options_array[@]}-1)); then ((++selected_int)); else selected_int=0; fi ;;
				up|shift_tab) if ((selected_int>0)); then ((selected_int--)); else selected_int=$((${#options_array[@]}-1)); fi ;;
				left|right) if [[ -n $lr && -z $inputting ]]; then valid=1; fi ;;
				enter) if [[ -n $inp ]]; then valid=1; fi ;;
				page_down) if ((page<pages)); then ((page++)); else page=1; selected_int=0; fi; redraw_misc=1; selected_int=$(( (page-1)*height )) ;;
				page_up) if ((page>1)); then ((page--)); else page=${pages}; fi; redraw_misc=1; selected_int=$(( (page-1)*height )) ;;
			esac
			if (( selected_int<(page-1)*height | selected_int>=page*height )); then page=$(( (selected_int/height)+1 )); redraw_misc=1; fi
		fi

		if [[ ${selected} == "color_theme" && ${keypress} =~ left|right && ${#themes} -lt 2 ]]; then unset valid; fi

		if [[ -n $valid ]]; then
			case "${selected} ${keypress}" in
				"update_ms right")
						if ((update_ms<86399900)); then
							update_ms=$((update_ms+100))
							updated_ms=1
						fi
					;;
				"update_ms left")
						if ((update_ms>100)); then
							update_ms=$((update_ms-100))
							updated_ms=1
						fi
					;;
				"update_ms enter")
						if [[ -z $inputting ]]; then inputting=1; inputting_value="${update_ms}"
						else
							if ((inputting_value<86400000)); then update_ms="${inputting_value:-0}"; updated_ms=1; fi
							unset inputting inputting_value
						fi
					;;
				"update_ms backspace"|"draw_clock backspace"|"custom_cpu_name backspace"|"disks_filter backspace")
						if [[ ${#inputting_value} -gt 0 ]]; then
							inputting_value="${inputting_value::-1}"
						fi
					;;
				"update_ms"*)
						inputting_value+="${keypress//[^0-9]/}"
					;;
				"draw_clock enter")
						if [[ -z $inputting ]]; then inputting=1; inputting_value="${draw_clock}"
						else draw_clock="${inputting_value}"; unset inputting inputting_value clock_out; fi
					;;
				"custom_cpu_name enter")
						if [[ -z $inputting ]]; then inputting=1; inputting_value="${custom_cpu_name}"
						else custom_cpu_name="${inputting_value}"; changed_cpu_name=1; unset inputting inputting_value; fi
					;;
				"disks_filter enter")
						if [[ -z $inputting ]]; then inputting=1; inputting_value="${disks_filter}"
						else disks_filter="${inputting_value}"; mem[counter]=10; resized=1; unset inputting inputting_value; fi
					;;
				"net_totals_reset enter")
						if ((net[reset]==1)); then net_totals_reset="Off"; net[reset]=0
						else net_totals_reset="On"; net[reset]=1; fi
					;;
				"check_temp"*|"error_logging"*|"background_update"*|"proc_reversed"*|"proc_gradient"*|"proc_per_core"*|"update_check"*|"hires_graphs"*|"use_psutil"*|"proc_tree"*)
						local -n selected_var=${selected}
						if [[ ${selected_var} == "true" ]]; then
							selected_var="false"
							if [[ $selected == "proc_reversed" ]]; then proc[order_change]=1; unset 'proc[reverse]'
							elif [[ $selected == "proc_tree" ]]; then proc[order_change]=1; unset 'proc[tree]'; fi
						else
							selected_var="true"
							if [[ $selected == "proc_reversed" ]]; then proc[order_change]=1; proc[reverse]="+"
							elif [[ $selected == "proc_tree" ]]; then proc[order_change]=1; proc[tree]="+"; fi
						fi
						if [[ $selected == "check_temp" && $check_temp == true ]]; then
							local has_temp
							sensor_comm=""
							if [[ $use_psutil == true ]]; then
								py_command -v has_temp "get_sensors_check()"
								if [[ $has_temp == true ]]; then sensor_comm="psutil"; fi
							fi
							if [[ -z $sensor_comm ]]; then
								local checker
								for checker in "vcgencmd" "sensors" "osx-cpu-temp"; do
									if command -v "${checker}" >/dev/null 2>&1; then sensor_comm="${checker}"; break; fi
								done
							fi
							if [[ -z $sensor_comm ]]; then check_temp="false"
							else resized=1; fi
						elif [[ $selected == "check_temp" ]]; then
							resized=1
						fi
						if [[ $selected == "use_psutil" && $system != "Linux" ]]; then use_psutil="true"
						elif [[ $selected == "use_psutil" ]]; then quit_ restart psutil; fi
						if [[ $selected == "error_logging" ]]; then quit_ restart; fi

					;;
				"proc_sorting right")
						if ((proc[sorting_int]<${#sorting[@]}-1)); then ((++proc[sorting_int]))
						else proc[sorting_int]=0; fi
						proc_sorting="${sorting[proc[sorting_int]]}"
						proc[order_change]=1
					;;
				"proc_sorting left")
						if ((proc[sorting_int]>0)); then ((proc[sorting_int]--))
						else proc[sorting_int]=$((${#sorting[@]}-1)); fi
						proc_sorting="${sorting[proc[sorting_int]]}"
						proc[order_change]=1
					;;
				"color_theme right")
						if ((theme_int<${#themes[@]}-1)); then ((++theme_int))
						else theme_int=0; fi
						color_theme="${themes[$theme_int]}"
						color_init_
						resized=1
					;;
				"color_theme left")
						if ((theme_int>0)); then ((theme_int--))
						else theme_int=$((${#themes[@]}-1)); fi
						color_theme="${themes[$theme_int]}"
						color_init_
						resized=1
					;;
				"color_theme enter")
						theme_check=1
						if ((${#desc_color_theme[@]}>8)); then unset 'desc_color_theme[-1]'; fi
						desc_color_theme+=("Checking for new themes...")
					;;
				"draw_clock"*|"custom_cpu_name"*|"disks_filter"*)
						inputting_value+="${keypress//[\\\$\"\']/}"
					;;

			esac

		fi

		if [[ -n $changed_cpu_name ]]; then
			changed_cpu_name=0
			get_cpu_info
			calc_sizes
			bashtop_draw_bg quiet
		fi

		if [[ $(${stty} size) != "$tty_height $tty_width" ]]; then resized; fi

		if ((resized>0)); then
			calc_sizes
			bashtop_draw_bg quiet
			redraw_misc=1
			unset options_out bannerd menu_out
		fi

		get_ms timestamp_end
		time_left=$((timestamp_start+update_ms-timestamp_end))
		if ((time_left<=0 | resized>0)); then get_ms timestamp_start; if [[ -z $inputting ]]; then collect_and_draw; fi; fi
		if ((resized>0)); then resized=0; page=1; selected_int=0; fi

		if [[ -n $updated_ms ]] && ((updated_ms++==2)); then
			unset updated_ms
			draw_update_string quiet
		fi

	done

	if [[ -n $from_menu ]]; then pause_
	elif [[ -n ${pause_screen} ]]; then unpause_; draw_update_string; fi
}

function get_key() { #? Get one key from standard input and translate key code to readable format
	local key key_out wait_time esc ext_out save

	if ((quitting==1)); then quit_; fi

	until (($#==0)); do
		case "$1" in
			-v|-variable) local -n key_out=$2; ext_out=1; shift;;			#* Output variable
			-w|-wait) wait_time="$2"; shift;;								#* Time to wait for key
			-s|-save) save=1;;												#* Save key for later processing
		esac
		shift
	done

	if [[ -z $save && -n ${saved_key[0]} ]]; then key="${saved_key[0]}"; unset 'saved_key[0]'; saved_key=("${saved_key[@]}")
	else
		unset key

		key=$(${stty} -cooked min 0 time ${wait_time:-0} 2>/dev/null; ${dd} bs=1 count=1 2>/dev/null)
		if [[ -z ${key:+s} ]]; then
			key_out=""
			${stty} isig
			if [[ -z $save ]]; then return 0
			else return 1; fi
		fi

		#* Read 3 more characters if a leading escape character is detected
		if [[ $key == "${enter_key}" ]]; then key="enter"
		elif [[ $key == "${ctrl_c}" ]]; then quitting=1; time_left=0
		elif [[ $key == "${ctrl_z}" ]]; then sleepy=1; time_left=0
		elif [[ $key == "${backspace}" || $key == "${backspace_real}" ]]; then key="backspace"
		elif [[ $key == "${tab}" ]]; then key="tab"
		elif [[ $key == "$esc_character" ]]; then
			esc=1; key=$(${stty} -cooked min 0 time 0 2>/dev/null; ${dd} bs=1 count=3 2>/dev/null); fi
		if [[ -z $key && $esc -eq 1 ]]; then key="escape"
		elif [[ $esc -eq 1 ]]; then
			case "${key}" in
				'[A'*|'OA'*) key="up" ;;
				'[B'*|'OB'*) key="down" ;;
				'[D'*|'OD'*) key="left" ;;
				'[C'*|'OC'*) key="right" ;;
				'[2~') key="insert" ;;
				'[3~') key="delete" ;;
				'[H'*) key="home" ;;
				'[F'*) key="end" ;;
				'[5~') key="page_up" ;;
				'[6~') key="page_down" ;;
				'[Z'*) key="shift_tab" ;;
				'OP'*) key="f1";;
				'OQ'*) key="f2";;
				'OR'*) key="f3";;
				'OS'*) key="f4";;
				'[15') key="f5";;
				'[17') key="f6";;
				'[18') key="f7";;
				'[19') key="f8";;
				'[20') key="f9";;
				'[21') key="f10";;
				'[23') key="f11";;
				'[24') key="f12";;
				*) key="" ;;
			esac
		fi

	fi

	${stty} -cooked min 0 time 0 >/dev/null 2>&1; ${dd} bs=512 count=1 >/dev/null 2>&1
	${stty} isig
	if [[ -n $save && -n $key ]]; then saved_key+=("${key}"); return 0; fi

	if [[ -n $ext_out ]]; then key_out="${key}"
	else echo -n "${key}"; fi
}

function process_input() { #? Process keypresses for main ui
	local wait_time="$1" keypress esc prev_screen anykey filter_change p_height=$((box[processes_height]-3))
	late_update=0
	#* Wait while reading input
	get_key -v keypress -w "${wait_time}"
	if [[ -z $keypress ]] || [[ -n $failed_pipe ]]; then return; fi

	if [[ -n $input_to_filter ]]; then
		filter_change=1
		case "$keypress" in
			"enter") unset input_to_filter ;;
			"backspace") if [[ ${#filter} -gt 0 ]]; then filter="${filter:: (-1)}"; else unset filter_change; fi ;;
			"escape") unset input_to_filter filter ;;
			*) if [[ ${#keypress} -eq 1 && $keypress =~ ^[A-Za-z0-9\!\@\#\%\&\/\(\)\[\+\-\_\*\,\;\.\:]$ ]]; then filter+="${keypress//[\\\$\"\']/}"; else unset filter_change; fi ;;
		esac

	else
		case "$keypress" in
			left) #* Move left in processes sorting column
				if ((proc[sorting_int]>0)); then ((proc[sorting_int]--))
				else proc[sorting_int]=$((${#sorting[@]}-1)); fi
				proc_sorting="${sorting[proc[sorting_int]]}"
				if [[ $proc_sorting == "tree" && $use_psutil == true ]]; then
					((proc[sorting_int]--))
					proc_sorting="${sorting[proc[sorting_int]]}"
				fi
				filter_change=1
			;;
			right) #* Move right in processes sorting column
				if ((proc[sorting_int]<${#sorting[@]}-1)); then ((++proc[sorting_int]))
				else proc[sorting_int]=0; fi
				proc_sorting="${sorting[proc[sorting_int]]}"
				if [[ $proc_sorting == "tree" && $use_psutil == true ]]; then
					proc[sorting_int]=0
					proc_sorting="${sorting[proc[sorting_int]]}"
				fi
				filter_change=1
			;;
			n|N) #* Switch to next network device
				if ((${#nic_list[@]}>1)); then
					if ((nic_int<${#nic_list[@]}-1)); then ((++nic_int))
					else nic_int=0; fi
					net[device]="${nic_list[nic_int]}"
					net[nic_change]=1
					collect_net init
					collect_net
					draw_net now
				fi
			;;
			b|B) #* Switch to previous network device
				if ((${#nic_list[@]}>1)); then
					if ((nic_int>0)); then ((nic_int--))
					else nic_int=$((${#nic_list[@]}-1)); fi
					net[device]="${nic_list[nic_int]}"
					net[nic_change]=1
					collect_net init
					collect_net
					draw_net now
				fi
			;;
			up|shift_tab) #* Move process selector up one
				if ((proc[selected]>1)); then
					((proc[selected]--))
					proc[page_change]=1
				elif ((proc[start]>1)); then
					if ((proc[selected]==0)); then proc[selected]=${p_height}; fi
					((proc[start]--))
					proc[page_change]=1
				elif ((proc[start]==1 & proc[selected]==1)); then
					proc[selected]=0
					proc[page_change]=1
				fi
			;;
			down|tab) #* Move process selector down one
				if ((proc[selected]<p_height & proc[start]+proc[selected]<(${#proc_array[@]}) )); then
					((++proc[selected]))
					proc[page_change]=1
				elif ((proc[start]+proc[selected]<(${#proc_array[@]}) )); then
					((++proc[start]))
					proc[page_change]=1
				fi
			;;
			enter) #* Show detailed info for selected process or close detailed info if no new process is selected
				if ((proc[selected]>0 & proc[detailed_pid]!=proc[selected_pid])) && ps -p ${proc[selected_pid]} > /dev/null 2>&1; then
					proc[detailed]=1
					proc[detailed_change]=1
					proc[detailed_pid]=${proc[selected_pid]}
					proc[selected]=0
					unset 'proc[detailed_name]' 'detail_history[@]' 'detail_mem_history[@]' 'proc[detailed_killed]'
					calc_sizes
					# collect_processes now
				elif ((proc[detailed]==1 & proc[detailed_pid]!=proc[selected_pid])); then
					proc[detailed]=0
					proc[detailed_change]=1
					unset 'proc[detailed_pid]'
					calc_sizes
				fi
			;;
			page_up) #* Move up one page in process box
				if ((proc[start]>1)); then
					proc[start]=$(( proc[start]-p_height ))
					if ((proc[start]<1)); then proc[start]=1; fi
					proc[page_change]=1
				elif ((proc[selected]>0)); then
					proc[selected]=0
					proc[start]=1
					proc[page_change]=1
				fi
			;;
			page_down) #* Move down one page in process box
				if ((proc[start]<(${#proc_array[@]}-1)-p_height)); then
					proc[start]=$(( proc[start]+p_height ))
					if (( proc[start]>(${#proc_array[@]})-p_height )); then proc[start]=$(( (${#proc_array[@]})-p_height )); fi
					proc[page_change]=1
				elif ((proc[selected]>0)); then
					proc[selected]=$((p_height))
					proc[page_change]=1
				fi
			;;
			home) #* Go to first page in process box
					proc[start]=1
					proc[page_change]=1
			;;
			end) #* Go to last page in process box
					proc[start]=$(((${#proc_array[@]}-1)-p_height))
					proc[page_change]=1
			;;
			r|R) #* Reverse order of processes sorting column
				if [[ -z ${proc[reverse]} ]]; then
					proc[reverse]="+"
					proc_reversed="true"
				else
					proc_reversed="false"
					unset 'proc[reverse]'
				fi
				filter_change=1
			;;
			e|E) #* Show processes as a tree
				if [[ -z ${proc[tree]} ]]; then
					proc[tree]="+"
					proc_tree="true"
				else
					proc_tree="false"
					unset 'proc[tree]'
				fi
				filter_change=1
			;;
			o|O|f2) #* Options
				options_
			;;
			+|A|a) #* Add 100ms to update timer
				if ((update_ms<86399900)); then
					update_ms=$((update_ms+100))
					draw_update_string
				fi
			;;
			-|S|s) #* Subtract 100ms from update timer
				if ((update_ms>100)); then
					update_ms=$((update_ms-100))
					draw_update_string
				fi
			;;
			h|H|f1) #* Show help
				help_
			;;
			q|Q) #* Quit
				quit_
			;;
			m|M|escape) #* Show main menu
				menu_
			;;
			f|F) #* Start process filtering input
				input_to_filter=1
				filter_change=1
				if ((proc[selected]>1)); then proc[selected]=1; fi
				proc[start]=1
			;;
			c|C) #* Clear process filter
				if [[ -n $filter ]]; then
					unset input_to_filter filter
					filter_change=1
				fi
			;;
			t|T|k|K|i|I) #* Send terminate, kill or interrupt signal
				if [[ ${proc[selected]} -gt 0 ]]; then
					killer_ "$keypress" "${proc[selected_pid]}"
				elif [[ ${proc[detailed]} -eq 1 && -z ${proc[detailed_killed]} ]]; then
					killer_ "$keypress" "${proc[detailed_pid]}"
				fi
			;;
		esac
	fi

	if [[ -n $filter_change ]]; then
		unset filter_change
		# collect_processes now
		proc[filter_change]=1
		# draw_processes now
	elif [[ ${proc[page_change]} -eq 1 || ${proc[detailed_change]} == 1 ]]; then
		if ((proc[selected]==0)); then unset 'proc[selected_pid]'; proc[detailed_change]=1; fi
		# draw_processes now
	fi

	#* Subtract time since input start from time left if timer is interrupted
	get_ms timestamp_input_end
	time_left=$(( (timestamp_start+update_ms)-timestamp_input_end ))

	return 0
}

function collect_and_draw() { 
	# Run all collect and draw functions
	local task_int=0 input_runs
	for task in navigation information status remote; do
		((++task_int))
		if [[ -n $pause_screen && -n ${saved_key[0]} ]]; then
			return
		elif [[ -z $pause_screen ]]; then
			input_runs=0
			while [[ -n ${saved_key[0]} ]] && ((time_left>0)) && ((++input_runs<=5)); do
				process_input
				unset late_update
			done
		fi
		# collect_${task}
		if get_key -save && [[ -z $pause_screen ]]; then process_input; fi
		# draw_${task}
		if get_key -save && [[ -z $pause_screen ]]; then process_input; fi
		draw_clock "$1"
		if ((resized>0 & resized<task_int)) || [[ -n $failed_pipe || -n $py_error ]]; then return; fi
	done

	last_screen="${draw_out}"
}

function get_functions() {
    # Usage: get_functions
    IFS=$'\n' read -d "" -ra functions < <(declare -F)
    printf '%s\n' "${functions[@]//declare -f }"
}
