#!/bin/bash

###################################################
# Make sure user didn't force script to run in sh #
###################################################

ps ax | grep $$ | grep bash > /dev/null ||
{
	clear
	echo "You are forcing the script to run in sh when it was written for bash."
	echo "Please run it in bash instead, and NEVER run any script the way you just did."
	exit 1
}

############################
# Only run if user is root #
############################

uid=$(/usr/bin/id -u) && [ "$uid" = "0" ] || 
{
	clear
	echo "You must be root to run $0."
	echo "Try again with the command 'sudo $0'"
	exit 1
} 

##############################################################################
# Check if the user is trying to run this script from within the RAM Session #
##############################################################################

if [ -e /RAM_Session ]
then
	clear
	echo "This script cannot be run from inside the RAM Session."
	exit 0
fi

####################
# Global Variables #
####################

#The folder where this script is located
#Used to make sure that the script can be run from any folder
SCRIPT_DIR=$(readlink -f $(dirname $0))

#The log file
LOG='/var/log/ram_booster.log'

#Ubuntu Version this script will work on
UBUNTU_VERSION='14.10'

#Path to the file that contains all the functions for this script
RAM_LIB="$SCRIPT_DIR/extras_$UBUNTU_VERSION/ram_lib"

#Path to the rupdate script
RUPDATE_FILE="$SCRIPT_DIR/extras_$UBUNTU_VERSION/rupdate"

#Path to the rupgrade script
RUPGRADE_FILE="$SCRIPT_DIR/extras_$UBUNTU_VERSION/rupgrade"

#Path to the rchroot script
RCHROOT_FILE="$SCRIPT_DIR/extras_$UBUNTU_VERSION/rchroot"

#Path to the rlib library
RLIB_FILE="$SCRIPT_DIR/extras_$UBUNTU_VERSION/rlib"

#Path to the 06_RAMSESS
GRUB_06_RAMSESS_SCRIPT="$SCRIPT_DIR/extras_$UBUNTU_VERSION/06_RAMSESS"

#Path to the za_ram_session_initramfs kernel postinst script
INITRAMFS_SCRIPT="$SCRIPT_DIR/extras_$UBUNTU_VERSION/postinst.d/za_ram_session_initramfs"

#Path to the zb_version_check kernel postinst script
VER_CHECK_SCRIPT="$SCRIPT_DIR/extras_$UBUNTU_VERSION/postinst.d/zb_version_check"

#Path to the zc_sort_kernels kernel postinst script
SORT_KERNELS_SCRIPT="$SCRIPT_DIR/extras_$UBUNTU_VERSION/postinst.d/zc_sort_kernels"

#True if home is already on another partition. False otherwise
HOME_ALREADY_MOUNTED=$(df /home | tail -1 | grep -q '/home' && echo true || echo false)

#True if /home should just be copied over to $DEST/home
#False otherwise
#Note: Do NOT remove the default value
COPY_HOME=true

#The new location of /home
#Note: Here, we check the old location of /home, but later we can change it
#to reflect the new location
HOME_DEV=$(readlink -f `df /home | grep -o '/dev/[^ ]*'`)

#The device of the root partition
ROOT_DEV=$(readlink -f `df / | grep -o '/dev/[^ ]*'`)

#The device of the boot partition
BOOT_DEV=$(readlink -f `df /boot | grep -o '/dev/[^ ]*'`)

#The device of /boot/efi, if it exists
EFI_DEV=$(readlink -f `df /boot/efi 2>/dev/null | grep -o '/dev/[^ ]*'` 2>/dev/null || echo None)

#The UUID of the home partition
#Gets set later
HOME_UUID=''

#The UUID of the root partition
ROOT_UUID=$(sudo blkid -o value -s UUID $ROOT_DEV)

#The UUID of the boot partition
BOOT_UUID=$(sudo blkid -o value -s UUID $BOOT_DEV)

