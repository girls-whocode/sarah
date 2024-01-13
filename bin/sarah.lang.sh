#!/usr/bin/env bash

function utf8() {
    #* Check for UTF-8 locale and set LANG variable if not set
    if [[ ! $LANG =~ UTF-8 ]]; then
        if [[ -n $LANG && ${LANG::1} != "C" ]]; then old_lang="${LANG%.*}"; fi

        for set_lang in $(locale -a); do
            if [[ $set_lang =~ utf8|UTF-8 ]]; then
                if [[ -n $old_lang && $set_lang =~ ${old_lang} ]]; then
                    declare -x LANG="${set_lang/utf8/UTF-8}"
                    debug "${utf8_changed_debug}"
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
            echo "${utf8_error}"
            error "${utf8_error}"
            exit 1
        elif [[ $set_lang_search != "found" ]]; then
            declare -x LANG="${first_lang/utf8/UTF-8}"
        fi
        unset old_lang set_lang first_lang set_lang_search set_lang_first
    fi
    debug "${utf8_debug}"
}

function language_loader() {
    # load language file for user
    if [ -z ${language} ]; then
        # Language was not defined
        source "${script_dir}/mods/languages/en.lang"
        debug "No language specified, defaulting to English"
    else
        # Language was defined, does it exist
        if [ -e "${script_dir}/mods/languages/${language}.lang" ]; then
            # It exists
            source "${script_dir}/mods/languages/${language}.lang"
            debug "Language ${language} was specified, loaded"
        else
            # It doesn't :( load English
            source "${script_dir}/mods/languages/en.lang"
            debug "Language ${language} was specified, but does not exist, defaulting to English"
        fi
    fi
    # Languages are loaded, we can now start translations into other languages
}