#!/usr/bin/env bash

function config() {
    local c_line c_read this_file

    if [ -f "${wkr_config_dir}/${wkr_config}" ]; then

        # Check to see if a config file already exists, if it does then source it, else create it
        if [[ -d "${wkr_config_dir}" && -w "${wkr_config_dir}" ]] || mkdir -p "${wkr_config_dir}"; then
            # shellcheck source=/dev/null
            if [[ -e "${wkr_config_dir}/${wkr_config}" ]]; then
                info "Configuration file found loading ${wkr_config}"
                source "${wkr_config_dir}/${wkr_config}"

                # Initalize the log levels
                logging_level
                success "Configuration file loaded"
            fi
        else
            #* If anything goes wrong turn off all writing to filesystem
            echo "${config_error}"
            critical ${config_error}
            wkr_config_dir="/dev/null"
            config_file="/dev/null"
            error_logging="false"
            unset 'save_array[@]'
        fi
    else
        info "${lang_create_config} ${wkr_config}"
        this_file="$(${realpath} "$0")"
        echo "# ${app_name} v${sarah_version} automated configuration file - This file was automatically created, you may edit these settings or use the menu in ${app_name}" > "${wkr_config_dir}/${wkr_config}"

        while IFS= read -r c_line; do
            if [[ $c_line =~ aaz_config() ]]; then 
                break
            elif [[ $c_read == "1" ]]; then 
                echo "$c_line" >> "${wkr_config_dir}/${wkr_config}"
            elif [[ $c_line =~ aaa_config() ]]; 
                then c_read=1; 
            fi
        done < "$this_file"

        # shellcheck source=/dev/null
        source "${wkr_config_dir}/${wkr_config}"

        # Initalize the log levels
        logging_level
        info "${lang_create_load} ${wkr_config_dir}/${wkr_config}"
    fi
}

function save_config() {
	if [[ -z $1 || ${wkr_config_dir}/${wkr_config} == "/dev/null" ]]; then return; fi
	local var tmp_conf tmp_value quote original new
	tmp_conf="$(<"${wkr_config_dir}/${wkr_config}")"
	for var in "$@"; do
		if [[ ${tmp_conf} =~ ${var} ]]; then
			get_value -v "tmp_value" -sv "tmp_conf" -k "${var}="
			if [[ ${tmp_value//\"/} != "${!var}" ]]; then
				original="${var}=${tmp_value}"
				new="${var}=\"${!var}\""
				original="${original//'/'/'\/'}"
				new="${new//'/'/'\/'}"
				${sed} -i "s/${original}/${new}/" "${wkr_config_dir}/${wkr_config}"
			fi
		else
			echo "${var}=\"${!var}\"" >> "${wkr_config_dir}/${wkr_config}"
		fi
	done
}

function reset_config() {
    if [[ -z $1 || ${wkr_config_dir}/${wkr_config} == "/dev/null" ]]; then return; fi
    local var tmp_conf tmp_value quote original new
    tmp_conf="$(<"${wkr_config_dir}/${wkr_config}")"
    for var in "$@"; do
        if [[ ${tmp_conf} =~ ${var} ]]; then
            get_value -v "tmp_value" -sv "tmp_conf" -k "${var}="
            if [[ ${tmp_value//\"/} != "${!var}" ]]; then
                original="${var}=${tmp_value}"
                new="${var}=\"${!var}\""
                original="${original//'/'/'\/'}"
                new="${new//'/'/'\/'}"
                ${sed} -i "s/${original}/${new}/" "${wkr_config_dir}/${wkr_config}"
            fi
        fi
    done
    success "Configuration file reset"
}