#!/bin/bash

#Make sure user didn't force script to run in sh
ps ax | grep $$ | grep bash > /dev/null ||
{
	clear
	echo "You are forcing the script to run in sh when it was written for bash."
	echo "Please run it in bash instead, and NEVER run any script the way you just did."
	exit 1
} 

#Path to the file that contains all the functions for this script
RAM_LIB='./ram_lib'

#Only run if user is root
uid=$(/usr/bin/id -u) && [ "$uid" = "0" ] || 
{
	clear
	echo "You must be root to run $0."
	echo "Try again with the command 'sudo $0'"
	exit 1
} 

#Source the file with all the functions for this script
if [[ -e $RAM_LIB ]]
then
	. $RAM_LIB
else
	clear
	echo "The library that comes with RAM Booster ($RAM_LIB) was not found!"
	exit 1
fi

#Check args passwd to this script
if [[ "$1" == "--uninstall" ]]
then
	#If $1 is --uninstall, force uninstall and exit
        clear
	Uninstall_RAM_Booster
        exit 0
elif [[ "$1" != "" ]]
then
	#If $1 is anything else, other than "--uninstall" or blank, it's invalid
	clear
	echo "\"$1\" is not a valid argument"
	exit 1
fi

