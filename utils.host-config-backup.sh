#!/bin/bash
#: Title		:host-config-backup.sh
#: Date			:2021-02-06
#: Author		:"Damola Adebayo" <damola@algoLifeNetworks.com>
#: Version		:1.0
#: Description	:use to create backup copy (ie one-way) of various system-specific files
#: Description	:such as configuration files that aren't covered by the routine backups
#: Description	:of the working directories.files are copied to a synchronised location
#: Options		:None

###############################################################################################
# This program is concerned only with files that are not synchronised along with the mutable files, \
# since they are DIFFERENT on each host and/or they're not accessible by regular user permissions. \
# For example:
	# global configuration files
	# git managed files
	# HOME, Downloads... dirs

# This program is only concerned with getting current copies of these files into sync-ready position \
# on respective hosts. That's it. CRON makes this happen frequently (few times per day)

# This program need only be run manually, on each host (perhaps via ssh)\
#+ on an ad-hoc (when changes are made) basis

# If the program is being run as a root cronjob, $0 will be the local git repository, otherwise \
# if run directly will be the symlink in ~/bin. The program branches based on whether interactive shell. \
# Also, when called by a root cronjob, it needs program parameters for:
	# regular username
	# destination_holding_dir_fullpath
# 
# m h  dom mon dow   command
# */10 * * * * /path/to/git/managed/host-config-backup.sh "my_username" "/dest/dir"

# Needs to run as root to get access to those global configuration files
# adjust file permissions and ownerships

# To add a new file path to this program, we just add it to the hostfiles_fullpaths_list array
# for now, but clearly this information will soon come from a json configuration file!
###############################################################################################

function main 
{
	###############################################################################################
	# GLOBAL VARIABLE DECLARATIONS:
	###############################################################################################
	
	## EXIT CODES:
	E_UNEXPECTED_BRANCH_ENTERED=10
	E_OUT_OF_BOUNDS_BRANCH_ENTERED=11
	E_INCORRECT_NUMBER_OF_ARGS=12
	E_UNEXPECTED_ARG_VALUE=13
	E_REQUIRED_FILE_NOT_FOUND=20
	E_REQUIRED_PROGRAM_NOT_FOUND=21
	E_UNKNOWN_RUN_MODE=30
	E_UNKNOWN_EXECUTION_MODE=31

	export E_UNEXPECTED_BRANCH_ENTERED
	export E_OUT_OF_BOUNDS_BRANCH_ENTERED
	export E_INCORRECT_NUMBER_OF_ARGS
	export E_UNEXPECTED_ARG_VALUE
	export E_REQUIRED_FILE_NOT_FOUND
	export E_REQUIRED_PROGRAM_NOT_FOUND
	export E_UNKNOWN_RUN_MODE
	export E_UNKNOWN_EXECUTION_MODE

	#######################################################################
	program_param_0=${1:-"not_yet_set"} ## 

	MAX_EXPECTED_NO_OF_PROGRAM_PARAMETERS=2
	ACTUAL_NO_OF_PROGRAM_PARAMETERS=$#
	ALL_THE_PARAMETERS_STRING="$@"

	echo "ALL_THE_PARAMETERS_STRING: $ALL_THE_PARAMETERS_STRING"
	
	my_username=""
	my_homedir=""
	test_line="" # global...

	USER_PRIV=
	
	abs_filepath_regex='^(/{1}[A-Za-z0-9\.\ _~:@-]+)+/?$' # absolute file path, ASSUMING NOT HIDDEN FILE, ...
	all_filepath_regex='^(/?[A-Za-z0-9\.\ _~:@-]+)+(/)?$' # both relative and absolute file path

	# TODO: host info for entry test removed until json config sorted

	ACTUAL_HOST=$(hostname)

	# array of absolute paths to host-specific directory and regular file (mostly configuration files) sources
	# this list is the superset of lists of each host - if file doesn't exist, just ignored.
	declare -a hostfiles_fullpaths_list=()	


	
	###############################################################################################

	###############################################################################################
	# 'SHOW STOPPER' FUNCTION CALLS:	
	###############################################################################################

	# verify and validate program positional parameters
	verify_and_validate_program_arguments

	# entry test to prevent running this program on an inappropriate host
	# entry tests apply only to those highly host-specific or filesystem-specific programs that are hard to generalise
	if [[ $(declare -a | grep "authorised_host_list" 2>/dev/null) ]]; then
		entry_test
	else
		echo "entry test skipped..." && sleep 1 && echo
	fi
	
	###############################################################################################
	# $SHLVL DEPENDENT FUNCTION CALLS:	
	###############################################################################################
	# using $SHLVL to show whether this script was called from another script, or from command line

	echo "OUR CURRENT SHELL LEVEL IS: $SHLVL"

	if [ $SHLVL -le 3 ]
	then
		# Display a descriptive and informational program header:
		display_program_header

		# give user option to leave if here in error:
		# USER_PRIV (reg or root) branching:
		if [ $USER_PRIV == "reg" ]
		then
			get_user_permission_to_proceed
		fi
	fi


	###############################################################################################
	# FUNCTIONS CALLED ONLY IF THIS PROGRAM USES A CONFIGURATION FILE:	
	###############################################################################################

	if [ -n "$config_file_fullpath" ]
	then
		:
		#display_current_config_file
#
		#get_user_config_edit_decision
#
		## test whether the configuration files' format is valid, and that each line contains something we're #expecting
		#validate_config_file_content
#
		## IMPORT CONFIGURATION INTO PROGRAM VARIABLES
		#import_ecrypt_mount_configuration
	fi


	###############################################################################################

	# TODO: SANITISE CODE BY GPG ENCRYPTING A FILE THAT CONTAINS ECRYPT MOUNT PARAMETERS\
	# DECRYPT AND bash -c $command FILE LINES ? 
	# AS NOT SAFE TO HARD CODE ECRYPT MOUNT PARAMETERS 

	###############################################################################################
	# TODO: remember to a cron configuration files to list

	###############################################################################################
	# PROGRAM-SPECIFIC FUNCTION CALLS:	
	###############################################################################################

	setup_dst_dir

	#exit # debug

	backup_regulars_and_dirs

	change_file_ownerships

	report_summary
	

} ## end main




