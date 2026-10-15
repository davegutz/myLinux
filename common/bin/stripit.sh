#!/bin/bash
# stripit.sh

# Delete "!" from file names
#

OIFS="$IFS"
IFS=$'\n'

items=`ls -1|grep "!"`
for old_file in $items
do
	new_file=`echo $old_file|sed 's/!//g'`
	mv "$old_file" "$new_file"
done

IFS="$OIFS"
