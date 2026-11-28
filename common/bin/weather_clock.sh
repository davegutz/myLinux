#!/bin/bash
TIME=$(date +"%I:%M %p")
DATE=$(date +"%a, %b %d")
WEATHER=$(curl -s --max-time 4 "wttr.in/Meredith,NH?format=Temp:+%t+(feels+like+%f)+Wind:+%w\nForecast:+%C" | sed 's/→/-> /g; s/←/<- /g; s/↑/^ /g; s/↓/v /g; s/↗/^> /g; s/↖/<^ /g; s/↘/v> /g; s/↙/<v /g')

echo "$TIME"
echo "$DATE"
echo "$WEATHER"