#The UUID of the /boot/efi partition, if it exists
EFI_UUID=$([[ "$EFI_DEV" != "None" ]] && sudo blkid -o value -s UUID $EFI_DEV || echo None)

#The folder where the RAM Session will be stored
DEST=/var/squashfs/

#Only applies when the Original OS starts out having /home on the same partition as /
#and the user chooses to use a separate partition for /home on the RAM Session
#true if the Original OS's /etc/fstab should be modified to also use
#	the partition that the RAM Session will be using as /home
#false if it should not
SHARE_HOME=false

##########################################################
# Source the file with all the functions for this script #
##########################################################

if [[ -e $RAM_LIB ]]
then
	. $RAM_LIB

	#Check if there was a problem
	if [[ "$?" != "0" ]]
	then
		echo
		echo "The library that comes with RAM Booster ($RAM_LIB) failed to be sourced"
		echo "Is it broken?"
		exit 1
	fi
else
	clear
	echo "The library that comes with RAM Booster ($RAM_LIB) was not found!"
	exit 1
fi

############################
# Check if OS is supported #
############################

OS_NAME=$(cat /etc/os-release | grep PRETTY_NAME | grep -o "\"[^\"]*\"" | tr -d '"')
OS_VERSION=$(cat /etc/os-release | grep VERSION_ID | grep -o "\"[^\"]*\"" | tr -d '"')

if [[ "$OS_VERSION" != "$UBUNTU_VERSION" ]]
then
	clear
	ECHO "This script was written to work with Ubuntu ${UBUNTU_VERSION}. You are running ${OS_NAME}. This means the script has NOT been tested for your OS."
	echo
	echo "Run this at your own risk."
	echo 
	echo "Press enter to continue or Ctrl+C to exit"
	read key
fi

############################
# Check for rupdate script #
############################

if [[ ! -e $RUPDATE_FILE ]]
then
	clear
	echo "\"$RUPDATE_FILE\" was not found!"
	exit 1
fi

#############################
# Check for rupgrade script #
#############################

if [[ ! -e $RUPGRADE_FILE ]]
then
	clear
	echo "\"$RUPGRADE_FILE\" was not found!"
	exit 1
fi

############################
# Check for rchroot script #
############################

if [[ ! -e $RCHROOT_FILE ]]
then
	clear
	echo "\"$RCHROOT_FILE\" not found!"
	exit 1
fi

##########################
# Check for RLIB library #
##########################

if [[ ! -e $RLIB_FILE ]]
then
	clear
	echo "\"$RLIB_FILE\" not found!"
	exit 1
fi

####################################
# Check args passed to this script #
####################################

case "$1" in
	--uninstall)
		#If $1 is --uninstall, force uninstall and exit
		clear
		Uninstall_Prompt
		exit 0
		;;
	"")
		#If no args, no problem
		;;
	*)
		#If $1 is anything else, other than "--uninstall" or blank, it's invalid
		clear
		echo "\"$1\" is not a valid argument"
		exit 1
		;;
esac

########################################################
# Check if RAM_booster has already run on this machine #
########################################################

if [ -e /Original_OS ]
then
	clear
	ECHO "$0 has already run on this computer. It will not run again until you uninstall it."
	echo
	read -p "Would you like to uninstall the RAM Session? [y/N]: " answer

	#Convert answer to lowercase
	answer=$(toLower $answer)

	case $answer in
		y|yes)
			clear
			Uninstall_Prompt
			exit 0
			;;  
		*)  
			exit 0
			;;  
	esac
fi

############################################################################
# If at any point the user hits Ctrl+C, quietly clean up any files we      #
# may have created.                                                        #
# Note: If the user hits Ctrl+C AFTER we start copying the filesystem to   #
# $DEST, a different trap will be activated which will be a lot less quiet #
############################################################################
trap 'echo; Uninstall_RAM_Booster quiet; exit 1' SIGINT

####################################################################
# Overwrite old logfile, and check if we can write to $LOG at all, #
# drawing a line on top to start the border of the first command   #
####################################################################

