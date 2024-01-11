#!/usr/bin/env bash

function create_box() { #? Draw a box with an optional title at given location
	local width height col line title ltype hpos vpos i hlines vlines color line_color c_rev=0 box_out ext_var fill
	until (($#==0)); do
		case $1 in
			-f|-full) col=1; line=1; width=$((tty_width)); height=$((tty_height));;							#? Use full terminal size for box
			-c|-col) if is_int "$2"; then col=$2; shift; fi;; 												#? Column position to start box
			-l|-line) if is_int "$2"; then line=$2; shift; fi;; 											#? Line position to start box
			-w|-width) if is_int "$2"; then width=$2; shift; fi;; 											#? Width of box
			-h|-height) if is_int "$2"; then height=$2; shift; fi;; 										#? Height of box
			-t|-title) if [[ -n $2 ]]; then title="$2"; shift; fi;;											#? Draw title without titlebar
			-s|-single) ltype="single";;																	#? Use single lines
			-d|-double) ltype="double";;																	#? Use double lines
			-lc|-line-color) line_color="$2"; shift;;														#? Color of the lines
			-fill) fill=1;;																					#? Fill background of box
			-v|-variable) local -n box_out=$2; ext_var=1; shift;;											#? Output box to a variable
		esac
		shift
	done
	if [[ -z $col || -z $line || -z $width || -z $height ]]; then return; fi

	ltype=${ltype:-"single"}
	vlines+=("$col" "$((col+width-1))")
	hlines+=("$line" "$((line+height-1))")

	print -v box_out -rs

	#* Fill box if enabled
	if [[ -n $fill ]]; then
		for((i=line+1;i<line+height-1;i++)); do
			print -v box_out -m $i $((col+1)) -rp $((width-2)) -t " "
		done
	fi

	#* Draw all horizontal lines
	print -v box_out -fg ${line_color:-${theme[div_line]}}
	for hpos in "${hlines[@]}"; do
		print -v box_out -m $hpos $col -rp $((width-1)) -t "${box[${ltype}_hor_line]}"
	done

	#* Draw all vertical lines
	for vpos in "${vlines[@]}"; do
		print -v box_out -m $line $vpos
		for((hpos=line;hpos<=line+height-1;hpos++)); do
			print -v box_out -m $hpos $vpos -t "${box[${ltype}_vert_line]}"
		done
	done

	#* Draw corners
	print -v box_out -m $line $col -t "${box[${ltype}_left_corner_up]}"
	print -v box_out -m $line $((col+width-1)) -t "${box[${ltype}_right_corner_up]}"
	print -v box_out -m $((line+height-1)) $col -t "${box[${ltype}_left_corner_down]}"
	print -v box_out -m $((line+height-1)) $((col+width-1)) -t "${box[${ltype}_right_corner_down]}"

	#* Draw small title without titlebar
	if [[ -n $title ]]; then
		print -v box_out -m $line $((col+2)) -t "┤" -fg ${theme[title]} -b -t "$title" -rs -fg ${line_color:-${theme[div_line]}} -t "├"
	fi

	print -v box_out -rs -m $((line+1)) $((col+1))

	if [[ -z $ext_var ]]; then echo -en "${box_out}"; fi
}

function create_meter() { 	#? Create a horizontal percentage meter, usage; create_meter <value 0-100>
					#? Optional arguments: [-p, -place <line> <col>] [-w, -width <columns>] [-f, -fill-empty]
					#? [-c, -color "array-name"] [-i, -invert-color] [-v, -variable "variable-name"]
	if [[ -z $1 ]]; then return; fi
	local val width colors color block="■" i fill_empty col line var ext_var out meter_var print_var invert bg_color=${theme[inactive_fg]}

	#* Argument parsing
	until (($#==0)); do
		case $1 in
			-p|-place) if is_int "${@:2:2}"; then line=$2; col=$3; shift 2; fi;;								#? Placement for meter
			-w|-width) width=$2; shift;;																		#? Width of meter in columns
			-c|-color) local -n colors=$2; shift;;																#? Name of an array containing colors from index 0-100
			-i|-invert) invert=1;;																				#? Invert meter
			-f|-fill-empty) fill_empty=1;;																		#? Fill unused space with dark blocks
			-v|-variable) local -n meter_var=$2; ext_var=1; shift;;												#? Output meter to a variable
			*) if is_int "$1"; then val=$1; fi;;
		esac
		shift
	done

	if [[ -z $val ]]; then return; fi

	#* Set default width if not given
	width=${width:-10}

	#* If no color array was given, create a simple greyscale array
	if [[ -z $colors ]]; then
		for ((i=0,ic=50;i<=100;i++,ic=ic+2)); do
			colors[i]="${ic} ${ic} ${ic}"
		done
	fi

	#* Create the meter
	meter_var=""
	if [[ -n $line && -n $col ]]; then print -v meter_var -rs -m $line $col
	else print -v meter_var -rs; fi

	if [[ -n $invert ]]; then print -v meter_var -r $((width+1)); fi
	for((i=1;i<=width;i++)); do
		if [[ -n $invert ]]; then print -v meter_var -l 2; fi

		if ((val>=i*100/width)); then
			print -v meter_var -fg ${colors[$((i*100/width))]} -t "${block}"
		elif ((fill_empty==1)); then
			if [[ -n $invert ]]; then print -v meter_var -l $((width-i)); fi
			print -v meter_var -fg $bg_color -rp $((1+width-i)) -t "${block}"; break
		else
			if [[ -n $invert ]]; then break; print -v meter_var -l $((1+width-i))
			else print -v meter_var -r $((1+width-i)); break; fi
		fi
	done
	if [[ -z $ext_var ]]; then echo -en "${meter_var}"; fi
}

