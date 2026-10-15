#!/usr/bin/env bash
# Make a listing of all video files an their run time
# run by './run_time.sh >result.txt'
OIFS="$IFS"
IFS=$'\n'
for vidfil in *.m??
do
     echo -en \""$vidfil"\"', '
     ffprobe -i "$vidfil" -show_entries format=duration -v quiet -of csv="p=0"
done
IFS="$OIFS"

