#!/bin/bash
# To debug this script
# set SLACK_TEST_MODE variable with not empty string.

# SERVICE_NAME="vi-svc.com"
# SLACK_TEST_MODE="yes"
# SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."
# SKIP_PARTITIONS="/dev/loop1;/dev/loop2;/dev/loop3;/dev/loop4"

# ------------
hostname=${HOSTNAME}
local_ip=$(echo $(hostname -I) | xargs)
public_ip=$(dig @resolver1.opendns.com ANY myip.opendns.com +short)
alarm=""

# ------------
# Read service name param
service_name=$1
if [[ $service_name == "" ]]; then
        service_name=${SERVICE_NAME}
        if [[ $service_name == "" ]]; then
                echo "No service_name specified"
                service_name=${HOSTNAME}
        fi
fi

# ------------
# Read webhook URL param
shift
webhook_url=$1
if [[ $webhook_url == "" ]]; then
        webhook_url=${SLACK_WEBHOOK_URL}
        if [[ $webhook_url == "" ]]; then
                echo "No webhook_url specified"
                exit 1
        fi
fi

# ------------
shift
channel=$1
if [[ $channel == "" ]]; then
        channel=${SLACK_CHANNEL}
        if [[ $channel == "" ]]; then
                echo "No channel specified, posting to default channel."
        fi
fi

# ------------
# Execute df-h
text="$(df -h)"
pretext="Summary of available disk storage space on *\`$hostname\`*."

# ------------
# Generate the JSON payload to POST to slack
json="{"
if [[ $channel != "" ]]; then
        json+="\"channel\": \"$channel\","
fi
json+="\"attachments\":["
IFS=$'\n'
for textLine in $text
do
        IFS=$' '
        words=($textLine)
        if [[ ${words[0]} == "Filesystem" ]]; then
                # This is the header line of df- h command
		json+="{\"author_name\":\"$service_name\", \"author_icon\": \"https://cdn2.iconfinder.com/data/icons/amazon-aws-stencils/100/Compute__Networking_copy_Amazon_EC2---512.png\","
		json+="\"text\":\"Host Name: $hostname\nPrivate IP: $local_ip\nPublic IP: $public_ip\""
		json+="},"
                json+="{\"text\": \"\`\`\`\n$textLine\n\`\`\`\", \"pretext\":\"$pretext\", \"color\":\"#0080ff\"},"
        else
                # Check the returned 'used' column to determine color
                used=${words[4]%\%}
		if [[ "$SKIP_PARTITIONS" == *"${words[0]}"* ]]; then
                        color="#808080"
                elif [[ $used -gt 89 ]]; then
                        color="danger"
			alarm="danger"
                elif [[ $used -gt 69 ]]; then
                        color="warning"
			alarm="warning"
                else
                        color="good"
                fi
                json+="{\"text\": \"\`\`\`\n$textLine\n\`\`\`\", \"color\":\"$color\"},"
        fi
done

# trim trailing comma
json="${json::-1}"

# -----------
# Complete JSON payload and make API request
json+="]}"

if [[ $alarm != "" || $SLACK_TEST_MODE != "" ]]; then
    cd "$(dirname "$0")";
    echo $(pwd)

    if [ -f ./slack-storage-notifier.log ]; then
        echo "Already notified !"
        find . -name *.log -mmin +60 -print
        find . -name *.log -mmin +60 -exec rm -f {} \;
        exit 1
    fi

    curl -s -d "payload=$json" "$webhook_url"
    touch slack-storage-notifier.log
fi
