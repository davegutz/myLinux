#!/bin/bash
# jobStat.sh
# Echo status to terminal so progress can be monitored

# Usage: run as needed with one text argument
#   jobStat.sh "e:  film name" &

echo -en "$1"
sleep 5
echo -en "$1"
sleep 5
echo -en "$1"
sleep 10
echo -en "$1"
sleep 20
echo -en "$1"
sleep 40
echo -en "$1"
while [ true ]; do
	sleep 120
	echo -en "$1"
done
