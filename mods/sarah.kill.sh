#!/usr/bin/env bash

function killer_() { 
    # Kill process with selected signal
	local kill_op="$1" kill_pid="$2" killer_out killer_box col line program keypress selected selected_int=0 sig confirmed=0 option killer_pause status msg
	local -a options=("yes" "no")

	if ! program="$(ps -o comm -p ${kill_pid})"; then return
	else program="$(tail -n1 <<<"$program")"; fi

	case $kill_op in
		t|T) kill_op="terminate"; sig="SIGTERM" ;;
		k|K) kill_op="kill"; sig="SIGKILL" ;;
		i|I) kill_op="interrupt"; sig="SIGINT" ;;
	esac

	until false; do

		#* Put program to sleep if caught ctrl-z
		if ((sleepy==1)); then sleep_; fi

		if [[ $background_update == true || -z $killer_box ]]; then
			draw_clock
			pause_ killer_pause
		else
			unset killer_pause
		fi

		if [[ -z $killer_box ]]; then
			col=$((tty_width/2-15)); line=$((tty_height/2-4)); y=1
			unset redraw killer_box
			create_box -v killer_box -w 40 -h 9 -l $line -c $((col++)) -fill -lc "${theme[proc_box]}" -title "${kill_op}"
		fi

		if ((confirmed==0)); then
			selected="${options[selected_int]}"
			print -v killer_out -m $((line+2)) $col -fg ${theme[title]} -b -jc 38 -t "${kill_op^} ${program::20}?" -m $((line+4)) $((col+3))
			for option in "${options[@]}"; do
				if [[ $option == "${selected}" ]]; then print -v killer_out -bg ${theme[selected_bg]} -fg ${theme[selected_fg]}; else print -v killer_out -fg ${theme[title]}; fi
				print -v killer_out -b -r 5 -t "[  ${option^}  ]" -rs
			done

		elif ((confirmed==1)); then
			selected="ok"
			print -v killer_out -m $((line+2)) $col -fg ${theme[title]} -b -jc 38 -t "${lang_cpu_action_send} ${sig} ${lang_cpu_action_toPID} ${kill_pid}!"
			print -v killer_out -m $((line+4)) $col -fg ${theme[main_fg]} -jc 38 -t "${status^}!" -m $((line+6)) $col
			if [[ -n $msg ]]; then print -v killer_out -m $((line+5)) $col -fg ${theme[main_fg]} -jc 38 -t "${msg}" -m $((line+7)) $col; fi
			print -v killer_out -fg ${theme[selected_fg]} -bg ${theme[selected_bg]} -b -r 15 -t "[  Ok  ]" -rs
		fi

		echo -en "${killer_pause}${killer_box}${killer_out}"
		unset killer_out draw_out


		get_ms timestamp_end
		time_left=$((timestamp_start+update_ms-timestamp_end))

		if ((time_left>1000)); then wait_string=10; time_left=$((time_left-1000))
		elif ((time_left>100)); then wait_string=$((time_left/100)); time_left=0
		else wait_string="0"; time_left=0; fi

		get_key -v keypress -w ${wait_string}
		if [[ $(${stty} size) != "$tty_height $tty_width" ]]; then resized; fi
		if ((resized>0)); then
			calc_sizes;
			bashtop_draw_bg quiet; 
			time_left=0; 
			unset killer_out killer_box
		fi

		case "$keypress" in
			right|shift_tab) if ((selected_int>0)); then ((selected_int--)); else selected_int=$((${#options[@]}-1)); fi ;;
			left|tab) if ((selected_int<${#options[@]}-1)); then ((++selected_int)); else selected_int=0; fi ;;
			enter)
				case "$selected" in
					yes) confirmed=1 ;;
					no|ok) confirmed=-1 ;;
				esac
			;;
			q|Q) quit_ ;;
		esac

		if ((confirmed<0)); then
			unpause_
			break
		elif ((confirmed>0)) && [[ -z $status ]]; then
			if ${kill} -${sig} ${kill_pid} >/dev/null 2>&1; then
				status="success"
			else
				if ! ps -p ${kill_pid} >/dev/null 2>&1; then
					msg="Process not running."
				elif [[ $UID != 0 ]]; then
					msg="Try restarting with sudo."
				else
					msg="Unknown error."
				fi
				status="failed"; fi
		fi

		if ((time_left==0)); then get_ms timestamp_start; unset draw_out; collect_and_draw; fi
		if ((resized>=5)); then resized=0; fi

	done


}