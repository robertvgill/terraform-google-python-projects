#!/bin/bash

while getopts :i: opt; do
    case $opt in
	i)
	    INPUT_FOLDER=$OPTARG
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

if [ -z "$INPUT_FOLDER" ]; then
   echo "Option -i not set" >& 2
   exit 1
fi   	       

echo "Copying scheduling inputs to $INPUT_FOLDER..."
sleep 2
echo "Done."