echo '================================================================================' | sudo tee $LOG &>/dev/null ||
{
	clear
	echo "Failed to write to '$LOG' log file"
	echo "Exiting..."
	Uninstall_RAM_Booster quiet
	exit 1
}

##################################
# Write some useful info to $LOG #
##################################

#/etc/fstab
LOGGER "$(echo -e "/etc/fstab:\n"; cat /etc/fstab)"

#/etc/lsb-release
LOGGER "$(echo -e "/etc/lsb-release:\n"; cat /etc/lsb-release)"

#Some git info
LOGGER "$(echo "Git:"; echo -en "\tCurrent Branch:\n\t\t"; git branch | grep '[*]'; echo -en "\tLatest Commit:\n\t\t"; git log --oneline -1 | cut -d ' ' -f 1)"

#fdisk
LOGGER "$(echo "fdisk -l:"; sudo fdisk -l)"

#blkid which shows the UUIDs that fstab uses
LOGGER "$(echo -e "blkid:\n"; sudo blkid)"

#################################################################
# Create /var/lib/ram_booster/conf which rlib, rupdate, rchroot #
#         and the Uninstall_RAM_Booster function can use        #
# Note: Must be after section that checks args, or              #
#         /var/lib/ram_booster/conf will get created even if    #
#         script is called with --uninstall                     #
#################################################################

#If the folder already exists (wasn't cleaned up on last run), delete it
if [[ -d /var/lib/ram_booster ]]
then
	sudo rm -rf /var/lib/ram_booster
fi

#Create the folder
sudo mkdir /var/lib/ram_booster 2>/dev/null

#Set permissions on the folder
sudo chown root:root /var/lib/ram_booster 2>/dev/null
sudo chmod 755 /var/lib/ram_booster 2>/dev/null

#Create /var/lib/ram_booster/conf
sudo touch /var/lib/ram_booster/conf &>/dev/null

#Check exit status
if [[ "$?" != "0" ]]
then
	echo
	echo "Failed to create /var/lib/ram_booster/conf"
	echo "Exiting..."
	Uninstall_RAM_Booster quiet
	exit 1
fi

#Set permissions on the file
sudo chown root:root /var/lib/ram_booster/conf 2>/dev/null
sudo chmod 644 /var/lib/ram_booster/conf 2>/dev/null

#####################################
# Add rlib to /var/lib/ram_booster/ #
#####################################

#Copy the script
sudo cp $RLIB_FILE /var/lib/ram_booster/

#Set permissions
sudo chown root:root /var/lib/ram_booster/rlib 2>/dev/null
sudo chmod 644 /var/lib/ram_booster/rlib 2>/dev/null

#########################################################################
# Add zb_version_check kernel postinst script to /etc/kernel/postinst.d #
#########################################################################
SCRIPT_FILE_NAME=$(basename $VER_CHECK_SCRIPT)

sudo cp $VER_CHECK_SCRIPT /etc/kernel/postinst.d/
sudo chown root:root /etc/kernel/postinst.d/$SCRIPT_FILE_NAME 2>/dev/null
sudo chmod 755 /etc/kernel/postinst.d/$SCRIPT_FILE_NAME 2>/dev/null

########################################################################
# Add zc_sort_kernels kernel postinst script to /etc/kernel/postinst.d #
########################################################################
SCRIPT_FILE_NAME=$(basename $SORT_KERNELS_SCRIPT)

sudo cp $SORT_KERNELS_SCRIPT /etc/kernel/postinst.d/
sudo chown root:root /etc/kernel/postinst.d/$SCRIPT_FILE_NAME 2>/dev/null
sudo chmod 755 /etc/kernel/postinst.d/$SCRIPT_FILE_NAME 2>/dev/null

#################################################
# Find out what the user wants to do with /home # 
#################################################

