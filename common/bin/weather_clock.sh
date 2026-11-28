#!/bin/bash
TEMP=$(curl -s "wttr.in/Meredith,NH?format=%t")
TIME=$(date +"%I:%M %p")
DATE=$(date +"%a, %b %d")
echo "$TIME"
echo "$DATE"
echo "$TEMP"
