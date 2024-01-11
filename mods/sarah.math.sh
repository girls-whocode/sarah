#!/usr/bin/env bash

function is_int() { #? Check if value(s) is integer
	local param
	for param; do
		if [[ ! $param =~ ^[\-]?[0-9]+$ ]]; then return 1; fi
	done
}

function is_float() { #? Check if value(s) is floating point
	local param
	for param; do
		if [[ ! $param =~ ^[\-]?[0-9]*[,.][0-9]+$ ]]; then return 1; fi
	done
}

function is_hex() { #? Check if value(s) is hexadecimal
	local param
	for param; do
		if [[ ! ${param//#/} =~ ^[0-9a-fA-F]*$ ]]; then return 1; fi
	done
}

function floating_humanizer() { 	#? Convert integer to floating point and scale up in steps of 1024 to highest positive unit
						#? Usage: floating_humanizer <-b,-bit|-B,-Byte> [-ps,-per-second] [-s,-start "1024 multiplier start"] [-v,-variable-output] <input>
	local value selector per_second unit_mult decimals out_var ext_var short sep=" "
	local -a unit
	until (($#==0)); do
		case "$1" in
			-b|-bit) unit=(bit Kib Mib Gib Tib Pib); unit_mult=8;;
			-B|-Byte) unit=(Byte KiB MiB GiB TiB PiB); unit_mult=1;;
			-ps|-per-second) per_second=1;;
			-short) short=1; sep="";;
			-s|-start) selector="$2"; shift;;
			-v|-variable-output) local -n out_var="$2"; ext_var=1; shift;;
			*) if is_int "$1"; then value=$1; break; fi;;
		esac
		shift
	done

	if [[ -z $value || $value -lt 0 || -z $unit_mult ]]; then return; fi

	if ((per_second==1 & unit_mult==1)); then per_second="/s"
	elif ((per_second==1)); then per_second="ps"; fi

	if ((value>0)); then
		value=$((value*100*unit_mult))

		until ((${#value}<6)); do
			value=$((value>>10))
			if ((value<100)); then value=100; fi
			((++selector))
		done

		if ((${#value}<5 & ${#value}>=2 & selector>0)); then
			decimals=$((5-${#value}))
			value="${value::-2}.${value:(-${decimals})}"
		elif ((${#value}>=2)); then
			value="${value::-2}"
		fi
	fi

	if [[ -n $short ]]; then value="${value%.*}"; fi

	out_var="${value}${sep}${unit[$selector]::${short:-${#unit[$selector]}}}${per_second}"
	if [[ -z $ext_var ]]; then echo -n "${out_var}"; fi
}

function calc_sizes() { 
	# Calculate width and height of all boxes
	local pos calc_size calc_total percent

	#* Calculate heights
	for pos in ${box[boxes]}; do
		if [[ $pos = "cpu" ]]; then percent=32;
		elif [[ $pos = "mem" ]]; then percent=40;
		else percent=28; fi

		#* Multiplying with 10 to convert to floating point
		calc_size=$(( (tty_height*10)*(percent*10)/100 ))

		#* Round down if last 2 digits of value is below "50" and round up if above
		if ((${calc_size:(-2):1}==0)); then calc_size=$((calc_size+10)); fi
		if ((${calc_size:(-2)}<50)); then
			calc_size=$((${calc_size::-2}))
		else
			calc_size=$((${calc_size::-2}+1))
		fi

		#* Subtract from last value if the total of all rounded numbers is larger then terminal height
		while ((calc_total+calc_size>tty_height)); do ((--calc_size)); done
		calc_total=$((calc_total+calc_size))

		#* Set calculated values in box array
		box[${pos}_line]=$((calc_total-calc_size+1))
		box[${pos}_col]=1
		box[${pos}_height]=$calc_size
		box[${pos}_width]=$tty_width
	done


	#* Calculate widths
	unset calc_total
	for pos in net processes; do
		if [[ $pos = "net" ]]; then percent=45; else percent=55; fi

		#* Multiplying with 10 to convert to floating point
		calc_size=$(( (tty_width*10)*(percent*10)/100 ))

		#* Round down if last 2 digits of value is below "50" and round up if above
		if ((${calc_size:(-2)}<50)); then
			calc_size=$((${calc_size::-2}))
		else
			calc_size=$((${calc_size::-2}+1))
		fi

		#* Subtract from last value if the total of all rounded numbers is larger then terminal width
		while ((calc_total+calc_size>tty_width)); do ((--calc_size)); done
		calc_total=$((calc_total+calc_size))

		#* Set calculated values in box array
		box[${pos}_col]=$((calc_total-calc_size+1))
		box[${pos}_width]=$calc_size
	done

	#* Copy numbers around to get target layout
	box[mem_width]=${box[net_width]}
	box[processes_line]=${box[mem_line]}
	box[processes_height]=$((box[mem_height]+box[net_height]))

	#  threads=${box[testing]} #! For testing, remove <--------------

	#* Recalculate size of process box if currently showing detailed process information
	if ((proc[detailed]==1)); then
		box[details_line]=${box[processes_line]}
		box[details_col]=${box[processes_col]}
		box[details_width]=${box[processes_width]}
		box[details_height]=8
		box[processes_line]=$((box[processes_line]+box[details_height]))
		box[processes_height]=$((box[processes_height]-box[details_height]))
	fi

	#* Calculate number of columns and placement of cpu meter box
	local cpu_line=$((box[cpu_line]+1)) cpu_width=$((box[cpu_width]-2)) cpu_height=$((box[cpu_height]-2)) box_cols
	if ((threads>(cpu_height-3)*3 && tty_width>=200)); then box[p_width]=$((24*4)); box[p_height]=$((threads/4+4)); box_cols=4
	elif ((threads>(cpu_height-3)*2 && tty_width>=150)); then box[p_width]=$((24*3)); box[p_height]=$((threads/3+5)); box_cols=3
	elif ((threads>cpu_height-3 && tty_width>=100)); then box[p_width]=$((24*2)); box[p_height]=$((threads/2+4)); box_cols=2
	else box[p_width]=24; box[p_height]=$((threads+4)); box_cols=1
	fi

	if [[ $check_temp == true ]]; then
		box[p_width]=$(( box[p_width]+13*box_cols))
	fi

	if ((box[p_height]>cpu_height)); then box[p_height]=$cpu_height; fi
	box[p_col]="$((cpu_width-box[p_width]+2))"
	box[p_line]="$((cpu_line+(cpu_height/2)-(box[p_height]/2)+1))"

	#* Calculate placement of mem divider
	local mem_line=$((box[mem_line]+1)) mem_width=$((box[mem_width]-2)) mem_height=$((box[mem_height]-2)) mem_col=$((box[mem_col]+1))
	box[m_width]=$((mem_width/2))
	box[m_width2]=${box[m_width]}
	if ((box[m_width]+box[m_width2]<mem_width)); then ((box[m_width]++)); fi
	box[m_height]=$mem_height
	box[m_col]=$((mem_col+1))
	box[m_line]=$mem_line

	#* Calculate placement of net value box
	local net_line=$((box[net_line]+1)) net_width=$((box[net_width]-2)) net_height=$((box[net_height]-2))
	box[n_width]=24
	if ((net_height>9)); then box[n_height]=9
	else box[n_height]=$net_height; fi
	box[n_col]="$((net_width-box[n_width]+2))"
	box[n_line]="$((net_line+(net_height/2)-(box[n_height]/2)+1))"
}