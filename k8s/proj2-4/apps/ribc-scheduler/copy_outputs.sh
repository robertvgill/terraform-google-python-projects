#!/bin/bash

while getopts :d:o: opt; do
    case $opt in
	d)
	    SCHEDULE_DESTINATION=$OPTARG
	    ;;
	o)
	    OUTPUT_FOLDER=$OPTARG
	    ;;
	\?)
	    echo "Invalid option: -$OPTARG" >& 2
	    exit 1
	    ;;
	:)
	    echo "Option -$OPTARG requires an argument." >& 2
	    exit 1
	    ;;
    esac
done

if [ -z "$SCHEDULE_DESTINATION" ]; then
   echo "Option -d not set" >& 2
   exit 1
fi

if [ -z "$OUTPUT_FOLDER" ]; then
    echo "Option -o not set" >$ 2
    exit 1
fi

echo "Uploading scheduling results from $OUTPUT_FOLDER to $SCHEDULE_DESTINATION..."
sleep 3
echo "Done."
