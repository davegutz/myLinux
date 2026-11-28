#!/bin/bash
TIME=$(date +"%I:%M %p")
DATE=$(date +"%a, %b %d")
WEATHER=$(curl -s --max-time 4 "wttr.in/Meredith,NH?format=%c+🌡️%t+(feels+like+%f)+🌬️%w\nForecast:+%C")

echo "$TIME"
echo "$DATE"
echo "$WEATHER"
