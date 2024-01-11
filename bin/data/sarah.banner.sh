#!/usr/bin/env bash

declare -a banner banner_colors
banner=(
"░░      ░░░░      ░░░       ░░░░      ░░░  ░░░░  ░"
"▒  ▒▒▒▒▒▒▒▒  ▒▒▒▒  ▒▒  ▒▒▒▒  ▒▒  ▒▒▒▒  ▒▒  ▒▒▒▒  ▒"
"▓▓      ▓▓▓  ▓▓▓▓  ▓▓       ▓▓▓  ▓▓▓▓  ▓▓        ▓"
"███████  ██        ██  ███  ███        ██  ████  █"
"██      ███  ████  ██  ████  ██  ████  ██  ████  █"
"  System Administrator and Remote Access Helper")

declare banner_width=${#banner[0]}
banner_colors=("#E62525" "#CD2121" "#B31D1D" "#9A1919" "#801414")

function draw_banner() { #? Draw banner, usage: draw_banner <line> [output variable]
	local y letter b_color x_color xpos ypos=$1 banner_out
	if [[ -n $2 ]]; then local -n banner_out=$2; fi
	xpos=$(( (tty_width/2)-(banner_width/2) ))

	for banner_line in "${banner[@]}"; do
		print -v banner_out -rs -move $((ypos+++y)) $xpos -t "${banner_line}"
	done

	if [[ -z $2 ]]; then echo -en "${banner_out}"; fi
	debug "Banner completed"
}