clear
ECHO "This script will create a copy of your Ubuntu OS in ${DEST} and then use that copy to create a squashfs image of it located at /live. After this separation, your old OS and your new OS (the RAM Session) will be two completely separate entities. Updates of one OS will not affect the update of the other (unless done so using the update script - in which case two separate updates take place one after the other), and the setup of packages on one will not transfer to the other. Depending on what you choose however, your /home may be shared between the two systems."

echo

ECHO "/home is the place where your desktop, documents, music, pictures, and program settings are stored. Would you like /home to be stored on a separate partition so that it can be writable? If you choose yes, you may need to provide a device name of a partition as this script will not attempt to partition your drives for you. If you choose no, /home will be copied to the RAM session as is, and will become permanent. This means everytime you reboot, it will revert to the way it is right now. Moving it to a separate partition will also make /home shared between the two systems."

#If /home is already on a separate partition, let the user know
if $HOME_ALREADY_MOUNTED
then
	echo
	ECHO "Your /home is currently located on $HOME_DEV. If you choose to have it separate, the RAM Session will mount the $HOME_DEV device as /home as well."
fi

echo
read -p "What would you like to do?: [(S)eparate/(c)opy as is]: " answer

#Convert answer to lowercase
answer=$(toLower $answer)

case $answer in
	s|separate)
		COPY_HOME=false

		if $HOME_ALREADY_MOUNTED
		then
			#/home is already on a separate partition, so we know exactly what to use
			echo
			ECHO "You chose to use $HOME_DEV as your /home for the RAM Session"
			sleep 4
		else
			#Ask user what he wants to use as /home
			#Note: This function sets the global variable $HOME_DEV
			Ask_User_About_Home

			#Ask_User_About_Home clears the CtrlC trap,
			#so here, we reset it
			trap CtrlC SIGINT
		fi
		;;  
	c|copy)  
		COPY_HOME=true

		#If the Original OS was already using some partition
		#as /home, and you chose to copy /home to RAM_Session
		#instead of use that partition, force HOME_DEV to be the
		#same as ROOT_DEV
		if $HOME_ALREADY_MOUNTED
		then
			HOME_DEV="$ROOT_DEV"
		fi

		echo
		ECHO "You chose to copy /home as is. I hope you read carefully and know what that means..."
		sleep 4
		;;  
	*)
		echo
		echo "Invalid answer"
		echo "Exiting..."
		Uninstall_RAM_Booster quiet
		exit 1
		;;
esac

####################################################################################
# If the Original OS's /home was on the same partition as /, and the user chose    #
# to have the RAM Session's /home on a separate partition, ask if we should change #
# the Original OS's /etc/fstab to also mount that partition as /home               #
####################################################################################

if ! $COPY_HOME
then
	if ! $HOME_ALREADY_MOUNTED
	then
		#Ask user if they want to share /home
		clear
		ECHO "Would you like to have your Original OS use $HOME_DEV as its /home as well?"
		echo
		ECHO "If you choose yes, your Original OS's /home and your RAM Session's /home will be shared"
		echo
		ECHO "If you choose no, your Original OS's /home and your RAM Session's /home will be different"
		echo
		read -p "Your choice [Y/n]: " answer

		#Convert answer to lowercase
		answer=$(toLower $answer)

		case $answer in
			n|no)  
				SHARE_HOME=false
				echo
				ECHO "Your Original OS's /home and your RAM Session's /home will remain separate."
				sleep 4
				;;
			*)
				SHARE_HOME=true

				echo
				ECHO "Your /etc/fstab will be modified to mount $HOME_DEV as your /home at boot"
				sleep 4
				;;
		esac
	else
		#If user chose to use a separate partition for /home,
		#and the Original OS was already doing this, we are still
		#sharing /home
		SHARE_HOME=true
	fi
fi

############################################################
# Write some global variables to /var/lib/ram_booster/conf #
############################################################

#Figure out the UUID of the home partition
HOME_UUID=$(sudo blkid -o value -s UUID $HOME_DEV)

