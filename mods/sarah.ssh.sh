#!/usr/bin/env bash

function do_ssh() {
    local user=$1
    local host=$2

    ssh -n -q -o BatchMode=yes -o ConnectTimeout=1 -i ~/.ssh/keys/${key} ${user}@${host} "sudo id" > /dev/null 2>&1
    local status=$?

    if [ $status -eq 255 ]; then
        echo "${lang_ssh_fail}${host}"
    elif [ $status -ne 0 ]; then
        echo "${lang_sudo_fail}${host}"
    else
        echo "${lang_connection_success}${host}"
    fi
}

function get_keys() {
    # Load the user's ssh configuration file and get the keys
    if [ -f "${HOME}/.ssh/config" ]; then
        # Initialize an empty associative array to hold the keys
        declare -A keys

        # Read the file line by line
        while IFS= read -r line
        do
            # If the line contains "IdentityFile", add the key to the array
            if [[ $line =~ [Ii][Dd][Ee][Nn][Tt][Ii][Tt][Yy][Ff][Ii][Ll][Ee]* ]]; then
                key="$(echo "$line" | awk '{print $2}')"
                # Remove double quotes from the key path
                key="${key%\"}"
                key="${key#\"}"
                # Add the key to the array if it doesn't already exist
                if [[ -z ${keys[$key]} ]]; then
                    keys["$key"]=1
                fi
            fi
        done < "${HOME}/.ssh/config"

        # Update the user's identity_file variable with the keys
        identity_file="${!keys[@]}"
    fi
}

function ssh_copy_id() {
    # input="servers"
    # source "./user"
    while IFS= read -r line; do
        if [[ -n ${line} ]] && [[ ${line:0:1} != "#" ]]; then
            sshpass -p ${pass} ssh-copy-id -i ~/.ssh/keys/${key}.pub ${user}@${line} > /dev/null 2>&1
            do_ssh ${user} ${line}
        fi
    done < "${input}"
}