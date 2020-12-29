#!/bin/bash
# source: https://code.mlvn.io/-/snippets/2
start_script=$(date +%s)
JAMF_URL=$(defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url)
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

readonly LOG_FILE="/var/log/validation-test.log"
sudo touch $LOG_FILE

exec 1>$LOG_FILE
exec 2>&1

checkprofiles() {
    SERIALNUMBER=$(system_profiler SPHardwareDataType | grep 'Serial Number (system)' | awk '{print $NF}')
    echo -e "$(date '+%a %b %d %T') $(hostname): ${BOLD}Validating scoped profile identifiers returned by Jamf${NORMAL}"
    echo -e "$(date '+%a %b %d %T') $(hostname): ${BOLD}Jamf instance${NORMAL}: $JAMF_URL"
    echo -e "$(date '+%a %b %d %T') $(hostname): ${BOLD}Device serialnumber${NORMAL}: $SERIALNUMBER"
    echo -e "$(date '+%a %b %d %T') $(hostname): ${BOLD}Calling API endpoint${NORMAL}: $JAMF_URL/JSSResource/computers/serialnumber/"

    #get scoped configuration profiles ID's for device from Jamf
    start=$(date +%s)
    scoped_profile=$(curl --silent --location --request GET "$JAMF_URL/JSSResource/computers/serialnumber/$SERIALNUMBER" \
        --header "Accept: application/json" \
        --header "Authorization: Basic #encoded_b64" | jq -r '.computer.configuration_profiles[] | .id | (select ( . >= 0))')
    end=$(date +%s)
    runtime=$((end - start))
    echo -e "$(date '+%a %b %d %T') $(hostname): Gathered scoped profiles ID's for device ($SERIALNUMBER) in ${BOLD}$runtime seconds${NORMAL}."

    #retrieve UUID's of scoped profiles from Jamf
    echo -e "$(date '+%a %b %d %T') $(hostname): ${BOLD}Calling API endpoint${NORMAL}: $JAMF_URL/JSSResource/osxconfigurationprofiles/id/"
    start=$(date +%s)
    line=1
    for id in $scoped_profile; do
        uuid=$(curl --silent --location --request GET "$JAMF_URL/JSSResource/osxconfigurationprofiles/id/$id" \
            --header "Accept: application/json" \
            --header "Authorization: Basic #encoded_b64" | jq -r '.os_x_configuration_profile.general.uuid')
        echo $uuid >>/tmp/scoped
        echo -e "$(date '+%a %b %d %T') $(hostname): 🔽 $line \t- $uuid"
        ((line = line + 1))
    done
    end=$(date +%s)
    runtime=$((end - start))
    echo -e "$(date '+%a %b %d %T') $(hostname): Gathered scoped profiles UUID's in ${BOLD}$runtime seconds${NORMAL}."

    #get installed configuration profiles identifiers
    installed=("$(sudo /usr/bin/profiles -P | sed '$ d' | awk '{print $NF}')")
    scoped=()
    while IFS= read -r line || [[ "$line" ]]; do
        scoped+=("$line")
    done </tmp/scoped

    #check installed profiles against scoped profiles
    echo -e "$(date '+%a %b %d %T') $(hostname): Valdation of scoped profiles:"
    line=1
    for id in "${scoped[@]}"; do
        if printf -- '%s\n' "${installed[@]}" | grep -q $id; then
            echo -e "$(date '+%a %b %d %T') $(hostname): ✅ $line \t- $id"
            ((line = line + 1))
            cat /tmp/validation.json | jq -n --arg profile $id --arg status success '{profile:($profile),status:($status)}' >>/tmp/validation.json
        else
            echo -e "$(date '+%a %b %d %T') $(hostname): ❌ $line \t- $id"
            ((line = line + 1))
            cat /tmp/validation.json | jq -n --arg profile $id --arg status failure '{profile:($profile),status:($status)}' >>/tmp/validation.json
        fi
    done

    #cleanup
    rm /tmp/scoped
    #rm /tmp/profile
}

#validate profile status from JSON until all succesful
validate() {
    touch /tmp/validation.json
    tasknumber=0
    while [[ $status != success ]]; do
        #if not successful rerun checkprofiles function
        tasknumber_exit=10
        sleep 1
        ((tasknumber = tasknumber + 1))

        #When timeout is reached, push error screen Octory and delete temporary file
        if [ $tasknumber -gt $tasknumber_exit ]; then
            end_script=$(date +%s)
            runtime_script=$((end_script - start_script))
            echo -e "$(date '+%a %b %d %T') $(hostname): 🐴 Timout! Script ran for ${BOLD}$runtime_script seconds${NORMAL}."
            exit 1
        fi
        checkprofiles
        if jq '.status' /tmp/validation.json | grep -q failure; then
            status=failure
            echo -e "$(date '+%a %b %d %T') $(hostname): 🐴 Missing profiles"
            rm /tmp/validation.json
        else
            status=success
            end_script=$(date +%s)
            runtime_script=$((end_script - start_script))
            echo -e "$(date '+%a %b %d %T') $(hostname): 🦄 Completed in ${BOLD}$runtime_script seconds${NORMAL}, continuing script"
            rm /tmp/validation.json
            break
        fi
    done
}

#run script
validate