echo "DEST=$DEST" | sudo tee -a /var/lib/ram_booster/conf &>/dev/null
echo "SHARE_HOME=$SHARE_HOME" | sudo tee -a /var/lib/ram_booster/conf &>/dev/null
echo "HOME_ALREADY_MOUNTED=$HOME_ALREADY_MOUNTED" | sudo tee -a /var/lib/ram_booster/conf &>/dev/null
echo "ROOT_DEV=$ROOT_DEV" | sudo tee -a /var/lib/ram_booster/conf &>/dev/null
echo "ROOT_UUID=$ROOT_UUID" | sudo tee -a /var/lib/ram_booster/conf &>/dev/null
echo "BOOT_DEV=$BOOT_DEV" | sudo tee -a /var/lib/ram_booster/conf &>/dev/null
echo "BOOT_UUID=$BOOT_UUID" | sudo tee -a /var/lib/ram_booster/conf &>/dev/null
#Blank line
echo "" | sudo tee -a /var/lib/ram_booster/conf &>/dev/null
echo "#The \$HOME_DEV and \$HOME_UUID variables reflect what the RAM Session should be using" | sudo tee -a /var/lib/ram_booster/conf &>/dev/null
echo "#The Original OS may be using something else for /home" | sudo tee -a /var/lib/ram_booster/conf &>/dev/null
echo "HOME_DEV=$HOME_DEV" | sudo tee -a /var/lib/ram_booster/conf &>/dev/null
echo "HOME_UUID=$HOME_UUID" | sudo tee -a /var/lib/ram_booster/conf &>/dev/null
echo "EFI_DEV=$EFI_DEV" | sudo tee -a /var/lib/ram_booster/conf &>/dev/null
echo "EFI_UUID=$EFI_UUID" | sudo tee -a /var/lib/ram_booster/conf &>/dev/null

########################################################################
# If the user hits Ctrl+C at any point, have the script ask to cleanup #
########################################################################

trap CtrlC SIGINT

###################################
# Install some essential packages #
###################################

clear
echo "Installing essential packages:"

echo "Running apt-get update..."
COMMAND sudo apt-get update

echo "Installing squashfs-tools..."
COMMAND sudo apt-get -y --force-yes install squashfs-tools ||
{
	ECHO "squashfs-tools failed to install. You'll have to download and install it manually..."
	Uninstall_RAM_Booster quiet
	exit 1
}

echo "Installing live-boot-initramfs-tools..."
COMMAND sudo apt-get -y --force-yes install live-boot-initramfs-tools ||
{
	ECHO "live-boot-initramfs-tools failed to install. You'll have to download and install it manually..."
	Uninstall_RAM_Booster quiet
	exit 1
}

COMMAND sudo apt-get -y --force-yes install live-boot ||
{
	ECHO "live-boot failed to install. You'll have to download and install it manually..."
	Uninstall_RAM_Booster quiet
	exit 1
}

echo "Packages installed successfully"

#####################
# Remove ureadahead #
#####################
#Reasoning:
#ureadahead preloads commonly used programs to ram. Since we're loading
#everything into RAM, it's unnecessary

echo
echo "Removing ureadahead..."

COMMAND sudo apt-get -y purge ureadahead ||
{
	ECHO "Failed to remove ureadahead. This is NOT a major problem."
}

#######################################################
# Change a few things to make boot process look nicer #
#######################################################

echo
echo "Making boot process look nicer..."

#Hide expr error on boot
COMMAND sudo sed -i 's/\(size=$( expr $(ls -la ${MODULETORAMFILE} | awk '\''{print $5}'\'') \/ 1024 + 5000\)\( )\)$/\1 2>\/dev\/null\2/' /lib/live/boot/9990-toram-todisk.sh

#Hide 'sh:bad number' error on boot
COMMAND sudo sed -i 's#\(if \[ "\${freespace}" -lt "\${size}" ]\)$#\1 2>/dev/null#' /lib/live/boot/9990-toram-todisk.sh

