#!/usr/bin/env bash

function sarah() {
    local wait_time wait_string input_runs

    #* Start infinite loop
    until false; do
        #* Put program to sleep if caught ctrl-z
        if ((sleepy==1)); then sleep_; fi

        #* Timestamp for accurate timer
        get_ms timestamp_start

        if [[ $(${stty} size) != "$tty_height $tty_width" ]]; then resized; fi

        if ((resized>0)); then
            calc_sizes
            sarah_draw_bg
        fi

        # Run all collect and draw functions
        # collect_and_draw now

        # #* Reset resized variable if resized and all functions have finished redrawing
        # if ((resized>=5)); then resized=0
        # elif ((resized>0)); then unset draw_out proc_out clock_out; return; fi

        # #* Echo everyting out to screen in one command to get a smooth transition between updates
        # echo -en "${draw_out}${proc_out}${clock_out}"
        # unset draw_out

        # #* Periodically check for new network device if non was found at start or was removed
        # if ((net[device_check]>10)); then
        #     net[device_check]=0
        #     get_net_device
        # elif [[ -n ${net[no_device]} ]]; then
        #     ((++net[device_check]))
        # fi

        # #* Compare timestamps to get exact time needed to wait until next loop
        # get_ms timestamp_end
        # time_left=$((timestamp_start+update_ms-timestamp_end))
        # if ((time_left>update_ms)); then time_left=$update_ms; fi
        # if ((time_left>0)); then

        #     late_update=0

        #     #* Divide waiting time in chunks of 500ms and below to keep program responsive while reading input
        #     while ((time_left>0 & resized==0)); do

        #         #* If NOT waiting for input and time left is greater than 500ms, wait 500ms and loop
        #         if [[ -z $input_to_filter ]] && ((time_left>=500)); then
        #             wait_string="5"
        #             time_left=$((time_left-500))

        #         #* If waiting for input and time left is greater than "50 ms", wait 50ms and loop
        #         elif [[ -n $input_to_filter ]] && ((time_left>=100)); then
        #             wait_string="1"
        #             time_left=$((time_left-100))

        #         #* Else format wait string with padded zeroes if needed and break loop
        #         else
        #             if ((time_left>=100)); then wait_string=$((time_left/100)); else wait_string=0; fi
        #             time_left=0
        #         fi

        #         #* Wait while reading input
        #         process_input "${wait_string}"
        #         if [[ -n $failed_pipe || -n $py_error ]]; then return; fi

        #         #* Draw clock if set
        #         draw_clock now

        #     done

        # #* If time left is too low to process any input more than five times in succession, add 100ms to update timer
        # elif ((++late_update==5)); then
        #     update_ms=$((update_ms+100))
        #     draw_update_string
        # fi

        unset skip_process_draw skip_net_draw
    done
}