###############################################################################################
####  FUNCTION DECLARATIONS  
###############################################################################################

# here because we're a logged in, regular user with a fully interactive shell
# assuming single logged in user
function get_user_inputs
{
	echo "Enter the name of the currently logged in regular user:"
	echo && sleep 1
	read my_username

	if [ $my_username == "$(id -un)" ]
	then
		echo "username VALID" && echo
	else
		# 
		echo "The valid user test FAILED"
		echo "Nothing to do now, but to exit..." && echo
		exit $E_UNEXPECTED_ARG_VALUE
	fi

	echo "Enter the full path to the destination directory:"
	echo "Copy-paste your choice" && echo
	echo && sleep 1
	find ~ -type d -name "*_host_specific_files_current" && echo # temporary dev workaound
	read destination_holding_dir_fullpath

	if [ -n "$destination_holding_dir_fullpath" ] 
	then
		sanitise_absolute_path_value "$destination_holding_dir_fullpath"
		echo "test_line has the value: $test_line"
		destination_holding_dir_fullpath=$test_line

		# this valid form test works for sanitised directory paths
		test_file_path_valid_form "${destination_holding_dir_fullpath}"
		return_code=$?
		if [ $return_code -eq 0 ]
		then
			echo "The dst filename is of VALID FORM"
		else
			echo "The valid form test FAILED and returned: $return_code"
			echo "Nothing to do now, but to exit..." && echo
			exit $E_UNEXPECTED_ARG_VALUE
		fi

		# NO FURTHER TESTS REQUIRED HERE, AS IF DIR DOESN'T YET EXIST, WE'LL SOON CREATE IT.
	else
		# 
		echo "The valid filepath test FAILED. Filepath was of zero length"
		echo "Nothing to do now, but to exit..." && echo
		exit $E_UNEXPECTED_ARG_VALUE
	fi
}
##########################################################################################################
# keep sanitise functions separate and specialised, as we may add more to specific value types in future
# FINAL OPERATION ON VALUE, SO GLOBAL test_line SET HERE. RENAME CONCEPTUALLY DIFFERENT test_line NAMESAKES
function sanitise_absolute_path_value ##
{

echo && echo "ENTERED INTO FUNCTION ${FUNCNAME[0]}" && echo

	# sanitise values
	# - trim leading and trailing space characters
	# - trim trailing / for all paths
	test_line="${1}"
	echo "test line on entering "${FUNCNAME[0]}" is: $test_line" && echo

	while [[ "$test_line" == *'/' ]] ||\
	 [[ "$test_line" == *[[:blank:]] ]] ||\
	 [[ "$test_line" == [[:blank:]]* ]]
	do 
		# TRIM TRAILING AND LEADING SPACES AND TABS
		# backstop code, as with leading spaces, config file line wouldn't even have been
		# recognised as a value!
		test_line=${test_line%%[[:blank:]]}
		test_line=${test_line##[[:blank:]]}

		# TRIM TRAILING / FOR ABSOLUTE PATHS:
		test_line=${test_line%'/'}
	done

	echo "test line after trim cleanups in "${FUNCNAME[0]}" is: $test_line" && echo

echo && echo "LEAVING FROM FUNCTION ${FUNCNAME[0]}" && echo

}
##########################################################################################################
# keep sanitise functions separate and specialised, as we may add more to specific value types in future
# FINAL OPERATION ON VALUE, SO GLOBAL test_line SET HERE...
function sanitise_relative_path_value
{

echo && echo "ENTERED INTO FUNCTION ${FUNCNAME[0]}" && echo

	# sanitise values
	# - trim leading and trailing space characters
	# - trim leading / for relative paths
	# - trim trailing / for all paths
	test_line="${1}"
	echo "test line on entering "${FUNCNAME[0]}" is: $test_line" && echo

	while [[ "$test_line" == *'/' ]] ||\
	 [[ "$test_line" == [[:blank:]]* ]] ||\
	 [[ "$test_line" == *[[:blank:]] ]]
	do 
		# TRIM TRAILING AND LEADING SPACES AND TABS
		# backstop code, as with leading spaces, config file line wouldn't even have been
		# recognised as a value!
		test_line=${test_line%%[[:blank:]]}
		test_line=${test_line##[[:blank:]]}

		# TRIM TRAILING / FOR ABSOLUTE PATHS:
		test_line=${test_line%'/'}
	done

	# FINALLY, JUST THE ONCE, TRIM LEADING / FOR RELATIVE PATHS:
	# afer this, test_line should just be the directory name
	test_line=${test_line##'/'}

	echo "test line after trim cleanups in "${FUNCNAME[0]}" is: $test_line" && echo

echo && echo "LEAVING FROM FUNCTION ${FUNCNAME[0]}" && echo

}

##########################################################################################################
# firstly, we test that the parameter we got is of the correct form for an absolute file | sanitised directory path 
# if this test fails, there's no point doing anything further
# 
function test_file_path_valid_form
{
	echo && echo "ENTERED INTO FUNCTION ${FUNCNAME[0]}" && echo

	test_result=
	test_file_fullpath=$1
	
	echo "test_file_fullpath is set to: $test_file_fullpath"
	#echo "test_dir_fullpath is set to: $test_dir_fullpath"

	if [[ $test_file_fullpath =~ $abs_filepath_regex ]]
	then
		echo "THE FORM OF THE INCOMING PARAMETER IS OF A VALID ABSOLUTE FILE PATH"
		test_result=0
	else
		echo "AN INCOMING PARAMETER WAS SET, BUT WAS NOT A MATCH FOR OUR KNOWN PATH FORM REGEX "$abs_filepath_regex"" && sleep 1 && echo
		echo "Returning with a non-zero test result..."
		test_result=1
		return $E_UNEXPECTED_ARG_VALUE
	fi 


	echo && echo "LEAVING FROM FUNCTION ${FUNCNAME[0]}" && echo

	return "$test_result"
}

###############################################################################################
# need to test for access to the file holding directory
# 
function test_dir_path_access
{
	echo && echo "ENTERED INTO FUNCTION ${FUNCNAME[0]}" && echo

	test_result=
	test_dir_fullpath=$1

	echo "test_dir_fullpath is set to: $test_dir_fullpath"

	if [ -d "$test_dir_fullpath" ] && cd "$test_dir_fullpath" 2>/dev/null
	then
		# directory file found and accessible
		echo "directory "$test_dir_fullpath" found and accessed ok" && echo
		test_result=0
	elif [ -d "$test_dir_fullpath" ] ## 
	then
		# directory file found BUT NOT accessible CAN'T RECOVER FROM THIS
		echo "directory "$test_dir_fullpath" found, BUT NOT accessed ok" && echo
		test_result=1
		echo "Returning from function \"${FUNCNAME[0]}\" with test result code: $E_FILE_NOT_ACCESSIBLE"
		return $E_FILE_NOT_ACCESSIBLE
	else
		# -> directory not found: THIS CAN BE RESOLVED BY CREATING THE DIRECTORY
		test_result=1
		echo "Returning from function \"${FUNCNAME[0]}\" with test result code: $E_REQUIRED_FILE_NOT_FOUND"
		return $E_REQUIRED_FILE_NOT_FOUND
	fi

	echo && echo "LEAVING FROM FUNCTION ${FUNCNAME[0]}" && echo

	return "$test_result"
}

##########################################################################################################
# declare after param validation, as list depends on knowing users' home dir etc...
function setup_source_dirs()
{
	echo && echo "Entered into function ${FUNCNAME[0]}" && echo

	# get crontab -l outputs redirected into a file that we can backup
	# USER_PRIV (reg or root) branching: TODO: SHOULD BE MODE: INTERACTIVE | NON-INTERACTIVE
	if [ $USER_PRIV == "reg" ]
	then
		echo "$(sudo crontab -l 2>/dev/null)" > "${my_homedir}/temp_root_cronfile"
		echo "$(crontab -l 2>/dev/null)" > "${my_homedir}/temp_user_cronfile"
	else
		# if non-interactive root shell
		echo "$(crontab -l 2>/dev/null)" > "${my_homedir}/temp_root_cronfile"
		echo "$(crontab -u ${my_username} -l 2>/dev/null)" > "${my_homedir}/temp_user_cronfile"
	fi

	# declare sources list
	hostfiles_fullpaths_list=(
	# host-specific dirs
	"${my_homedir}/research"
	"${my_homedir}/secure"
	"${my_homedir}/Downloads"
	# global configs
	"/etc"
	"/var/www"
	"/var/log/syslog"
	"${my_homedir}/.ssh/config"
	"${my_homedir}/.config"
	"/usr/lib/node_modules/npm/package.json"
	"/usr/lib/node_modules/eslint/package.json"
	# vscode workspace configs...
	"${my_homedir}/Documents/businesses/tech_business/workspaces"
	"${my_homedir}/bin/workspaces"
	"${my_homedir}/Code/workspaces"
	# git managed source code AND configs...
	"${my_homedir}/bin/utils/audit-list-maker"
	"${my_homedir}/bin/utils/decoder_converter"
	"${my_homedir}/bin/utils/encryption-services"
	"${my_homedir}/bin/utils/file-management-shell-scripts"
	#"${my_homedir}/Documents/businesses/tech_business/coderDojo/coderdojo-projects"
	#"${my_homedir}/Documents/businesses/tech_business/adebayo10k.github.io"
	#"${my_homedir}/Documents/businesses/tech_business/CodingActivityPathChooser"
	"${my_homedir}/.gitconfig"
	#"/cronjob configs..."
	"${my_homedir}/temp_root_cronfile"
	"${my_homedir}/temp_user_cronfile"
	)
	
	echo && echo "Leaving from function ${FUNCNAME[0]}" && echo
	
	
}

##########################################################################################################
# delete existing backups and recreate destination_holding_dir_fullpath
function setup_dst_dir()
{
	echo && echo "Entered into function ${FUNCNAME[0]}" && echo

	echo $destination_holding_dir_fullpath

	if [ -d $destination_holding_dir_fullpath ]
	then	
		rm -rf $destination_holding_dir_fullpath && mkdir $destination_holding_dir_fullpath
	else
		mkdir $destination_holding_dir_fullpath
	fi

	echo && echo "Leaving from function ${FUNCNAME[0]}" && echo
	
	# USER_PRIV (reg or root) branching: TODO: SHOULD BE MODE: INTERACTIVE | NON-INTERACTIVE
	if [ $USER_PRIV == "reg" ]
	then
		echo "NOTICE: Now is a good time to tidy up the ~/Downloads directory. I'll wait here."
		echo "Press ENTER when ready to continue..." && read
	fi
	
}

############################################################################################
# called for each directory in the list
function traverse() {
	date_label=$(date +'%F')
	
	for file in "$1"/*
	do
	    # sanitise copy of file to make it ready for appending as a regular file
		sanitise_relative_path_value "${file}"
		echo "test_line has the value: $test_line"
		rel_filepath=$test_line

		#
		mkdir -p "$(dirname "${destination_holding_dir_fullpath}/${rel_filepath}")"
		
		if [ ! -d "${file}" ] && [ $USER_PRIV == "reg" ]; then
			sudo cp -p "${file}" "${destination_holding_dir_fullpath}/${rel_filepath}.bak.${date_label}"

		elif [ ! -d "${file}" ] && [ $USER_PRIV == "root" ]; then
			cp -p "${file}" "${destination_holding_dir_fullpath}/${rel_filepath}.bak.${date_label}"

	    else # 
			# skip over excluded subdirectories
			# TODO: exlude .git dirs completely. after all, this is a git-independent backup!
			if [[ $file =~ '.config/Code' ]]; then
				echo "Skipping excluded dir: $file"
				continue
			fi
	        echo "entering recursion with: ${file}"
	        traverse "${file}"
	    fi
	done
}

###############################################################################################
function backup_regulars_and_dirs()
{
	echo && echo "Entered into function ${FUNCNAME[0]}" && echo

	setup_source_dirs	# later, this may be from json config
	
	date_label=$(date +'%F')

	# copy sparse sources into dst
	for file in ${hostfiles_fullpaths_list[@]}
	do
		# sanitise file to make it ready for appending
		sanitise_relative_path_value "${file}"
		echo "test_line has the value: $test_line"
		rel_filepath=$test_line
		
		#
		mkdir -p "$(dirname "${destination_holding_dir_fullpath}/${rel_filepath}")"

		# if source directory is not empty...
		if [ -d $file ] && [ "$(ls $file)" ]
		then
			## give user some progress feedback
			echo "Copying dir $file ..." && traverse $file
		elif [ -f $file ] && [ $USER_PRIV == "reg" ]
		then
			# give some user progress feedback
			echo "Copying file $file ..."
			# preserve file metadata during copy
			sudo cp -p $file "${destination_holding_dir_fullpath}/${rel_filepath}.bak.${date_label}"
		elif [ -f $file ] && [ $USER_PRIV == "root" ]
		then
			# give some user progress feedback
			echo "Copying file $file ..."
			# preserve file metadata during copy
			cp -p $file "${destination_holding_dir_fullpath}/${rel_filepath}.bak.${date_label}"
		else
			# failsafe
			echo "Entered the failsafe"
			echo "NO FILE EXISTS on this host for:"
			echo $file && echo
		fi

	done

	# delete those temporary crontab -l output files
	rm -fv "${my_homedir}/temp_root_cronfile" "${my_homedir}/temp_user_cronfile"
	
	echo && echo "Leaving from function ${FUNCNAME[0]}" && echo

}

###############################################################################################
# reduce the privilege level of all backup dir contents.
# why? reg user doesn't need to access them, and we've got sudo tar if needed
# preserving ownership etc. might have more fidelity
function change_file_ownerships()
{
	echo && echo "Entered into function ${FUNCNAME[0]}" && echo

	# USER_PRIV (reg or root) branching:
	if [ $USER_PRIV == "reg" ]
	then
		sudo chown -R ${my_username}:${my_username} "${destination_holding_dir_fullpath}"
	else
		chown -R ${my_username}:${my_username} "${destination_holding_dir_fullpath}"
	fi	
	
	echo && echo "Leaving from function ${FUNCNAME[0]}" && echo
}

###############################################################################################
# if we have an interactive shell, give user a summary of dir sizes in the dst dir
function report_summary()
{
	echo && echo "Entered into function ${FUNCNAME[0]}" && echo

	for file in "${destination_holding_dir_fullpath}"/*
	do
		if [ -d $file ]
		then
			# assuming we're still giving ownership to reg user, else need sudo
			du -h --summarize "$file"
		fi
	done


	echo && echo "Leaving from function ${FUNCNAME[0]}" && echo

}

###############################################################################################
function dummy()
{
	echo && echo "Entered into function ${FUNCNAME[0]}" && echo

	#ssh 5490
	echo -e "\e[32msetup variables\e[0m"
	echo -e "\e[32m\$cp template-script.sh new-script.sh\e[0m"
	echo -e "\033[33mREMEMBER TO .... oh crap!\033[0m" && sleep 4 && echo


	echo && echo "Leaving from function ${FUNCNAME[0]}" && echo

}

###############################################################################################
# this program is allowed to have ... arguments
function verify_and_validate_program_arguments()
{

	echo "USAGE: $(basename $0)"

	# establish that number of params is valid
	if [ $ACTUAL_NO_OF_PROGRAM_PARAMETERS -eq 0 ] || [ $ACTUAL_NO_OF_PROGRAM_PARAMETERS -eq 2 ]
	then
		# if two args put them into an array
		if [ $ACTUAL_NO_OF_PROGRAM_PARAMETERS -eq 2 ]
		then
			#echo "IFS: -$IFS+"
			ALL_THE_PARAMETERS_ARRAY=( $ALL_THE_PARAMETERS_STRING )
			echo "ALL_THE_PARAMETERS_ARRAY[0]: ${ALL_THE_PARAMETERS_ARRAY[0]}"
			echo "ALL_THE_PARAMETERS_ARRAY[1]: ${ALL_THE_PARAMETERS_ARRAY[1]}"
			echo "ALL_THE_PARAMETERS_ARRAY[2]: ${ALL_THE_PARAMETERS_ARRAY[2]}"
			# sanitise_program_args
			sanitise_absolute_path_value "${ALL_THE_PARAMETERS_ARRAY[1]}"
			echo "test_line has the value: $test_line"
			ALL_THE_PARAMETERS_ARRAY[1]=$test_line

			# sanitise my_username
			sanitise_relative_path_value "${ALL_THE_PARAMETERS_ARRAY[0]}"
			echo "test_line has the value: $test_line"
			ALL_THE_PARAMETERS_ARRAY[0]=$test_line
			
			# validate_program_args
		else
			# zero params case
			echo "zero program parameter case ok"
		fi
	else
		echo "Usage: $(basename $0) [<absolute file path>...]+"
		echo "Incorrect number of command line arguments. Exiting now..."		
		exit $E_INCORRECT_NUMBER_OF_ARGS
	fi
	
	# establish how this script was called.
	# assume regular user always calls using symlink in their ~/bin
	if [ $0 = "${HOME}/bin/host-config-backup.sh" ] && [ $ACTUAL_NO_OF_PROGRAM_PARAMETERS -eq 0 ]
	then
		# this script was called by regular user, with zero parameters
		echo "reg"
		my_username="$(id -un)" ## will come from user input
		my_homedir="${HOME}"
		USER_PRIV="reg"
		get_user_inputs #
	elif [ $ACTUAL_NO_OF_PROGRAM_PARAMETERS -eq 2 ] && [ $0 != "${HOME}/bin/host-config-backup.sh" ]
	then
		# script was called during a root cronjob, with two parameters. we ARE root!
		# params tell us which regular users' configuration to deal with
		# assume root cron always calls directly from repository file
		echo "root"
		USER_PRIV="root"
		my_username="${ALL_THE_PARAMETERS_ARRAY[0]}"
		my_homedir="/home/${my_username}"
		destination_holding_dir_fullpath="${ALL_THE_PARAMETERS_ARRAY[1]}"
	else
		# ...
		echo "Usage: $(basename $0) [<absolute file path>...]+"
		echo "Incorrect number of command line arguments. Exiting now..."		
		exit $E_INCORRECT_NUMBER_OF_ARGS
	fi

	echo "${HOME} $(date)" >> "${my_homedir}/crontest.txt" # debug

	echo "OUR CURRENT SHELL LEVEL IS: $SHLVL"
	

}

##########################################################################################################
# entry test to prevent running this program on an inappropriate host
function entry_test()
{
	go=36

	#echo "go was set to: $go"

	for authorised_host in ${authorised_host_list[@]}
	do
		#echo "$authorised_host"
		[ $authorised_host == $ACTUAL_HOST ] && go=0 || go=1
		[ "$go" -eq 0 ] && echo "THE CURRENT HOST IS AUTHORISED TO USE THIS PROGRAM" && break
	done

	# if loop finished with go=1
	[ $go -eq 1 ] && echo "UNAUTHORISED HOST. ABOUT TO EXIT..." && sleep 2 && exit 1


	#echo "go was set to: $go"

}

###############################################################################################
# Display a program header:
function display_program_header(){

	echo
	echo -e "		\033[33m===================================================================\033[0m";
	echo -e "		\033[33m||         Welcome to the host-specific file backuper         ||  author: adebayo10k\033[0m";  
	echo -e "		\033[33m===================================================================\033[0m";
	echo

	# REPORT SOME SCRIPT META-DATA
	echo "The absolute path to this script is:	$0"
	echo "Script root directory set to:		$(dirname $0)"
	echo "Script filename set to:			$(basename $0)" && echo

	echo -e "\033[33mREMEMBER TO RUN THIS PROGRAM ON EVERY HOST!\033[0m" && sleep 2 && echo
		
}

###############################################################################################
# give user option to leave if here in error:
function get_user_permission_to_proceed(){

	echo " Press ENTER to continue or type q to quit."
	echo && sleep 1

	# TODO: if the shell level is -ge 2, called from another script so bypass this exit option
	read last_chance
	case $last_chance in 
	[qQ])	echo
			echo "Goodbye!" && sleep 1
			exit 0
				;;
	*) 		echo "You're IN..." && echo && sleep 1
				;;
	esac 
}

###############################################################################################

main "$@"; exit