#Make rsync at boot use human readable byte counter
COMMAND sudo sed -i 's/rsync -a --progress/rsync -a -h --progress/g' /lib/live/boot/9990-toram-todisk.sh

#The following 2 sed lines change the way rsync appears on screen at boot
#The final result will be this:
#	1. Wait 1 second for user to finish reading whatever was on screen (or take a picture of it or something)
#	2. Clear the screen
#	3. Show:
#		* Copying /live/medium/live/filesystem.squashfs to RAM
#		* filesystem.squashfs: 1.19G
#	4. Add newline
#	5. Show the rsync process copying filesystem.squashfs to RAM
#	6. Add some newlines before letting the system continue
#Note: The grep command checks to see if the fix has been applied to
#the file already by looking for the strings '033c' and '#Part 2" in it

grep -q '033c' /lib/live/boot/9990-toram-todisk.sh ||
COMMAND sudo sed -i 's#\(echo " [*] Copying $MODULETORAMFILE to RAM" 1>/dev/console\)#sleep 1\
				echo -ne "\\033c" 1>/dev/console\
				\1\
				echo -n " * `basename $MODULETORAMFILE` is: " 1>/dev/console\
				rsync -h -n -v ${MODULETORAMFILE} ${copyto} | grep "total size is" | grep -Eo "[0-9]+[.]*[0-9]*[mMgG]" 1>/dev/console\
				echo 1>/dev/console#g' /lib/live/boot/9990-toram-todisk.sh

grep -q '#Part 2' /lib/live/boot/9990-toram-todisk.sh ||
COMMAND sudo sed -i 's#\(rsync -a -h --progress .*\)#\1\
				\#Part 2\
				echo 1>/dev/console\
				echo 1>/dev/console#g' /lib/live/boot/9990-toram-todisk.sh

#Fix the "can't create /root/etc/fstab.d/live: nonexistent directory" error at boot
#Appears on Ubuntu 14.10
sudo sed -i 's|^\(\t\t\)\(echo.*/root/etc/fstab.d/live$\)|\1[ -d /root/etc/fstab.d ] \&\& \2|g' /lib/live/boot/9990-fstab.sh

############################################################################
# Tell /bin/live-update-initramfs not to worry about creating an initramfs #
# image when a new kernel is installed - we'll be doing this ourselves     #
############################################################################

#Note: /bin/live-update-initramfs tries to write to
#/lib/live/mount/medium/live without checking it if exists, which it does
#not. All we do here is tell it to check first, which has the desired
#effect of it not messing with the initramfs image apt-get installs
#in /boot
sudo sed -i 's|\(/proc/mounts\)$|\1 \&\& [ -d /lib/live/mount/medium/live/ ]|g' /bin/live-update-initramfs

#########################################
# Update the kernel module dependencies #
#########################################

echo
echo "Updating the kernel module dependencies..."
sudo depmod -a

if [[ "$?" != 0 ]] 
then
        echo "Kernel module dependencies failed to update."
	echo
        echo "Exiting..."
	Uninstall_RAM_Booster quiet
        exit 1
else
        echo "Kernel module dependencies updated successfully."
fi

########################
# Update the initramfs #
########################

echo
echo "Updating the initramfs..."
sudo update-initramfs -u

if [[ "$?" != 0 ]] 
then
        echo "Initramfs failed to update."
	echo
        echo "Exiting..."
	Uninstall_RAM_Booster quiet
        exit 1
else
        echo "Initramfs updated successfully."
fi

##################################################
# Create folder where RAM Session will be stored #
##################################################

sudo mkdir -p ${DEST}

###########################################################################
# Write files to / to identify where you are - Original OS or RAM Session #
###########################################################################

sudo bash -c 'echo "This is the RAM Session. Your OS is running from within RAM." > '${DEST}'/RAM_Session'
sudo bash -c 'echo "This is your Original OS. You are NOT inside the RAM Session." > /Original_OS'

