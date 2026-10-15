#!/bin/bash
# renameit.sh

# add dates to file names.  the .txt file must be saved in unux line feed EOL format
# ./renameit.sh mv_colondelimited.txt

infile=$1
if [ -z "$infile" ]; then
	echo "ERROR($0):  must supply file name as first argument"
	exit 1
fi

DEST=$infile'.m4v'
cat $infile | while IFS=':' read -r old new
do
	oldstr="$old".m4v
	newstr="$new".m4v
	ls /cygdrive/w/Movies/"$oldstr"
#	ls /cygdrive/x/Movies/"$oldstr"
done