function create_graph() { 	#? Create a graph from an array of percentage values, usage; 	create_graph <options> <value-array>
					#? Create a graph from an array of non percentage values:       create_graph <options> <-max "max value"> <value-array>
					#? Add a value to existing graph; 								create_graph [-i, -invert] [-max "max value"] -add-value "graph_array" <value>
					#? Add last value from an array to existing graph; 				create_graph [-i, -invert] [-max "max value"] -add-last "graph_array" "value-array"
					#? Options: < -d, -dimensions <line> <col> <height> <width> > [-i, -invert] [-n, -no-guide] [-c, -color "array-name"] [-o, -output-array "variable-name"]
	if [[ -z $1 ]]; then return; fi
	if [[ ${graph[hires]} == true ]]; then create_graph_hires "$@"; return; fi

	local val col s_col line s_line height s_height width s_width colors color i var ext_var out side_num side_nums=1 add add_array invert no_guide max
	local -a graph_array input_array

	#* Argument parsing
	until (($#==0)); do
		case $1 in
			-d|-dimensions) if is_int "${@:2:4}"; then line=$2; col=$3; height=$4; width=$5; shift 4; fi;;						#? Graph dimensions
			-c|-color) local -n colors=$2; shift;;																				#? Name of an array containing colors from index 0-100
			-o|-output-array) local -n output_array=$2; ext_var=1; shift;;														#? Output meter to an array
			-add-value) if is_int "$3"; then local -n output_array=$2; add=$3; break; else return; fi;;							#? Add a value to existing graph
			-add-last) local -n output_array=$2; local -n add_array=$3; add=${add_array[-1]}; break;;							#? Add last value from array to existing graph
			-i|-invert) invert=1;;																								#? Invert graph, drawing from top to bottom
			-n|-no-guide) no_guide=1;;																							#? Don't print side and bottom guide lines
			-max) if is_int "$2"; then max=$2; shift; fi;;																		#? Needed max value for non percentage arrays
			*) local -n tmp_in_array=$1; input_array=("${tmp_in_array[@]}");;
		esac
		shift
	done

	if [[ -z $no_guide ]]; then
		((--height))
	else
		if [[ -n $invert ]]; then ((line--)); fi
	fi


	if ((width<3)); then width=3; fi
	if ((height<1)); then height=1; fi


	#* If argument "add" was passed check for existing graph and make room for new value(s)
	local add_start add_end
	if [[ -n $add ]]; then
		local cut_left search
		if [[ -n ${input_array[0]} ]]; then return; fi
		if [[ -n $output_array ]]; then
			graph_array=("${output_array[@]}")
			if [[ -z ${graph_array[0]} ]]; then return; fi
		else
			return
		fi
		height=$((${#graph_array[@]}-1))
		input_array[0]=${add}

		#* Remove last value in current graph

		for ((i=0;i<height;i++)); do
			cut_left="${graph_array[i]%m*}"
			search=$((${#cut_left}+1))
			graph_array[i]="${graph_array[i]::$search}${graph_array[i]:$((search+1))}"
		done

	fi

	#* Initialize graph if no "add" argument was given
	if [[ -z $add ]]; then
		#* Scale down graph one line if height is even
		local inv_offset h_inv normal_vals=1
		local -a side_num=(100 0) g_char=(" ⡇" " ⠓" "⠒") g_index

		if [[ -n $invert ]]; then
			for((i=height;i>=0;i--)); do
				g_index+=($i)
			done

		else
			for((i=0;i<=height;i++)); do
				g_index+=($i)
			done
		fi

		if [[ -n $no_guide ]]; then unset normal_vals
		elif [[ -n $invert ]]; then g_char=(" ⡇" " ⡤" "⠤")
		fi

		#* Set up graph array print side numbers and lines
		print -v graph_array[0] -rs
		print -v graph_array[0] -m $((line+g_index[0])) ${col} ${normal_vals:+-jr 3 -fg "#ee" -b -t "${side_num[0]}" -rs -fg ${theme[main_fg]} -t "${g_char[0]}"} -fg ${colors[100]}
		for((i=1;i<height;i++)); do
			print -v graph_array[i] -m $((line+g_index[i])) ${col} ${normal_vals:+-r 3 -fg ${theme[main_fg]} -t "${g_char[0]}"} -fg ${colors[$((100-i*100/height))]}
		done

		if [[ -z $no_guide ]]; then width=$((width-5)); fi

		graph_array[height]=""
		if [[ -z $no_guide ]]; then
			print -v graph_array[$height] -m $((line+g_index[(-1)])) ${col} -jr 3 -fg "#ee" -b -t "${side_num[1]}" -rs -fg ${theme[main_fg]} -t "${g_char[1]}" -rp ${width} -t "${g_char[2]}"
		fi

		#* If no color array was given, create a simple greyscale array
		if [[ -z $colors ]]; then
			for ((i=0,ic=50;i<=100;i++,ic=ic+2)); do
				colors[i]="${ic} ${ic} ${ic}"
			done
		fi
	fi

	#* Create the graph
	local value_width x y a cur_value prev_value=100 symbol tmp_out compare found count virt_height=$((height*10))
	if [[ -n $add ]]; then
		value_width=1
	elif ((${#input_array[@]}<=width)); then
		value_width=${#input_array[@]};
	else
		value_width=${width}
		input_array=("${input_array[@]:(-$width)}")
	fi

	if [[ -n $invert ]]; then
		y=$((height-1))
		done_val="-1"
	else
		y=0
		done_val=$height
	fi

	#* Convert input array to percentage values of max if a max value was given
	if [[ -n $max ]]; then
		for((i=0;i<${#input_array[@]};i++)); do
			if ((input_array[i]>=max)); then
				input_array[i]=100
			else
				input_array[i]=$((input_array[i]*100/max))
			fi
		done
	fi

	until ((y==done_val)); do

		#* Print spaces to right-justify graph if number of values is less than graph width
		if [[ -z $add ]] && ((value_width<width)); then print -v graph_array[y] -rp $((width-value_width)) -t " "; fi

		cur_value=$(( virt_height-(y*10) ))
		next_value=$(( virt_height-((y+1)*10) ))

		count=0
		x=0

		#* Create graph by walking through all values for each line, speed up by counting similar values and print once, when difference is met
		while ((x<value_width)); do

			if [[ -z ${input_array[x]} ]] || ((input_array[x]<1)) || ((${#input_array[x]}>3)); then input_array[x]=0; fi

			#* Print empty space if current value is less than percentage for current line
			while ((x<value_width & input_array[x]*virt_height/100<next_value)); do
				((++count))
				((++x))
			done
			if ((count>0)); then
				print -v graph_array[y] -rp ${count} -t " "
				count=0
			fi

			#* Print current value in percent relative to graph size if current value is less than line percentage but greater than next line percentage
			while ((x<value_width & input_array[x]*virt_height/100<cur_value & input_array[x]*virt_height/100>=next_value)); do
				print -v graph_array[y] -t "${graph_symbol[${invert:+-}$(( (input_array[x]*virt_height/100)-next_value ))]}"
				((++x))
			done

			#* Print full block if current value is greater than percentage for current line
			while ((x<value_width & input_array[x]*virt_height/100>=cur_value)); do
				((++count))
				((++x))
			done
			if ((count>0)); then
				print -v graph_array[y] -rp ${count} -t "${graph_symbol[10]}"
				count=0
			fi
		done

	if [[ -n $invert ]]; then
		((y--)) || true
	else
		((++y))
	fi
	done

	#* Echo out graph if no argument for a output array was given
	if [[ -z $ext_var && -z $add ]]; then echo -en "${graph_array[*]}"
	else output_array=("${graph_array[@]}"); fi
}

function create_mini_graph() { 	#? Create a one line high graph from an array of percentage values, usage; 	create_mini_graph <options> <value-array>
						#? Add a value to existing graph; 						create_mini_graph [-i, -invert] [-nc, -no-color] [-c, -color "array-name"] -add-value "graph_variable" <value>
						#? Add last value from an array to existing graph; 		create_mini_graph [-i, -invert] [-nc, -no-color] [-c, -color "array-name"] -add-last "graph_variable" "value-array"
						#? Options: [-w, -width <width>] [-i, -invert] [-nc, -no-color] [-c, -color "array-name"] [-o, -output-variable "variable-name"]
	if [[ -z $1 ]]; then return; fi

	if [[ ${graph[hires]} == true ]]; then create_mini_graph_hires "$@"; return; fi

	local val col s_col line s_line height s_height width s_width colors color i var ext_var out side_num side_nums=1 add invert no_guide graph_var no_color color_value

	#* Argument parsing
	until (($#==0)); do
		case $1 in
			-w|-width) if is_int "$2"; then width=$2; shift; fi;;									 						#? Graph width
			-c|-color) local -n colors=$2; shift;;																			#? Name of an array containing colors from index 0-100
			-nc|-no-color) no_color=1;;																						#? Set no color
			-o|-output-variable) local -n output_var=$2; ext_var=1; shift;;													#? Output graph to a variable
			-add-value) if is_int "$3"; then local -n output_var=$2; add=$3; break; else return; fi;;						#? Add a value to existing graph
			-add-last) local -n output_var=$2 add_array=$3; add="${add_array[-1]}"; break;; 								#? Add last value from array to existing graph
			-i|-invert) invert=1;;																							#? Invert graph, drawing from top to bottom
			*) local -n input_array=$1;;
		esac
		shift
	done

	if ((width<1)); then width=1; fi

	#* If argument "add" was passed check for existing graph and make room for new value(s)
	local add_start add_end
	if [[ -n $add ]]; then
		local cut_left search
		#if [[ -n ${input_array[0]} ]]; then return; fi
		if [[ -n $output_var ]]; then
			graph_var="${output_var}"
			if [[ -z ${graph_var} ]]; then return; fi
		else
			return
		fi

		declare -a input_array
		input_array[0]=${add}

		#* Remove last value in current graph
		if [[ -n ${graph_var} && -z $no_color ]]; then
			if [[ ${graph_var::5} == "\e[1C" ]]; then
				graph_var="${graph_var#'\e[1C'}"
			else
				cut_left="${graph_var%%m*}"
				search=$((${#cut_left}+1))
				graph_var="${graph_var:$((search+1))}"
			fi
		elif [[ -n ${graph_var} && -n $no_color ]]; then
			if [[ ${graph_var::5} == "\e[1C" ]]; then
				#cut_left="${graph_var%%C*}"
				#search=$((${#cut_left}+1))
				#graph_var="${graph_var:$((search))}"
				graph_var="${graph_var#'\e[1C'}"
			else
				graph_var="${graph_var:1}"
			fi
		fi
	fi


	#* If no color array was given, create a simple greyscale array
	if [[ -z $colors && -z $no_color ]]; then
		for ((i=0,ic=50;i<=100;i++,ic=ic+2)); do
			colors[i]="${ic} ${ic} ${ic}"
		done
	fi


	#* Create the graph
	local value_width x=0 y a cur_value virt_height=$((height*10)) offset=0 org_value
	if [[ -n $add ]]; then
		value_width=1
	elif ((${#input_array[@]}<=width)); then
		value_width=${#input_array[@]};
	else
		value_width=${width}
		offset=$((${#input_array[@]}-width))
	fi

	#* Print spaces to right-justify graph if number of values is less than graph width
		if [[ -z $add && -z $no_color ]] && ((value_width<width)); then print -v graph_var -rp $((width-value_width)) -t "\e[1C"
		elif [[ -z $add && -n $no_color ]] && ((value_width<width)); then print -v graph_var -rp $((width-value_width)) -t "\e[1C"; fi
		#* Create graph
		while ((x<value_width)); do
			#* Round current input_array value divided by 10 to closest whole number
			org_value=${input_array[offset+x]}
			if ((org_value<=0)); then org_value=0; fi
			if ((org_value>=100)); then cur_value=10; org_value=100
			elif [[ ${#org_value} -gt 1 && ${org_value:(-1)} -ge 5 ]]; then cur_value=$((${org_value::1}+1))
			elif [[ ${#org_value} -gt 1 && ${org_value:(-1)} -lt 5 ]]; then cur_value=$((${org_value::1}))
			elif [[ ${org_value:(-1)} -ge 5 ]]; then cur_value=1
			else cur_value=0
			fi
			if [[ -z $no_color ]]; then
				color="-fg ${colors[$org_value]} "
			else
				color=""
			fi

			if [[ $cur_value == 0 ]]; then
				print -v graph_var -t "\e[1C"
			else
				print -v graph_var ${color}-t "${graph_symbol[${invert:+-}$cur_value]}"
			fi
			((++x))
		done

	#* Echo out graph if no argument for a output array was given
	if [[ -z $ext_var && -z $add ]]; then echo -en "${graph_var}"
	else output_var="${graph_var}"; fi
}

function create_graph_hires() { 	#? Create a graph from an array of percentage values, usage; 	create_graph <options> <value-array>
					#? Create a graph from an array of non percentage values:       create_graph <options> <-max "max value"> <value-array>
					#? Add a value to existing graph; 								create_graph [-i, -invert] [-max "max value"] -add-value "graph_array" <value>
					#? Add last value from an array to existing graph; 				create_graph [-i, -invert] [-max "max value"] -add-last "graph_array" "value-array"
					#? Options: < -d, -dimensions <line> <col> <height> <width> > [-i, -invert] [-n, -no-guide] [-c, -color "array-name"] [-o, -output-array "variable-name"]
	if [[ -z $1 ]]; then return; fi
	local val col s_col line s_line height s_height width s_width colors color var ext_var out side_num side_nums=1 add add_array invert no_guide max graph_name offset=0 last_val
	local -a input_array
	local -i i

	#* Argument parsing
	until (($#==0)); do
		case $1 in
			-d|-dimensions) if is_int "${@:2:4}"; then line=$2; col=$3; height=$4; width=$5; shift 4; fi;;						#? Graph dimensions
			-c|-color) local -n colors=$2; shift;;																				#? Name of an array containing colors from index 0-100
			-o|-output-array) local -n output_array=$2; graph_name=$2; ext_var=1; shift;;										#? Output meter to an array
			-add-value) if is_int "$3"; then local -n output_array=$2; graph_name=$2; add=$3; break; else return; fi;;			#? Add a value to existing graph
			-add-last) local -n output_array=$2; graph_name=$2; local -n add_array=$3; add=${add_array[-1]}; break;;			#? Add last value from array to existing graph
			-i|-invert) invert=1;;																								#? Invert graph, drawing from top to bottom
			-n|-no-guide) no_guide=1;;																							#? Don't print side and bottom guide lines
			-max) if is_int "$2"; then max=$2; shift; fi;;																		#? Needed max value for non percentage arrays
			*) local -n tmp_in_array="$1"; input_array=("${tmp_in_array[@]}");;
		esac
		shift
	done

	local -n last_val="graph[${graph_name}_last_val]"
	local -n last_type="graph[${graph_name}_last_type]"


	if [[ -z $add ]]; then
		last_type="even"
		last_val=0
		local -n graph_array="${graph_name}_odd"
		local -n graph_even="${graph_name}_even"
		graph_even=("")
		graph_array=("")
	elif [[ ${last_type} == "even" ]]; then
		local -n graph_array="${graph_name}_odd"
		last_type="odd"
	elif [[ ${last_type} == "odd" ]]; then
		local -n graph_array="${graph_name}_even"
		last_type="even"
	fi

	if [[ -z $no_guide ]]; then ((--height))
	elif [[ -n $invert ]]; then ((line--))
	fi

	if ((width<3)); then width=3; fi
	if ((height<1)); then height=1; fi


	#* If argument "add" was passed check for existing graph and make room for new value(s)
	local add_start add_end
	if [[ -n $add ]]; then
		local cut_left search
		if [[ -n ${input_array[*]} || -z ${graph_array[0]} ]]; then return; fi

		height=$((${#graph_array[@]}-1))
		input_array=("${add}")

		#* Remove last value in current graph

		for ((i=0;i<height;i++)); do
			cut_left="${graph_array[i]%m*}"
			search=$((${#cut_left}+1))
			graph_array[i]="${graph_array[i]::$search}${graph_array[i]:$((search+1))}"
		done

	fi

	#* Initialize graph if no "add" argument was given
	if [[ -z $add ]]; then
		#* Scale down graph one line if height is even
		local inv_offset h_inv normal_vals=1
		local -a side_num=(100 0) g_char=(" ⡇" " ⠓" "⠒") g_index

		if [[ -n $invert ]]; then
			for((i=height;i>=0;i--)); do
				g_index+=($i)
			done

		else
			for((i=0;i<=height;i++)); do
				g_index+=($i)
			done
		fi

		if [[ -n $no_guide ]]; then unset normal_vals
		elif [[ -n $invert ]]; then g_char=(" ⡇" " ⡤" "⠤")
		fi

		#* Set up graph array print side numbers and lines
		print -v graph_array[0] -rs -m $((line+g_index[0])) ${col} ${normal_vals:+-jr 3 -fg "#ee" -b -t "${side_num[0]}" -rs -fg ${theme[main_fg]} -t "${g_char[0]}"} -fg ${colors[100]}
		for((i=1;i<height;i++)); do
			print -v graph_array[i] -m $((line+g_index[i])) ${col} ${normal_vals:+-r 3 -fg ${theme[main_fg]} -t "${g_char[0]}"} -fg ${colors[$((100-i*100/height))]}
		done

		if [[ -z $no_guide ]]; then width=$((width-5)); fi

		graph_array[$height]=""
		if [[ -z $no_guide ]]; then
			print -v graph_array[$height] -m $((line+g_index[(-1)])) ${col} -jr 3 -fg "#ee" -b -t "${side_num[1]}" -rs -fg ${theme[main_fg]} -t "${g_char[1]}" -rp ${width} -t "${g_char[2]}"
		fi

		graph_even=("${graph_array[@]}")

		#* If no color array was given, create a simple greyscale array
		if [[ -z $colors ]]; then
			for ((i=0,ic=50;i<=100;i++,ic=ic+2)); do
				colors[i]="${ic} ${ic} ${ic}"
			done
		fi
	fi

	#* Create the graph
	local value_width next_line prev_value cur_value virt_height=$((height*4)) converted
	local -i x y c_val p_val l_val
	if [[ -n $add ]]; then
		value_width=1
	elif ((${#input_array[@]}<=width*2)); then
		value_width=$((${#input_array[@]}*2))
	else
		value_width=$((width*2))
		input_array=("${input_array[@]:(-${value_width})}")
	fi

	if [[ -z $add ]] && ! ((${#input_array[@]}%2)); then last_val=${input_array[0]}; input_array=("${input_array[@]:1}"); converted=1; fi

	#* Print spaces to right-justify graph if number of values is less than graph width
	if [[ -z $add ]] && ((${#input_array[@]}/2<width)); then
		for((i=0;i<height;i++)); do
			print -v graph_array[i] -rp $((width-1-${#input_array[@]}/2)) -t " "
		done
		graph_even=("${graph_array[@]}")
	fi

	if [[ -n $invert ]]; then
		y=$((height-1))
		done_val="-1"
	else
		y=0
		done_val=$height
	fi

	#* Convert input array to percentage values of max if a max value was given
	if [[ -n $max ]]; then
		for((i=0;i<${#input_array[@]};i++)); do
			if ((input_array[i]>=max)); then
				input_array[i]=100
			else
				input_array[i]=$((input_array[i]*100/max))
			fi
		done
		if [[ -n $converted ]]; then
			last_val=$((${last_val}*100/max))
			if ((${last_val}>100)); then last_val=100; fi
		fi
	fi

	if [[ -n $invert ]]; then local -n symbols=graph_symbol_down
	else local -n symbols=graph_symbol_up
	fi

	until ((y==done_val)); do

		next_line=$(( virt_height-((y+1)*4) ))
		unset p_val

		#* Create graph by walking through all values for each line
		for ((x=0;x<${#input_array[@]};x++)); do
			c_val=${input_array[x]}
			p_val=${p_val:-${last_val}}
			cur_value="$((c_val*virt_height/100-next_line))"
			prev_value=$((p_val*virt_height/100-next_line))

			if ((cur_value<0)); then cur_value=0
			elif ((cur_value>4)); then cur_value=4; fi
			if ((prev_value<0)); then prev_value=0
			elif ((prev_value>4)); then prev_value=4; fi

			if [[ -z $add ]] && ((x==0)); then
				print -v graph_even[y] -t "${symbols[${prev_value}_${cur_value}]}"
				print -v graph_array[y] -t "${symbols[0_${prev_value}]}"
			elif [[ -z $add ]] && ! ((x%2)); then
				print -v graph_even[y] -t "${symbols[${prev_value}_${cur_value}]}"
			else
				print -v graph_array[y] -t "${symbols[${prev_value}_${cur_value}]}"
			fi

			if [[ -z $add ]]; then p_val=${input_array[x]}; else unset p_val; fi

		done

		if [[ -n $invert ]]; then
			((y--)) || true
		else
			((++y))
		fi

	done

	if [[ -z $add && ${last_type} == "even" ]]; then
		declare -n graph_array="${graph_name}_even"
	fi

	last_val=$c_val

	output_array=("${graph_array[@]}")
}

function create_mini_graph_hires() { 	#? Create a one line high graph from an array of percentage values, usage; 	create_mini_graph <options> <value-array>
						#? Add a value to existing graph; 						create_mini_graph [-i, -invert] [-nc, -no-color] [-c, -color "array-name"] -add-value "graph_variable" <value>
						#? Add last value from an array to existing graph; 		create_mini_graph [-i, -invert] [-nc, -no-color] [-c, -color "array-name"] -add-last "graph_variable" "value-array"
						#? Options: [-w, -width <width>] [-i, -invert] [-nc, -no-color] [-c, -color "array-name"] [-o, -output-variable "variable-name"]
	if [[ -z $1 ]]; then return; fi
	local val col s_col line s_line height s_height width s_width colors color var ext_var out side_num side_nums=1 add invert no_guide graph_var no_color color_value graph_name
	local -a input_array
	local -i i

	#* Argument parsing
	until (($#==0)); do
		case $1 in
			-w|-width) if is_int "$2"; then width=$2; shift; fi;;									 						#? Graph width
			-c|-color) local -n colors=$2; shift;;																			#? Name of an array containing colors from index 0-100
			-nc|-no-color) no_color=1;;																						#? Set no color
			-o|-output-variable) local -n output_var=$2; graph_name=$2; ext_var=1; shift;;									#? Output graph to a variable
			-add-value) if is_int "$3"; then local -n output_var=$2; graph_name=$2; add=$3; break; else return; fi;;		#? Add a value to existing graph
			-add-last) local -n output_var=$2; local -n add_array=$3; graph_name=$2; add="${add_array[-1]:-0}"; break;; 		#? Add last value from array to existing graph
			-i|-invert) invert=1;;																							#? Invert graph, drawing from top to bottom
			*) local -n tmp_in_arr=$1; input_array=("${tmp_in_arr[@]}");;
		esac
		shift
	done

	local -n last_val="${graph_name}_last_val"
	local -n last_type="${graph_name}_last_type"

	if [[ -z $add ]]; then
		last_type="even"
		last_val=0
		local -n graph_var="${graph_name}_odd"
		local -n graph_other="${graph_name}_even"
		graph_var=""; graph_other=""
	elif [[ ${last_type} == "even" ]]; then
		local -n graph_var="${graph_name}_odd"
		last_type="odd"
	elif [[ ${last_type} == "odd" ]]; then
		local -n graph_var="${graph_name}_even"
		last_type="even"
	fi

	if ((width<1)); then width=1; fi

	#* If argument "add" was passed check for existing graph and make room for new value(s)
	local add_start add_end
	if [[ -n $add ]]; then
		local cut_left search
		input_array[0]=${add}

		#* Remove last value in current graph
		if [[ -n ${graph_var} && -z $no_color ]]; then
			if [[ ${graph_var::5} == '\e[1C' ]]; then
				graph_var="${graph_var#'\e[1C'}"
			else
				cut_left="${graph_var%m*}"
				search=$((${#cut_left}+1))
				graph_var="${graph_var::$search}${graph_var:$((search+1))}"
			fi
		elif [[ -n ${graph_var} && -n $no_color ]]; then
			if [[ ${graph_var::5} == "\e[1C" ]]; then
				#cut_left="${graph_var%%C*}"
				#search=$((${#cut_left}+1))
				#graph_var="${graph_var:$((search))}"
				graph_var="${graph_var#'\e[1C'}"
			else
				graph_var="${graph_var:1}"
			fi
		fi
	fi


	#* If no color array was given, create a simple greyscale array
	if [[ -z $colors && -z $no_color ]]; then
		for ((i=0,ic=50;i<=100;i++,ic=ic+2)); do
			colors[i]="${ic} ${ic} ${ic}"
		done
	fi


	#* Create the graph
	local value_width x=0 y a cur_value prev_value p_val c_val acolor jump odd offset=0
	if [[ -n $add ]]; then
		value_width=1
	elif ((${#input_array[@]}<=width*2)); then
		value_width=$((${#input_array[@]}*2))
	else
		value_width=$((width*2))
		input_array=("${input_array[@]:(-${value_width})}")
	fi

	if [[ -z $add ]] && ! ((${#input_array[@]}%2)); then last_val=${input_array[0]}; input_array=("${input_array[@]:1}"); fi

	#* Print spaces to right-justify graph if number of values is less than graph width
	if [[ -z $add ]] && ((${#input_array[@]}/2<width)); then print -v graph_var -rp $((width-1-${#input_array[@]}/2)) -t "\e[1C"; graph_other="${graph_var}"; fi

	if [[ -n $invert ]]; then local -n symbols=graph_symbol_down
	else local -n symbols=graph_symbol_up
	fi

	unset p_val

	#* Create graph
	for((i=0;i<${#input_array[@]};i++)); do

		c_val=${input_array[i]}
		p_val=${p_val:-${last_val}}

		if ((c_val>=85)); then cur_value=4
		elif ((c_val>=60)); then cur_value=3
		elif ((c_val>=30)); then cur_value=2
		elif ((c_val>=10)); then cur_value=1
		elif ((c_val<10)); then cur_value=0; fi

		if ((p_val>=85)); then prev_value=4
		elif ((p_val>=60)); then prev_value=3
		elif ((p_val>=30)); then prev_value=2
		elif ((p_val>=10)); then prev_value=1
		elif ((p_val<10)); then prev_value=0; fi

		if [[ -z $no_color ]]; then
			if ((c_val>p_val)); then acolor=$((c_val-p_val))
			else acolor=$((p_val-c_val)); fi
			if ((acolor>100)); then acolor=100; elif ((acolor<0)); then acolor=0; fi
			color="-fg ${colors[${acolor:-0}]} "
		else
			unset color
		fi

		if ((cur_value==0 & prev_value==0)); then jump="\e[1C"; else unset jump; fi

		if [[ -z $add ]] && ((i==0)); then
			print -v graph_other ${color}-t "${jump:-${symbols[${prev_value}_${cur_value}]}}"
			print -v graph_var ${color}-t "${jump:-${symbols[0_${prev_value}]}}"
		elif [[ -z $add ]] && ((i%2)); then
			print -v graph_other ${color}-t "${jump:-${symbols[${prev_value}_${cur_value}]}}"
		else
			print -v graph_var ${color}-t "${jump:-${symbols[${prev_value}_${cur_value}]}}"
		fi

		if [[ -z $add ]]; then p_val=$c_val; else unset p_val; fi
	done

	#if [[ -z $add ]]; then
	#	declare -n graph_var="${graph_name}_even"
	# 	#echo "yup" >&2
	#fi

	last_val=$c_val

	output_var="${graph_var}"
}

function print() {	
	#? Print text, set true-color foreground/background color, add effects, center text, move cursor, save cursor position and restore cursor postion
	#? Effects: [-fg, -foreground <RGB Hex>|<R Dec> <G Dec> <B Dec>] [-bg, -background <RGB Hex>|<R Dec> <G Dec> <B Dec>] [-rs, -reset] [-/+b, -/+bold] [-/+da, -/+dark]
	#? [-/+ul, -/+underline] [-/+i, -/+italic] [-/+bl, -/+blink] [-f, -font "sans-serif|script|fraktur|monospace|double-struck"]
	#? Manipulation: [-m, -move <line> <column>] [-l, -left <x>] [-r, -right <x>] [-u, -up <x>] [-d, -down <x>] [-c, -center] [-sc, -save] [-rc, -restore]
	#? [-jl, -justify-left <width>] [-jr, -justify-right <width>] [-jc, -justify-center <width>] [-rp, -repeat <x>]
	#? Text: [-v, -variable "variable-name"] [-stdin] [-t, -text "string"] ["string"]

	#* Return if no arguments is given
	if [[ -z $1 ]]; then return; fi

	#* Just echo and return if only one argument and not a valid option
	if [[ $# -eq 1 && ${1::1} != "-"  ]]; then echo -en "$1"; return; fi

	local effect color add_command text text2 esc center clear fgc bgc fg_bg_div tmp tmp_len bold italic custom_font val var out ext_var hex="16#"
	local justify_left justify_right justify_center repeat r_tmp trans


	#* Loop function until we are out of arguments
	until (($#==0)); do

		#* Argument parsing
		until (($#==0)); do
			case $1 in
				-t|-text) text="$2"; shift 2; break;;																#? String to print
				-stdin) text="$(</dev/stdin)"; shift; break;;																				#? Print from stdin
				-fg|-foreground)	#? Set text foreground color, accepts either 6 digit hexadecimal "#RRGGBB", 2 digit hex (greyscale) or decimal RGB "<0-255> <0-255> <0-255>"
					if [[ ${2::1} == "#" ]]; then
						val=${2//#/}
						if [[ ${#val} == 6 ]]; then fgc="\e[38;2;$((${hex}${val:0:2}));$((${hex}${val:2:2}));$((${hex}${val:4:2}))m"; shift
						elif [[ ${#val} == 2 ]]; then fgc="\e[38;2;$((${hex}${val:0:2}));$((${hex}${val:0:2}));$((${hex}${val:0:2}))m"; shift
						fi
					elif is_int "${@:2:3}"; then fgc="\e[38;2;$2;$3;$4m"; shift 3
					fi
					;;
				-bg|-background)	#? Set text background color, accepts either 6 digit hexadecimal "#RRGGBB", 2 digit hex (greyscale) or decimal RGB "<0-255> <0-255> <0-255>"
					if [[ ${2::1} == "#" ]]; then
						val=${2//#/}
						if [[ ${#val} == 6 ]]; then bgc="\e[48;2;$((${hex}${val:0:2}));$((${hex}${val:2:2}));$((${hex}${val:4:2}))m"; shift
						elif [[ ${#val} == 2 ]]; then bgc="\e[48;2;$((${hex}${val:0:2}));$((${hex}${val:0:2}));$((${hex}${val:0:2}))m"; shift
						fi
					elif is_int "${@:2:3}"; then bgc="\e[48;2;$2;$3;$4m"; shift 3
					fi
					;;
				-c|-center) center=1;;																										#? Center text horizontally on screen
				-rs|-reset) effect="0${effect}${theme[main_bg]}";;																			#? Reset text colors and effects
				-b|-bold) effect="${effect}${effect:+;}1"; bold=1;;																			#? Enable bold text
				+b|+bold) effect="${effect}${effect:+;}21"; bold=0;;																		#? Disable bold text
				-da|-dark) effect="${effect}${effect:+;}2";;																				#? Enable dark text
				+da|+dark) effect="${effect}${effect:+;}22";;																				#? Disable dark text
				-i|-italic) effect="${effect}${effect:+;}3"; italic=1;;																		#? Enable italic text
				+i|+italic) effect="${effect}${effect:+;}23"; italic=0;;																	#? Disable italic text
				-ul|-underline) effect="${effect}${effect:+;}4";;																			#? Enable underlined text
				+ul|+underline) effect="${effect}${effect:+;}24";;																			#? Disable underlined text
				-bl|-blink) effect="${effect}${effect:+;}5";;																				#? Enable blinking text
				+bl|+blink) effect="${effect}${effect:+;}25";;																				#? Disable blinking text
				-f|-font) if [[ $2 =~ ^(sans-serif|script|fraktur|monospace|double-struck)$ ]]; then custom_font="$2"; shift; fi;;			#? Set custom font
				-m|-move) add_command="${add_command}\e[${2};${3}f"; shift 2;;																#? Move to postion "LINE" "COLUMN"
				-l|-left) add_command="${add_command}\e[${2}D"; shift;;																		#? Move left x columns
				-r|-right) add_command="${add_command}\e[${2}C"; shift;;																	#? Move right x columns
				-u|-up) add_command="${add_command}\e[${2}A"; shift;;																		#? Move up x lines
				-d|-down) add_command="${add_command}\e[${2}B"; shift;;																		#? Move down x lines
				-jl|-justify-left) justify_left="${2}"; shift;;																				#? Justify string left within given width
				-jr|-justify-right) justify_right="${2}"; shift;;																			#? Justify string right within given width
				-jc|-justify-center) justify_center="${2}"; shift;;																			#? Justify string center within given width
				-rp|-repeat) repeat=${2}; shift;;																							#? Repeat next string x number of times
				-sc|-save) add_command="\e[s${add_command}";;																				#? Save cursor position
				-rc|-restore) add_command="${add_command}\e[u";;																			#? Restore cursor position
				-trans) trans=1;;																											#? Make whitespace transparent
				-v|-variable) local -n var=$2; ext_var=1; shift;;																			#? Send output to a variable, appending if not unset
				*) text="$1"; shift; break;;																								#? Assumes text string if no argument is found
			esac
			shift
		done

		#* Repeat string if repeat is enabled
		if [[ -n $repeat ]]; then
			printf -v r_tmp "%${repeat}s" ""
			text="${r_tmp// /$text}"
		fi

		#* Set correct placement for screen centered text
		if ((center==1 & ${#text}>0 & ${#text}<tty_width-4)); then
			add_command="${add_command}\e[${tty_width}D\e[$(( (tty_width/2)-(${#text}/2) ))C"
		fi

		#* Convert text string to custom font if set and remove non working effects
		if [[ -n $custom_font ]]; then
			unset effect
			text=$(set_font "${custom_font}${bold:+" bold"}${italic:+" italic"}" "${text}")
		fi

		#* Set text justification if set
		if [[ -n $justify_left ]] && ((${#text}<justify_left)); then
			printf -v text "%s%$((justify_left-${#text}))s" "${text}" ""
		elif [[ -n $justify_right ]] && ((${#text}<justify_right)); then
			printf -v text "%$((justify_right-${#text}))s%s" "" "${text}"
		elif [[ -n $justify_center ]] && ((${#text}<justify_center)); then
			printf -v text "%$(( (justify_center/2)-(${#text}/2) ))s%s" "" "${text}"
			printf -v text "%s%-$((justify_center-${#text}))s" "${text}" ""
		fi

		if [[ -n $trans ]]; then
			text="${text// /'\e[1C'}"
		fi

		#* Create text string
		if [[ -n $effect ]]; then effect="\e[${effect}m"; fi
		out="${out}${add_command}${effect}${bgc}${fgc}${text}"
		unset add_command effect fgc bgc center justify_left justify_right justify_center custom_font text repeat trans justify
	done

	#* Print the string to stdout if variable out hasn't been set
	if [[ -z $ext_var ]]; then echo -en "$out"
	else var="${var}${out}"; fi

}

function sarah_draw_bg() {
	#? Draw all box outlines
	local this_box cpu_p_width i cpu_model_len

	unset boxes_out
	for this_box in ${sarah_box[boxes]}; do
		create_box -v boxes_out -col ${box[${this_box}_col]} -line ${box[${this_box}_line]} -width ${box[${this_box}_width]} -height ${box[${this_box}_height]} -fill -lc "${box[${this_box}_color]}" -title ${this_box}
	done

}

function bashtop_draw_bg() { 
	#? Draw all box outlines
	local this_box cpu_p_width i cpu_model_len

	unset boxes_out
	for this_box in ${box[boxes]}; do
		create_box -v boxes_out -col ${box[${this_box}_col]} -line ${box[${this_box}_line]} -width ${box[${this_box}_width]} -height ${box[${this_box}_height]} -fill -lc "${box[${this_box}_color]}" -title ${this_box}
	done

	#* Misc cpu box
	if [[ $check_temp == true ]]; then cpu_model_len=18; else cpu_model_len=9; fi
	create_box -v boxes_out -col $((box[p_col]-1)) -line $((box[p_line]-1)) -width ${box[p_width]} -height ${box[p_height]} -lc ${theme[div_line]} -t "${cpu[model]:0:${cpu_model_len}}"
	print -v boxes_out -m ${box[cpu_line]} $((box[cpu_col]+10)) -rs -fg ${box[cpu_color]} -t "┤" -b -fg ${theme[hi_fg]} -t "m" -fg ${theme[title]} -t "enu" -rs -fg ${box[cpu_color]} -t "├"

	#* Misc mem
	print -v boxes_out -m ${box[mem_line]} $((box[mem_col]+box[m_width]+2)) -rs -fg ${box[mem_color]} -t "┤" -fg ${theme[title]} -b -t "${lang_title_disk}" -rs -fg ${box[mem_color]} -t "├"
	print -v boxes_out -m ${box[mem_line]} $((box[mem_col]+box[m_width])) -rs -fg ${box[mem_color]} -t "┬"
	print -v boxes_out -m $((box[mem_line]+box[mem_height]-1)) $((box[mem_col]+box[m_width])) -fg ${box[mem_color]} -t "┴"
	for((i=1;i<=box[mem_height]-2;i++)); do
		print -v boxes_out -m $((box[mem_line]+i)) $((box[mem_col]+box[m_width])) -fg ${theme[div_line]} -t "│"
	done

	#* Misc net box
	create_box -v boxes_out -col $((box[n_col]-1)) -line $((box[n_line]-1)) -width ${box[n_width]} -height ${box[n_height]} -lc ${theme[div_line]} -t "${lang_title_download}"
	print -v boxes_out -m $((box[n_line]+box[n_height]-2)) $((box[n_col]+1)) -rs -fg ${theme[div_line]} -t "┤" -fg ${theme[title]} -b -t "${lang_title_upload}" -rs -fg ${theme[div_line]} -t "├"

	if [[ $1 == "quiet" ]]; then draw_out="${boxes_out}"
	else echo -en "${boxes_out}"; fi
	draw_update_string $1
}

function draw_cpu() { #? Draw cpu and core graphs and print percentages
	local cpu_out i name cpu_p_color temp_color y pt_line pt_col p_normal_color="${theme[main_fg]}" threads=${cpu[threads]}
	local meter meter_size meter_width temp_var cpu_out_var core_name temp_name temp_width

	#* Get variables from previous calculations
	local col=$((box[cpu_col]+1)) line=$((box[cpu_line]+1)) width=$((box[cpu_width]-2)) height=$((box[cpu_height]-2))
	local p_width=${box[p_width]} p_height=${box[p_height]} p_col=${box[p_col]} p_line=${box[p_line]}

	#* If resized recreate cpu meter/graph box, cpu graph and core graphs
	if ((resized>0)); then
		local graph_a_size graph_b_size
		graph_a_size=$((height/2)); graph_b_size=${graph_a_size}

		if ((graph_a_size*2<height)); then ((graph_a_size++)); fi
		create_graph -o cpu_graph_a -d ${line} ${col} ${graph_a_size} $((width-p_width-2)) -c color_cpu_graph -n cpu_history
		create_graph -o cpu_graph_b -d $((line+graph_a_size)) ${col} ${graph_b_size} $((width-p_width-2)) -c color_cpu_graph -i -n cpu_history

		if [[ -z ${cpu_core_1_graph} ]]; then
			for((i=1;i<=threads;i++)); do
				create_mini_graph -o "cpu_core_${i}_graph" -w 10 -nc "cpu_core_history_${i}"
			done
		fi

		if [[ $check_temp == true && -z ${cpu_temp_0_graph} ]]; then
			for((i=0;i<=threads;i++)); do
				if [[ -n ${cpu[temp_${i}]} ]]; then create_mini_graph -o "cpu_temp_${i}_graph" -w 5 -nc "cpu_temp_history_${i}"; fi
			done
		fi
		((resized++))
	fi

	#* Add new values to cpu and core graphs unless just resized
	if ((resized==0)); then
		create_graph -add-last cpu_graph_a cpu_history
		create_graph -i -add-last cpu_graph_b cpu_history
		for((i=1;i<=threads;i++)); do
			create_mini_graph -w 10 -nc -add-last "cpu_core_${i}_graph" "cpu_core_history_${i}"
		done
		if [[ $check_temp == true ]]; then
			for((i=0;i<=threads;i++)); do
				if [[ -n ${cpu[temp_${i}]} ]]; then
					create_mini_graph -w 5 -nc -add-last "cpu_temp_${i}_graph" "cpu_temp_history_${i}"
				fi
			done
		fi
	fi

	#* Print CPU total and all cpu core percentage meters in box
	for((i=0;i<=threads;i++)); do
		if ((i==0)); then name="CPU"; else name="Core${i}"; fi

		#* Get color of cpu text depending on current usage
		cpu_p_color="${color_cpu_graph[cpu_usage[i]]}"

		pt_col=$p_col; pt_line=$p_line; meter_size="small"; meter_width=10

		#* Set temperature string if "sensors" is available
		if [[ $check_temp == true ]]; then
			#* Get color of temperature text depending on current temp vs factory high temp
			declare -n temp_hist="cpu_temp_history_${i}[-1]"
			temp_color="${color_temp_graph[${temp_hist}]}"
			temp_name="cpu_temp_${i}_graph"
			temp_width=13
		fi

		if ((i==0 & p_width>24+temp_width)); then
			name="CPU Total "; meter_width=$((p_width-17-temp_width))
		fi


		#* Create cpu usage meter
		if ((i==0)); then
			create_meter -v meter -w $meter_width -f -c color_cpu_graph ${cpu_usage[i]}
		else
			core_name="cpu_core_${i}_graph"
			meter="${!core_name}"
		fi

		if ((p_width>84+temp_width & i>=(p_height-2)*3-2)); then pt_line=$((p_line+i-y*4)); pt_col=$((p_col+72+temp_width*3))
		elif ((p_width>54+temp_width & i>=(p_height-2)*2-1)); then pt_line=$((p_line+i-y*3)); pt_col=$((p_col+48+temp_width*2))
		elif ((p_width>24+temp_width & i>=p_height-2)); then pt_line=$((p_line+i-y*2)); pt_col=$((p_col+24+temp_width))
		else y=$i; fi

		print -v cpu_out_var -m $((pt_line+y)) $pt_col -rs -fg $p_normal_color -jl 7 -t "$name" -fg ${theme[inactive_fg]} "⡀⡀⡀⡀⡀⡀⡀⡀⡀⡀" -l 10 -fg $cpu_p_color -t "$meter"\
		-jr 4 -fg $cpu_p_color -t "${cpu_usage[i]}" -fg $p_normal_color -t "%"
		if [[ $check_temp == true && -n ${cpu[temp_${i}]} ]]; then
			print -v cpu_out_var -fg ${theme[inactive_fg]} "  ⡀⡀⡀⡀⡀" -l 7 -fg $temp_color -jl 7 -t "  ${!temp_name}" -jr 4 -t ${cpu[temp_${i}]} -fg $p_normal_color -t ${cpu[temp_unit]}
		fi

		if (( i>(p_height-2)*( p_width/(24+temp_width) )-( p_width/(24+temp_width) )-1 )); then break; fi
	done

	#* Print load average and uptime
	if ((pt_line+y+3<p_line+p_height)); then
		local avg_string avg_width
		if [[ $check_temp == true ]]; then avg_string="Load Average: "; avg_width=7; else avg_string="L AVG: "; avg_width=5; fi
		print -v cpu_out_var -m $((pt_line+y+1)) $pt_col -fg ${theme[main_fg]} -t "${avg_string}"
		for avg_string in ${cpu[load_avg]}; do
			print -v cpu_out_var -jc $avg_width -t "${avg_string::4}"
		done
	fi
	print -v cpu_out_var -m $((line+height-1)) $((col+1)) -fg ${theme[inactive_fg]} -trans -t "${lang_cpu_up_title} ${cpu[uptime]}"

	#* Print current CPU frequency right of the title in the meter box
	if [[ -n ${cpu[freq_string]} ]]; then print -v cpu_out_var -m $((p_line-1)) $((p_col+p_width-5-${#cpu[freq_string]})) -fg ${theme[div_line]} -t "┤" -fg ${theme[title]} -b -t "${cpu[freq_string]}" -rs -fg ${theme[div_line]} -t "├"; fi

	#* Print created text, graph and meters to output variable
	draw_out+="${cpu_graph_a[*]}${cpu_graph_b[*]}${cpu_out_var}"

}

function draw_mem() { #? Draw mem, swap and disk statistics

	if ((mem[counter]>0 & resized==0)); then return; fi

	local i swap_used_meter swap_free_meter mem_available_meter mem_free_meter mem_used_meter mem_cached_meter normal_color="${theme[main_fg]}" value_text
	local meter_mod_w meter_mod_pos value type m_title meter_options values="used available cached free"
	local -a types=("mem")
	unset mem_out

	if [[ -n ${swap[total]} && ${swap[total]} -gt 0 ]]; then types+=("swap"); fi

	#* Get variables from previous calculations
	local col=$((box[mem_col]+1)) line=$((box[mem_line]+1)) width=$((box[mem_width]-2)) height=$((box[mem_height]-2))
	local m_width=${box[m_width]} m_height=${box[m_height]} m_col=${box[m_col]} m_line=${box[m_line]} mem_line=$((box[mem_col]+box[m_width]))

	#* Create text and meters for memory and swap and adapt sizes based on available height
	local y_pos=$m_line v_height=8 list value meter inv_meter

	for type in ${types[@]}; do
		local -n type_name="$type"
		if [[ $type == "mem" ]]; then
			m_title="${lang_title_mem}"
		else
			case type in
				swap) m_title="${lang_title_swap}";;
				mem) m_title="${lang_title_mem}";;
				*) m_title="${lang_title_mem}";;
			esac

			if ((height>14)); then ((y_pos++)); fi
		fi

		#* Print name of type and total amount in humanized base 2 bytes
		print -v mem_out -m $y_pos $m_col -rs -fg ${theme[title]} -b -jl 9 -t "${m_title^}:" -m $((y_pos++)) $((mem_line-10)) -jr 9 -t " ${type_name[total_string]::$((m_width-11))}"

		for value in ${values}; do
			case $value in
				"used") value_text="${lang_mem_value_used}";;
				"available") value_text="${lang_mem_value_available}";;
				"cached") value_text="${lang_mem_value_cached}";;
				"free") value_text="${lang_mem_value_free}";;
			esac

			if [[ $type == "swap" && $value =~ available|cached ]]; then continue; fi

			if [[ $system == "MacOS" && $value == "cached" ]]; then 
				value_text="${lang_mem_active_status}"
			else 
				value_text="${value::$((m_width-12))}"; 
			fi
			
			if ((height<14)); then value_text="${value_text::5}"; fi

			#* Print name of value and value amount in humanized base 2 bytes
			print -v mem_out -m $y_pos $m_col -rs -fg $normal_color -jl 9 -t "${value_text^}:" -m $((y_pos++)) $((mem_line-10)) -jr 9 -t " ${type_name[${value}_string]::$((m_width-11))}"

			#* Create meter for value and calculate size and placement depending on terminal size
			if ((height>v_height++ | tty_width>100)); then
				if ((height<=v_height & tty_width<150)); then
					meter_mod_w=12
					meter_mod_pos=7
					((y_pos--))
				elif ((height<=v_height)); then
					print -v mem_out -m $((--y_pos)) $((m_col+5)) -jr 4 -t "${type_name[${value}_percent]}%"
					meter_mod_w=14
					meter_mod_pos=10
				fi
				create_meter -v ${type}_${value}_meter -w $((m_width-7-meter_mod_w)) -f -c color_${value}_graph ${type_name[${value}_percent]}

				meter="${type}_${value}_meter"
				print -v mem_out -m $((y_pos++)) $((m_col+meter_mod_pos)) -t "${!meter}" -rs -fg $normal_color

				if [[ -z $meter_mod_w ]]; then print -v mem_out  -jr 4 -t "${type_name[${value}_percent]}%"; fi
			fi
		#if [[ $system == "MacOS" && -z $swap_on ]] && ((height>14)); then ((y_pos++)); fi
		done
	done

	#* Create text and meters for disks and adapt sizes based on available height
	local disk_num disk_name disk_value v_height2 just_val name_len
	y_pos=$m_line
	m_col=$((m_col+m_width))
	m_width=${box[m_width2]}
	v_height=$((${#disks_name[@]}))
	unset meter_mod_w meter_mod_pos

	for disk_name in "${disks_name[@]}"; do
		if ((y_pos>m_line+height-2)); then break; fi

		#* Print folder disk is mounted on, total size in humanized base 2 bytes and io stats if enabled
		print -v mem_out -m $((y_pos++)) $m_col -rs -fg ${theme[title]} -b -t "${disks_name[disk_num]::10}"
		name_len=${#disks_name[disk_num]}; if ((name_len>10)); then name_len=10; fi
		if [[ -n ${disks_io[disk_num]} && ${disks_io[disk_num]} != "0" ]] && ((m_width-11-name_len>6)); then
			print -v mem_out -jc $((m_width-name_len-10)) -rs -fg ${theme[main_fg]} -t "${disks_io[disk_num]::$((m_width-10-name_len))}"
			just_val=8
		else
			just_val=$((m_width-name_len-2))
		fi
		print -v mem_out -jr ${just_val} -fg ${theme[title]} -b -t "${disks_total[disk_num]::$((m_width-11))}"

		for value in "used" "free"; do
			if ((height<v_height*3)) && [[ $value == "free" ]]; then break; fi
			local -n disk_value="disks_${value}"

			#* Print name of value and value amount in humanized base 2 bytes
			print -v mem_out -m $((y_pos++)) $m_col -rs -fg $normal_color -jl 9 -t "${value^}:" -jr $((m_width-11)) -t "${disk_value[disk_num]::$((m_width-11))}"

			#* Create meter for value and calculate size and placement depending on terminal size
			if ((height>=v_height*5 | tty_width>100)); then
				local -n disk_value_percent="disks_${value}_percent"
				if ((height<=v_height*5 & tty_width<150)); then
					meter_mod_w=12
					meter_mod_pos=7
					((y_pos--))
				elif ((height<=v_height*5)); then
					print -v mem_out -m $((--y_pos)) $((m_col+5)) -jr 4 -t "${disk_value_percent[disk_num]}%"
					meter_mod_w=14
					meter_mod_pos=10
				fi
				create_meter -v disk_${disk_num}_${value}_meter -w $((m_width-7-meter_mod_w)) -f -c color_${value}_graph ${disk_value_percent[disk_num]}

				meter="disk_${disk_num}_${value}_meter"
				print -v mem_out -m $((y_pos++)) $((m_col+meter_mod_pos)) -t "${!meter}" -rs -fg $normal_color

				if [[ -z $meter_mod_w ]]; then print -v mem_out -jr 4 -t "${disk_value_percent[disk_num]}%"; fi
			fi
			if ((y_pos>m_line+height-1)); then break; fi
		done
		if ((height>=v_height*4 & height<v_height*5 | height>=v_height*6)); then ((y_pos++)); fi
		((++disk_num))
	done

	if ((resized>0)); then ((resized++)); fi
	#* Print created text, graph and meters to output variable
	draw_out+="${mem_graph[*]}${swap_graph[*]}${mem_out}"

}

function draw_processes() { #? Draw processes and values to screen
	local argument="$1"
	if [[ -n $skip_process_draw && $argument != "now" ]]; then return; fi
	local line=${box[processes_line]} col=${box[processes_col]} width=${box[processes_width]} height=${box[processes_height]} out_line y=1 fg_step_r=0 fg_step_g=0 fg_step_b=0 checker=2 page_string sel_string
	local reverse_string reverse_pos order_left="───────────┤" filter_string current_num detail_location det_no_add com_fg pg_arrow_up_fg pg_arrow_down_fg p_height=$((height-3))
	local pid=0 pid_graph pid_step_r pid_step_g pid_step_b pid_add_r pid_add_g pid_add_b bg_add bg_step proc_start up_fg down_fg page_up_fg page_down_fg this_box=${lang_process_title}
	local d_width=${box[details_width]} d_height=${box[details_height]} d_line=${box[details_line]} d_col=${box[details_col]}
	local detail_graph_width=$((d_width/3+2)) detail_graph_height=$((d_height-1)) kill_fg det_mod fg_add_r fg_add_g fg_add_b
	local right_width=$((d_width-detail_graph_width-2))
	local right_col=$((d_col+detail_graph_width+4))
	local -a pid_rgb=(${theme[proc_misc]}) fg_rgb=(${theme[main_fg_dec]})
	local pid_r=${pid_rgb[0]} pid_g=${pid_rgb[1]} pid_b=${pid_rgb[2]} fg_r=${fg_rgb[0]} fg_g=${fg_rgb[1]} fg_b=${fg_rgb[2]}

	if [[ $argument == "now" ]]; then skip_process_draw=1; fi

	if [[ $proc_gradient == true ]]; then
		if ((fg_r+fg_g+fg_b<(255*3)/2)); then
			fg_add_r="$(( (fg_r-255-((fg_r-255)/6) )/height))"
			fg_add_g="$(( (fg_g-255-((fg_g-255)/6) )/height))"
			fg_add_b="$(( (fg_b-255-((fg_b-255)/6) )/height))"

			pid_add_r="$(( (pid_r-255-((pid_r-255)/6) )/height))"
			pid_add_g="$(( (pid_g-255-((pid_g-255)/6) )/height))"
			pid_add_b="$(( (pid_b-255-((pid_b-255)/6) )/height))"
		else
			fg_add_r="$(( (fg_r-(fg_r/6) )/height))"
			fg_add_g="$(( (fg_g-(fg_g/6) )/height))"
			fg_add_b="$(( (fg_b-(fg_b/6) )/height))"

			pid_add_r="$(( (pid_r-(pid_r/6) )/height))"
			pid_add_g="$(( (pid_g-(pid_g/6) )/height))"
			pid_add_b="$(( (pid_b-(pid_b/6) )/height))"
		fi
	fi

	unset proc_out

	#* Details box
	if ((proc[detailed_change]>0)) || ((proc[detailed]>0 & resized>0)); then
		proc[detailed_change]=0
		proc[order_change]=1
		proc[page_change]=1
		if ((proc[detailed]==1)); then
			unset proc_det
			local enter_fg enter_a_fg misc_fg misc_a_fg i det_y=6 dets cmd_y

			if [[ ${#detail_history[@]} -eq 1 ]] || ((resized>0)); then
				unset proc_det2
				create_graph -o detail_graph -d $((d_line+1)) $((d_col+1)) ${detail_graph_height} ${detail_graph_width} -c color_cpu_graph -n detail_history
				if ((tty_width>120)); then create_mini_graph -o detail_mem_graph -w $((right_width/3-3)) -nc detail_mem_history; fi
				det_no_add=1

				for detail_location in "${d_line}" "$((d_line+d_height))"; do
					print -v proc_det2 -m ${detail_location} $((d_col+1)) -rs -fg ${box[processes_color]} -rp $((d_width-2)) -t "─"
				done
				for((i=1;i<d_height;i++)); do
					print -v proc_det2 -m $((d_line+i)) $((d_col+3+detail_graph_width)) -rp $((right_width-1)) -t " "
					print -v proc_det2 -m $((d_line+i)) ${d_col} -fg ${box[processes_color]} -t "│" -r $((detail_graph_width+1)) -fg ${theme[div_line]} -t "│" -r $((right_width+1)) -fg ${box[processes_color]} -t "│"
				done

				print -v proc_det2 -m ${d_line} ${d_col} -t "┌" -m ${d_line} $((d_col+d_width-1)) -t "┐"
				print -v proc_det2 -m ${d_line} $((d_col+2+detail_graph_width)) -t "┬" -m $((d_line+d_height)) $((d_col+detail_graph_width+2)) -t "┴"
				print -v proc_det2 -m $((d_line+d_height)) ${d_col} -t "├" -r 1 -t "┤" -fg ${theme[title]} -b -t "${this_box}" -rs -fg ${box[processes_color]} -t "├" -r $((d_width-5-${#this_box})) -t "┤"
				print -v proc_det2 -m ${d_line} $((d_col+2)) -t "┤" -fg ${theme[title]} -b -t "${proc[detailed_name],,}" -rs -fg ${box[processes_color]} -t "├"
				if ((tty_width>128)); then print -v proc_det2 -r 1 -t "┤" -fg ${theme[title]} -b -t "${proc[detailed_pid]}" -rs -fg ${box[processes_color]} -t "├"; fi

				if ((${#proc[detailed_cmd]}>(right_width-6)*2)); then ((det_y--)); dets=2
				elif ((${#proc[detailed_cmd]}>right_width-6)); then dets=1; fi

				print -v proc_det2 -fg ${theme[title]} -b
				for i in C M D; do
					print -v proc_det2 -m $((d_line+5+cmd_y++)) $right_col -t "$i"
				done

				print -v proc_det2 -m $((d_line+det_y++)) $((right_col+1)) -jc $((right_width-4)) -rs -fg ${theme[main_fg]} -t "${proc[detailed_cmd]::$((right_width-6))}"
				if ((dets>0)); then print -v proc_det2 -m $((d_line+det_y++)) $((right_col+2)) -jl $((right_width-6)) -t "${proc[detailed_cmd]:$((right_width-6)):$((right_width-6))}"; fi
				if ((dets>1)); then print -v proc_det2 -m $((d_line+det_y)) $((right_col+2)) -jl $((right_width-6)) -t "${proc[detailed_cmd]:$(( (right_width-6)*2 )):$((right_width-6))}"; fi
			fi

			if ((proc[selected]>0)); then enter_fg="${theme[inactive_fg]}"; enter_a_fg="${theme[inactive_fg]}"; else enter_fg="${theme[title]}"; enter_a_fg="${theme[hi_fg]}"; fi
			if [[ -n ${proc[detailed_killed]} ]]; then misc_fg="${theme[title]}"; misc_a_fg="${theme[hi_fg]}"
			else misc_fg=$enter_fg; misc_a_fg=$enter_a_fg; fi
			print -v proc_det -m ${d_line} $((d_col+d_width-11)) -fg ${box[processes_color]} -t "┤" -fg $enter_fg -b -t "${lang_processes_title_close} " -fg $enter_a_fg -t "↲" -rs -fg ${box[processes_color]} -t "├"
			if ((tty_width<129)); then det_mod="-8"; fi

			print -v proc_det -m ${d_line} $((d_col+detail_graph_width+4+det_mod)) -t "┤" -fg $misc_a_fg -b -t "t" -fg $misc_fg -t "erminate" -rs -fg ${box[processes_color]} -t "├"
			print -v proc_det -r 1 -t "┤" -fg $misc_a_fg -b -t "k" -fg $misc_fg -t "ill" -rs -fg ${box[processes_color]} -t "├"
			if ((tty_width>104)); then print -v proc_det -r 1 -t "┤" -fg $misc_a_fg -b -t "i" -fg $misc_fg -t "nterrupt" -rs -fg ${box[processes_color]} -t "├"; fi


			proc_det="${proc_det2}${proc_det}"
			proc_out="${proc_det}"

		elif ((resized==0)); then
			unset proc_det
			create_box -v proc_out -col ${box[${this_box}_col]} -line ${box[${this_box}_line]} -width ${box[${this_box}_width]} -height ${box[${this_box}_height]} -fill -lc "${box[${this_box}_color]}" -title ${this_box}
		fi
	fi

	if [[ ${proc[detailed]} -eq 1 ]]; then
		local det_status status_color det_columns=3
		if ((tty_width>140)); then ((det_columns++)); fi
		if ((tty_width>150)); then ((det_columns++)); fi
		if [[ -z $det_no_add && $1 != "now" && -z ${proc[detailed_killed]} ]]; then
			create_graph -add-last detail_graph detail_history
			if ((tty_width>120)); then create_mini_graph -w $((right_width/3-3)) -nc -add-last detail_mem_graph detail_mem_history; fi
		fi

		print -v proc_out -fg ${theme[title]} -b
		cmd_y=0
		for i in C P U; do
			print -v proc_out -m $((d_line+3+cmd_y++)) $((d_col+1)) -t "$i"
		done
		print -v proc_out -m $((d_line+1)) $((d_col+1)) -fg ${theme[title]} -t "${proc[detailed_cpu]}%"

		if [[ -n ${proc[detailed_killed]} ]]; then det_status="stopped"; status_color="${theme[inactive_fg]}"
		else det_status="running"; status_color="${theme[proc_misc]}"; fi
		print -v proc_out -m $((d_line+1)) ${right_col} -fg ${theme[title]} -b -jc $((right_width/det_columns-1)) -t "${lang_processes_title_status}:" -jc $((right_width/det_columns)) -t "${lang_processes_title_elapsed}:" -jc $((right_width/det_columns)) -t "${lang_processes_title_parent}:"
		if ((det_columns>=4)); then print -v proc_out -jc $((right_width/det_columns-1)) -t "${lang_processes_title_user}:"; fi
		if ((det_columns>=5)); then print -v proc_out -jc $((right_width/det_columns-1)) -t "${lang_processes_title_threads}:"; fi
		print -v proc_out -m $((d_line+2)) ${right_col} -rs -fg ${status_color} -jc $((right_width/det_columns-1)) -t "${det_status}" -jc $((right_width/det_columns)) -fg ${theme[main_fg]} -t "${proc[detailed_runtime]::$((right_width/det_columns-1))}" -jc $((right_width/det_columns)) -t "${proc[detailed_parent_name]::$((right_width/det_columns-2))}"
		if ((det_columns>=4)); then print -v proc_out -jc $((right_width/det_columns-1)) -t "${proc[detailed_user]::$((right_width/det_columns-2))}"; fi
		if ((det_columns>=5)); then print -v proc_out -jc $((right_width/det_columns-1)) -t "${proc[detailed_threads]}"; fi

		print -v proc_out -m $((d_line+4)) ${right_col} -fg ${theme[title]} -b -jr $((right_width/3+2)) -t "${lang_processes_title_memory}: ${proc[detailed_mem]}%" -t " "
		if ((tty_width>120)); then print -v proc_out -rs -fg ${theme[inactive_fg]} -rp $((right_width/3-3)) "⡀" -l $((right_width/3-3)) -fg ${theme[proc_misc]} -t "${detail_mem_graph}" -t " "; fi
		print -v proc_out -fg ${theme[title]} -b -t "${proc[detailed_mem_string]}"
	fi

	#* Print processes
	if ((${#proc_array[@]}<=p_height)); then
		proc[start]=1
	elif (( proc[start]>(${#proc_array[@]}-1)-p_height )); then
		proc[start]=$(( (${#proc_array[@]}-1)-p_height ))
	fi

	if ((proc[selected]>${#proc_array[@]}-1)); then proc[selected]=$((${#proc_array[@]}-1)); fi

	if [[ $proc_gradient == true ]] && ((proc[selected]>1)); then
		fg_r="$(( fg_r-( fg_add_r*(proc[selected]-1) ) ))"
		fg_g="$(( fg_g-( fg_add_g*(proc[selected]-1) ) ))"
		fg_b="$(( fg_b-( fg_add_b*(proc[selected]-1) ) ))"

		pid_r="$(( pid_r-( pid_add_r*(proc[selected]-1) ) ))"
		pid_g="$(( pid_g-( pid_add_g*(proc[selected]-1) ) ))"
		pid_b="$(( pid_b-( pid_add_b*(proc[selected]-1) ) ))"
	fi

	current_num=1

	print -v proc_out -rs -m $((line+y++)) $((col+1)) -fg ${theme[title]} -b -t "${proc_array[0]::$((width-3))} " -rs

	local -a out_arr
	for out_line in "${proc_array[@]:${proc[start]}}"; do

		if [[ $use_psutil == true ]]; then
			out_arr=(${out_line})
			pi=0
			if [[ $proc_tree == true ]]; then
				while [[ ! ${out_arr[pi]} =~ ^[0-9]+$ ]]; do ((++pi)); done
			fi
			pid="${out_arr[pi]}"

		else
			pid="${out_line::$((proc[pid_len]+1))}"; pid="${pid// /}"
			out_line="${out_line//'\'/'\\'}"
			out_line="${out_line//'$'/'\$'}"
			out_line="${out_line//'"'/'\"'}"
		fi

		pid_graph="pid_${pid}_graph"

		if ((current_num==proc[selected])); then print -v proc_out -bg ${theme[selected_bg]} -fg ${theme[selected_fg]} -b; proc[selected_pid]="$pid"
		else print -v proc_out -rs -fg $((fg_r-fg_step_r)) $((fg_g-fg_step_g)) $((fg_b-fg_step_b)); fi

		print -v proc_out -m $((line+y)) $((col+1)) -t "${out_line::$((width-3))} "

		if ((current_num==proc[selected])); then print -v proc_out -rs -bg ${theme[selected_bg]}; fi

		print -v proc_out -m $((line+y)) $((col+width-12)) -fg ${theme[inactive_fg]} -t "⡀⡀⡀⡀⡀"

		if [[ -n ${!pid_graph} ]]; then
			print -v proc_out -m $((line+y)) $((col+width-12)) -fg $((pid_r-pid_step_r)) $((pid_g-pid_step_g)) $((pid_b-pid_step_b)) -t "${!pid_graph}"
		fi

		((y++))
		((current_num++))
		if ((y>height-2)); then break; fi
		if [[ $proc_gradient == false ]]; then :
		elif ((current_num<proc[selected]+1)); then
			fg_step_r=$((fg_step_r-fg_add_r)); fg_step_g=$((fg_step_g-fg_add_g)); fg_step_b=$((fg_step_b-fg_add_b))
			pid_step_r=$((pid_step_r-pid_add_r)); pid_step_g=$((pid_step_g-pid_add_g)); pid_step_b=$((pid_step_b-pid_add_b))
		elif ((current_num>=proc[selected])); then
			fg_step_r=$((fg_step_r+fg_add_r)); fg_step_g=$((fg_step_g+fg_add_g)); fg_step_b=$((fg_step_b+fg_add_b))
			pid_step_r=$((pid_step_r+pid_add_r)); pid_step_g=$((pid_step_g+pid_add_g)); pid_step_b=$((pid_step_b+pid_add_b))
		fi

	done
		print -v proc_out -rs
		while ((y<=height-2)); do
			print -v proc_out -m $((line+y++)) $((col+1)) -rp $((width-2)) -t " "
		done

		if ((proc[selected]>0)); then sel_string=$((proc[start]-1+proc[selected])); else sel_string=0; fi
		page_string="${sel_string}/$((${#proc_array[@]}-2${filter:++1}))"
		print -v proc_out -m $((line+height-1)) $((col+width-20)) -fg ${box[processes_color]} -rp 19 -t "─"
		print -v proc_out -m $((line+height-1)) $((col+width-${#page_string}-4)) -fg ${box[processes_color]} -t "┤" -b -fg ${theme[title]} -t "$page_string" -rs -fg ${box[processes_color]} -t "├"


	if ((proc[order_change]==1 | proc[filter_change]==1 | resized>0)); then
		unset proc_misc
		proc[order_change]=0
		proc[filter_change]=0
		proc[page_change]=1
		print -v proc_misc -m $line $((col+13)) -fg ${box[processes_color]} -rp $((box[processes_width]-14)) -t "─" -rs

		if ((proc[detailed]==1)); then
			print -v proc_misc -m $((d_line+d_height)) $((d_col+detail_graph_width+2)) -fg ${box[processes_color]} -t "┴" -rs
		fi

		if ((tty_width>100)); then
			reverse_string="-fg ${box[processes_color]} -t ┤ -fg ${theme[hi_fg]}${proc[reverse]:+ -ul} -b -t r -fg ${theme[title]} -t everse -rs -fg ${box[processes_color]} -t ├"
			reverse_pos=9
		fi
		print -v proc_misc -m $line $((col+width-${#proc_sorting}-14-reverse_pos)) -rs\
		${reverse_string}\
		-fg ${box[processes_color]} -t ┤ -fg ${theme[title]}${proc[tree]:+ -ul} -b -t "tre" -fg ${theme[hi_fg]} -t "e" -rs -fg ${box[processes_color]} -t ├\
		-fg ${box[processes_color]} -t "┤" -fg ${theme[hi_fg]} -b -t "‹" -fg ${theme[title]} -t " ${proc_sorting} "  -fg ${theme[hi_fg]} -t "›" -rs -fg ${box[processes_color]} -t "├"

		if [[ -z $filter && -z $input_to_filter ]]; then
			print -v proc_misc -m $line $((col+14)) -fg ${box[processes_color]} -t "┤" -fg ${theme[hi_fg]} -b -t "f" -fg ${theme[title]} -t "ilter" -rs -fg ${box[processes_color]} -t "├"
		elif [[ -n $input_to_filter ]]; then
			if [[ ${#filter} -le $((width-35-reverse_pos)) ]]; then filter_string="${filter}"
			elif [[ ${#filter} -gt $((width-35-reverse_pos)) ]]; then filter_string="${filter: (-$((width-35-reverse_pos)))}"
			fi
			print -v proc_misc -m $line $((col+14)) -fg ${box[processes_color]} -t "┤" -fg ${theme[title]} -b -t "${filter_string}" -fg ${theme[proc_misc]} -bl -t "█" -rs -fg ${box[processes_color]} -t "├"
		elif [[ -n $filter ]]; then
			if [[ ${#filter} -le $((width-35-reverse_pos-4)) ]]; then filter_string="${filter}"
			elif [[ ${#filter} -gt $((width-35-reverse_pos-4)) ]]; then filter_string="${filter::$((width-35-reverse_pos-4))}"
			fi
			print -v proc_misc -m $line $((col+14)) -fg ${box[processes_color]} -t "┤" -fg ${theme[hi_fg]} -b -t "f" -fg ${theme[title]} -t " ${filter_string} " -fg ${theme[hi_fg]} -t "c" -rs -fg ${box[processes_color]} -t "├"
		fi

		proc_out+="${proc_misc}"
	fi

	if ((proc[page_change]==1 | resized>0)); then
		unset proc_misc2
		proc[page_change]=0
		if ((proc[selected]>0)); then kill_fg="${theme[hi_fg]}"; com_fg="${theme[title]}"; else kill_fg="${theme[inactive_fg]}"; com_fg="${theme[inactive_fg]}"; fi
		if ((proc[selected]==(${#proc_array[@]}-1${filter:++1})-proc[start])); then down_fg="${theme[inactive_fg]}"; else down_fg="${theme[hi_fg]}"; fi
		if ((proc[selected]>0 | proc[start]>1)); then up_fg="${theme[hi_fg]}"; else up_fg="${theme[inactive_fg]}"; fi

		print -v proc_misc2 -m $((line+height-1)) $((col+2)) -fg ${box[processes_color]} -t "┤" -fg $up_fg -b -t "↑" -fg ${theme[title]} -t " ${lang_processes_option_select} " -fg $down_fg -t "↓" -rs -fg ${box[processes_color]} -t "├"
		print -v proc_misc2 -r 1 -fg ${box[processes_color]} -t "┤" -fg $com_fg -b -t "${lang_processes_option_info} " -fg $kill_fg "↲" -rs -fg ${box[processes_color]} -t "├"
		if ((tty_width>100)); then print -v proc_misc2 -r 1 -t "┤" -fg $kill_fg -b -t "t" -fg $com_fg -t "erminate" -rs -fg ${box[processes_color]} -t "├"; fi
		if ((tty_width>111)); then print -v proc_misc2 -r 1 -t "┤" -fg $kill_fg -b -t "k" -fg $com_fg -t "ill" -rs -fg ${box[processes_color]} -t "├"; fi
		if ((tty_width>126)); then print -v proc_misc2 -r 1 -t "┤" -fg $kill_fg -b -t "i" -fg $com_fg -t "nterrupt" -rs -fg ${box[processes_color]} -t "├"; fi

		proc_out+="${proc_misc2}"
	fi

	proc_out="${detail_graph[*]}${proc_out}"

	if ((resized>0)); then ((resized++)); fi

	if [[ $argument == "now" ]]; then
		echo -en "${proc_out}"
	fi

}

function draw_net() { #? Draw net information and graphs to screen
	local net_out argument=$1
	if [[ -n ${net[no_device]} ]]; then return; fi
	if [[ -n $skip_net_draw && $argument != "now" ]]; then return; fi
	if [[ $argument == "now" ]]; then skip_net_draw=1; fi

	#* Get variables from previous calculations
	local col=$((box[net_col]+1)) line=$((box[net_line]+1)) width=$((box[net_width]-2)) height=$((box[net_height]-2))
	local n_width=${box[n_width]} n_height=${box[n_height]} n_col=${box[n_col]} n_line=${box[n_line]} main_fg="${theme[main_fg]}"

	#* If resized recreate net meter box and net graphs
	if ((resized>0)); then
		local graph_a_size graph_b_size
		graph_a_size=$(( (height)/2 )); graph_b_size=${graph_a_size}
		if ((graph_a_size*2<height)); then ((graph_a_size++)); fi
		net[graph_a_size]=$graph_a_size
		net[graph_b_size]=$graph_b_size
		net[download_redraw]=0
		net[upload_redraw]=0
		((resized++))
	fi

	#* Update graphs if graph resolution update is needed or just resized, otherwise just add new values
	if ((net[download_redraw]==1 | net[nic_change]==1 | resized>0)); then
		create_graph -o download_graph -d $line $col ${net[graph_a_size]} $((width-n_width-2)) -c color_download_graph -n -max "${net[download_graph_max]}" net_history_download
	else
		create_graph -max "${net[download_graph_max]}" -add-last download_graph net_history_download
	fi
	if ((net[upload_redraw]==1 | net[nic_change]==1 | resized>0)); then
		create_graph -o upload_graph -d $((line+net[graph_a_size])) $col ${net[graph_b_size]} $((width-n_width-2)) -c color_upload_graph -i -n -max "${net[upload_graph_max]}" net_history_upload
	else
		create_graph -max "${net[upload_graph_max]}" -i -add-last upload_graph net_history_upload
	fi

	if ((net[nic_change]==1 | resized>0)); then
		local dev_len=${#net[device]}
		if ((dev_len>15)); then dev_len=15; fi
		unset net_misc 'net[nic_change]'
		print -v net_out -m $((line-1)) $((width-23)) -rs -fg ${box[net_color]} -rp 23 -t "─"
		print -v net_misc -m $((line-1)) $((width-7-dev_len)) -rs -fg ${box[net_color]} -t "┤" -fg ${theme[hi_fg]} -b -t "‹b " -fg ${theme[title]} -t "${net[device]::15}" -fg ${theme[hi_fg]} -t " n›" -rs -fg ${box[net_color]} -t "├"
		net_out+="${net_misc}"
	fi

	#* Create text depening on box height
	local ypos=$n_line

	print -v net_out -fg ${main_fg} -m $((ypos++)) $n_col -jl 10 -t "▼ ${lang_net_title_byte}:" -jr 12 -t "${net[speed_download_byteps]}"
	if ((height>4)); then print -v net_out -fg ${main_fg} -m $((ypos++)) $n_col -jl 10 -t "▼ ${lang_net_title_bit}:" -jr 12 -t "${net[speed_download_bitps]}"; fi
	if ((height>6)); then print -v net_out -fg ${main_fg} -m $((ypos++)) $n_col -jl 10 -t "▼ ${lang_net_title_total}:" -jr 12 -t "${net[total_download]}"; fi

	if ((height>8)); then ((ypos++)); fi
	print -v net_out -fg ${main_fg} -m $((ypos++)) $n_col -jl 10 -t "▲ ${lang_net_title_byte}:" -jr 12 -t "${net[speed_upload_byteps]}"
	if ((height>7)); then print -v net_out -fg ${main_fg} -m $((ypos++)) $n_col -jl 10 -t "▲ ${lang_net_title_bit}:" -jr 12 -t "${net[speed_upload_bitps]}"; fi
	if ((height>5)); then print -v net_out -fg ${main_fg} -m $((ypos++)) $n_col -jl 10 -t "▲ ${lang_net_title_total}:" -jr 12 -t "${net[total_upload]}"; fi

	print -v net_out -fg ${theme[inactive_fg]} -m $line $col -t "${net[download_max_string]}"
	print -v net_out -fg ${theme[inactive_fg]} -m $((line+height-1)) $col -t "${net[upload_max_string]}"


	#* Print graphs and text to output variable
	draw_out+="${download_graph[*]}${upload_graph[*]}${net_out}"
	if [[ $argument == "now" ]]; then echo -en "${download_graph[*]}${upload_graph[*]}${net_out}"; fi
}

function draw_clock() { #? Draw a clock at top of screen
	if [[ -z $draw_clock ]]; then return; fi
	if [[ $resized -gt 0 && $resized -lt 5 ]]; then unset clock_out; return; fi
	local width=${box[cpu_width]} color=${box[cpu_color]} old_time_string="${time_string}"
	#time_string="$(date ${draw_clock})"
	printf -v time_string "%(${draw_clock})T"
	if [[ $old_time_string != "$time_string" || -z $clock_out ]]; then
		unset clock_out
		print -v clock_out -m 1 $((width/2-${#time_string}/2)) -rs -fg ${color} -t "┤" -fg ${theme[title]} -b -t "${time_string}" -fg ${color} -t "├"
	fi
	if [[ $1 == "now" ]]; then echo -en "${clock_out}"; fi
}

function draw_update_string() {
	unset update_string
	print -v update_string -m ${box[cpu_line]} $((box[cpu_col]+box[cpu_width]-${#update_ms}-14)) -rs -fg ${box[cpu_color]} -t "────┤"  -fg ${theme[hi_fg]} -b -t "+" -fg ${theme[title]} -b -t " ${update_ms}ms "  -fg ${theme[hi_fg]} -b -t "-" -rs -fg ${box[cpu_color]} -t "├"
	if [[ $1 == "quiet" ]]; then draw_out+="${update_string}"
	else echo -en "${update_string}"; fi
}

function resized() {
	# Get new terminal size if terminal is resized
	resized=1
	unset winches
	while ((++winches<5)); do
		read tty_height tty_width < <(${stty} size)
		if (($tty_width<80 | $tty_height<24)); then
			size_error_msg
			winches=0
		else
			echo -en "${clear_screen}"
			create_box -w 30 -h 3 -c 1 -l 1 -lc "#EE2020" -title "resizing"
			print -jc 28 -fg ${theme[title]} "New size: ${tty_width}x${tty_height}"
			${sleep} 0.2
			if [[ $(${stty} size) != "$tty_height $tty_width" ]]; then winches=0; fi
		fi
	done
	debug "Terminal resized to ${tty_width}x${tty_height}"
}

function set_font() {
	#? Take a string and generate a string of unicode characters of given font, usage; set_font "font-name [bold] [italic]" "string"
	local i letter letter_hex new_hex add_hex start font="$1" string_in="$2" string_out hex="16#"
	if [[ -z $font || -z $string_in ]]; then return; fi
	case "$font" in
		"sans-serif") lower_start="1D5BA"; upper_start="1D5A0"; digit_start="1D7E2";;
		"sans-serif bold") lower_start="1D5EE"; upper_start="1D5D4"; digit_start="1D7EC";;
		"sans-serif italic") lower_start="1D622"; upper_start="1D608"; digit_start="1D7E2";;
		#"sans-serif bold italic") start="1D656"; upper_start="1D63C"; digit_start="1D7EC";;
		"script") lower_start="1D4B6"; upper_start="1D49C"; digit_start="1D7E2";;
		"script bold") lower_start="1D4EA"; upper_start="1D4D0"; digit_start="1D7EC";;
		"fraktur") lower_start="1D51E"; upper_start="1D504"; digit_start="1D7E2";;
		"fraktur bold") lower_start="1D586"; upper_start="1D56C"; digit_start="1D7EC";;
		"monospace") lower_start="1D68A"; upper_start="1D670"; digit_start="1D7F6";;
		"double-struck") lower_start="1D552"; upper_start="1D538"; digit_start="1D7D8";;
		*) echo -n "${string_in}"; return;;
	esac

	for((i=0;i<${#string_in};i++)); do
		letter=${string_in:i:1}
		if [[ $letter =~ [a-z] ]]; then #61
			printf -v letter_hex '%X\n' "'$letter"
			printf -v add_hex '%X' "$((${hex}${letter_hex}-${hex}61))"
			printf -v new_hex '%X' "$((${hex}${lower_start}+${hex}${add_hex}))"
			string_out="${string_out}\U${new_hex}"
			#if [[ $font =~ sans-serif && $letter =~ m|w ]]; then string_out="${string_out} "; fi
			#\U205F
		elif [[ $letter =~ [A-Z] ]]; then #41
			printf -v letter_hex '%X\n' "'$letter"
			printf -v add_hex '%X' "$((${hex}${letter_hex}-${hex}41))"
			printf -v new_hex '%X' "$((${hex}${upper_start}+${hex}${add_hex}))"
			string_out="${string_out}\U${new_hex}"
			#if [[ $font =~ sans-serif && $letter =~ M|W ]]; then string_out="${string_out} "; fi
		elif [[ $letter =~ [0-9] ]]; then #30
			printf -v letter_hex '%X\n' "'$letter"
			printf -v add_hex '%X' "$((${hex}${letter_hex}-${hex}30))"
			printf -v new_hex '%X' "$((${hex}${digit_start}+${hex}${add_hex}))"
			string_out="${string_out}\U${new_hex}"
		else
			string_out="${string_out} \e[1D${letter}"
		fi
	done

	echo -en "${string_out}"
}