############################################
# Run /etc/kernel/postinst.d/version_check #
############################################

SCRIPT_FILE_NAME=$(basename $VER_CHECK_SCRIPT)

#Create list of kernels the Original OS supports
sudo /etc/kernel/postinst.d/$SCRIPT_FILE_NAME

#The list of kernels the Original OS supports is
#exactly the same while the RAM Session is being installed
sudo cp -a /boot/Orig /boot/RAM_Sess

###########################
# Add Grub2 entry to menu #
###########################

SCRIPT_FILE_NAME=$(basename $GRUB_06_RAMSESS_SCRIPT)

#Adding entry to Grub2 menu
echo
echo "Adding entry to Grub2 menu"

#Copy 06_RAMSESS to grub folder
cp $GRUB_06_RAMSESS_SCRIPT /etc/grub.d/

#Set permissions
sudo chown root:root /etc/grub.d/$SCRIPT_FILE_NAME 2>/dev/null
sudo chmod 755 /etc/grub.d/$SCRIPT_FILE_NAME 2>/dev/null

#Unhide grub menu by uncommenting line in /etc/default/grub
sudo sed -i 's/\(GRUB_HIDDEN_TIMEOUT=0\)/#\1/g' /etc/default/grub

#Inform user everything went well
echo "Grub entry added successfully."

########################
# Copy the OS to $DEST #
########################

CopyFileSystem

#####################################################################
# Block update-grub from running in the RAM Session without rupdate #
# since it fails when it runs there, and it's unnecessary           #
# Note: Since we never modify the Original OS, we do not need to    #
# have our Uninstall function remove this explicitly - it gets      #
# removed with /var/squashfs                                        #
#####################################################################

#Modify $DEST/usr/sbin/update-grub
sudo sed -i '$i\
if [ -e /RAM_Session ]\
then\
	if [ "$(ls -di / | cut -d " " -f 1)" = 2 ] || [ "$(ls -di / | cut -d " " -f 1)" = 128 ]\
	then\
		echo "update-grub cannot be run from RAM Session unless you are using rchroot"\
		echo "Ignoring grub-update request"\
		exit 0\
	fi\
fi' ${DEST}/usr/sbin/update-grub

###############
# Update Grub #
###############

echo
echo "Updating grub:"
sudo update-grub

#############################################
# Add note to fake /boot that it's not real #
#############################################
echo "This is NOT the real /boot. This is a temporary /boot that software you install in the RAM Session can use to stay happy. The real boot is mounted when you use one of the scripts to update or make changes." | sudo tee $DEST/boot/IMPORTANT_README >/dev/null

##############################################
# Remove /boot from RAM Session's /etc/fstab #
##############################################
#Reasoning:
#Because of the nature of the RAM Session - the fact that it reverts
#back to a previous state after a reboot, if /boot was placed into a
#separate partition, it would be exempt from this action. In cases where
#software is installed that makes changes to /boot, such as changes
#to initrd images, a reboot would result in the software that made the
#changes being removed while the initrd image would still contain the
#changes. This would cause the OS to be in an inconsistent state. I'm no
#expert on the linux kernel by any means, and I have no idea if this is
#dangerous in any way, but updating /boot only when a permanent software
#update is going to be made just seems like the cleanest alternative.
sudo sed -i '/^UUID=[-0-9a-zA-Z]*[ \t]*\/boot[ \t]/d' $DEST/etc/fstab
sudo sed -i '/^\/dev\/...[0-9][ \t]*\/boot[ \t]/d' $DEST/etc/fstab

#Also remove /boot/efi if it's there
sudo sed -i '/^UUID=[-0-9a-zA-Z]*[ \t]*\/boot\/efi[ \t]/d' $DEST/etc/fstab
sudo sed -i '/^\/dev\/...[0-9][ \t]*\/boot\/efi[ \t]/d' $DEST/etc/fstab

#################
# Cleanup Tasks #
#################

#Clean some unnecessary files
#Note: The 'root' we skip is the name of root's cron file. Since we
#might be writing to it, we don't want to delete it
echo
echo "Cleaning unnecessary files:"
sudo find ${DEST}/var/run ${DEST}/var/crash ${DEST}/var/mail ${DEST}/var/spool ${DEST}/var/lock ${DEST}/var/backups ${DEST}/var/tmp -type f -not -name "root" -exec rm {} \;

#Delete only OLD log files
echo
echo "Deleting old log files:"
sudo find ${DEST%/}/var/log -type f -iregex '.*\.[0-9].*' -exec rm -v {} \;
sudo find ${DEST%/}/var/log -type f -iname '*.gz' -exec rm -v {} \;

#Clean current log files
echo
echo "Cleaning recent log files:"
sudo find ${DEST%/}/var/log -type f | while read file; do echo "emptied '$file'"; echo -n '' | sudo tee $file; done 

#####################################
# Add rupdate script to RAM Session #
#####################################

sudo cp $RUPDATE_FILE ${DEST}/usr/sbin/
sudo chown root:root ${DEST}/usr/sbin/rupdate
sudo chmod 755 ${DEST}/usr/sbin/rupdate

######################################
# Add rupgrade script to RAM Session #
######################################

sudo cp $RUPGRADE_FILE ${DEST}/usr/sbin/
sudo chown root:root ${DEST}/usr/sbin/rupgrade
sudo chmod 755 ${DEST}/usr/sbin/rupgrade

#####################################
# Add rchroot script to RAM Session #
#####################################

sudo cp $RCHROOT_FILE ${DEST}/usr/sbin/
sudo chown root:root ${DEST}/usr/sbin/rchroot
sudo chmod 755 ${DEST}/usr/sbin/rchroot

######################################################
# Add za_ram_session_initramfs script to RAM Session #
######################################################

SCRIPT_FILE_NAME=$(basename $INITRAMFS_SCRIPT)

sudo cp $INITRAMFS_SCRIPT ${DEST}/etc/kernel/postinst.d/
sudo chown root:root ${DEST}/etc/kernel/postinst.d/$SCRIPT_FILE_NAME 2>/dev/null
sudo chmod 755 ${DEST}/etc/kernel/postinst.d/$SCRIPT_FILE_NAME 2>/dev/null

##################################
# Write some useful info to $LOG #
##################################

#$DEST/etc/fstab
LOGGER "$(echo -e "${DEST%/}/etc/fstab:\n"; cat $DEST/etc/fstab)"

#######################
# Make squashfs image #
#######################

echo
echo "Creating squashfs image..."
sudo mkdir -p /live
sudo mksquashfs ${DEST} /live/filesystem.squashfs -noappend -always-use-fragments

#See how it went
if [[ "$?" != 0 ]]
then
        echo "Squashfs image creation failed."
	echo
        echo "Exiting..."
        exit 1
else
	echo
        echo "Squashfs image created successfully."
	sleep 4
fi

####################
# Clear the screen #
####################
clear

###########################################
# Tell user how much RAM they should have #
###########################################

#Find out how big the squashfs image ended up being
Image_Size=$(sudo du -h /live/filesystem.squashfs | awk '{ print $1 }')

#Tell user how much RAM they should have
ECHO "The size of the image is $Image_Size. This MUST fit in your total RAM, with room to spare. If it does not, you either need to buy more RAM, or manually remove unimportant packages from your OS until the image fits."
echo

ECHO "Note: Do NOT format your original OS that you made the RAM Session out of, as the squashfs image still resides there. So does $DEST, the folder the image gets recreated from everytime you make any changes to the RAM Session through the update scripts. You should be able to shrink the partition with your original OS however in order to save space."

echo
ECHO "Also, if you switch between your original OS and your RAM Session a lot, and forget which one you are in, do an 'ls /'. If you see the /Original_OS file, you are in the original OS. If you see the /RAM_Session file, you are in the RAM Session."
