#!/bin/bash
#: Title		:host-config-backup.sh
#: Date			:2021-02-06
#: Author		:"Damola Adebayo"
#: Version		:1.0
#: Description	:use to create backup copy (ie one-way) of various system-specific files
#: Description	:such as configuration files that aren't covered by my routine backups
#: Description	:of the working directories. files are --update copied to external device if
#: Description	:possible, else to a local synchronised directory.
#: Options		:None


###############################################################################################
# This program is concerned only with files that I do not routinely synchronise,
# plus those frequently mutating files, \
# plus those files that are DIFFERENT on each host, \
# plus those files that are not accessible by regular user permissions. \
# For example:
	# configuration files
	# HOME, Downloads... dirs

# This program only needs to try to run say, once every day, as these configuration and 
# host-specific files change less frequently.

# This program is only concerned with getting current copies of these files onto external drive, or \
# into sync-ready position on respective hosts. That's it. CRON makes this happen daily.

# The program branches based on whether interactive shell or batch-mode.

# on bash:
# m h  dom mon dow   command
# 30 12,16 * * * * /usr/bin/time -a -o "/home/dir/hcf-log" /path/to/git/repo/host-config-backup.sh

# Needs to run as root to get access to those global configuration files,
# then adjust file ownership or not?

# To add a new file path to this program, we just add it to the json configuration file.

# NOTE: new cp --update strategy assumes that existing source files get modified (or not), but don't get deleted.
# ...so need a way to get rid of last CURRENT backup of a deleted file.

# host authorisation is moot because configuration file specifies host-specific configuration parameters 

# NOTE: jq does not handle hyphenated filter argument quoting and faffing. Think I read something about that
# in the docs. Better to just use camelCased JSON property names universally.
###############################################################################################

##################################################################
##################################################################
# THIS STUFF IS HAPPENING BEFORE MAIN FUNCTION CALL:
#===================================

# 1. MAKE SHARED LIBRARY FUNCTIONS AVAILABLE HERE

# make all the shared library functions available to this script
shared_bash_functions_fullpath="${SHARED_LIBRARIES_DIR}/shared-bash-functions.inc.sh"
shared_bash_constants_fullpath="${SHARED_LIBRARIES_DIR}/shared-bash-constants.inc.sh"

for resource in "$shared_bash_functions_fullpath" "$shared_bash_constants_fullpath"
do
	if [ -f "$resource" ]
	then
		echo "Required library resource FOUND OK at:"
		echo "$resource"
		source "$resource"
	else
		echo "Could not find the required resource at:"
		echo "$resource"
		echo "Check that location. Nothing to do now, except exit."
		exit 1
	fi
done


# 2. MAKE SCRIPT-SPECIFIC FUNCTIONS AVAILABLE HERE

# must resolve canonical_fullpath here, in order to be able to include sourced function files BEFORE we call main, and  outside of any other functions defined here, of course.

# at runtime, command_fullpath may be either a symlink file or actual target source file
command_fullpath="$0"
command_dirname="$(dirname $0)"
command_basename="$(basename $0)"

# if a symlink file, then we need a reference to the canonical file name, as that's the location where all our required source files will be.
# we'll test whether a symlink, then use readlink -f or realpath -e although those commands return canonical file whether symlink or not.
# 
canonical_fullpath="$(readlink -f $command_fullpath)"
canonical_dirname="$(dirname $canonical_fullpath)"

# this is just development debug information
if [ -h "$command_fullpath" ]
then
	echo "is symlink"
	echo "canonical_fullpath : $canonical_fullpath"
else
	echo "is canonical"
	echo "canonical_fullpath : $canonical_fullpath"
fi

# included source files for json profile import functions
#source "${canonical_dirname}/preset-profile-builder.inc.sh"


# THAT STUFF JUST HAPPENED (EXECUTED) BEFORE MAIN FUNCTION CALL!
##################################################################
##################################################################


function main 
{
	#######################################################################
	# GLOBAL VARIABLE DECLARATIONS:
	#######################################################################

	actual_host=$(hostname)
	unset authorised_host_list
	declare -a authorised_host_list=($HOST_0065 $HOST_0054 $HOST_R001 $HOST_R002)  # allow | deny
	if [[ $(declare -a | grep 'authorised_host_list' 2>/dev/null) ]]
	then
		entry_test
	fi

	declare -r PROGRAM_PARAM_1=${1:-"not_yet_set"} ## 

	declare -i max_expected_no_of_program_parameters=1
	declare -i min_expected_no_of_program_parameters=0
	declare -ir actual_no_of_program_parameters=$#
	all_the_parameters_string="$@"

	CONFIG_FILE_FULLPATH=

	program_title=""
	original_author=""
	program_dependencies=(jq vi)

	# declare the backup scheme for which this backup program is designed
	declare -r BACKUP_SCHEME_TYPE="host_configuration_file_backups"
	# declare the constant identifying the current host
	declare -r THIS_HOST="$(hostname)"

	declare -a EXTERNAL_DRV_DATA_ARRAY=()
	declare -a LOCAL_DRV_DATA_ARRAY=()
	declare -a NETWORK_DRV_DATA_ARRAY=()
		
	dst_dir_current_fullpath= # the first destination backup directory that this program finds to be accessible ok

	BACKUP_DESCRIPTION=
	REGULAR_USER=
	REGULAR_USER_HOME_DIR=
	declare -a SRC_FILES_FULLPATHS_LIST=()
	declare -a EXCLUDED_FILE_PATTERN_LIST=()
	LOG_FILE=

	test_line="" # global...
	
	
	###############################################################################################

	# establish the script RUN_MODE using whoami command.
	if [ "$(whoami)" == "root" ]
	then
		declare -r RUN_MODE="batch"
		#make_root_safe by making
	else
		declare -r RUN_MODE="interactive"
	fi

	# count program positional parameters
	check_no_of_program_args

	# check program dependencies and requirements
	check_program_requirements "${program_dependencies[@]}"

	if [ "$SHLVL" -le 3 ]
	then
		# Display a descriptive and informational program header:
		display_program_header

		# give user option to leave if here in error:
		if [ "$RUN_MODE" == "interactive" ]
		then
			get_user_permission_to_proceed
		fi
	fi

	# cleanup and validate, test program positional parameters
  cleanup_and_validate_program_arguments
	
	
	###############################################################################################
	# PROGRAM-SPECIFIC FUNCTION CALLS:	
	###############################################################################################

	if [ -n "$CONFIG_FILE_FULLPATH" ] # should have been received as a validated program argument
	then
		echo "the config is REAL"
		# TODO: open/display_current_config_file to user (if run mode is interactive) for editing option?
		import_json
	else
		msg="NO CONFIG FOR YOU. Exiting now..."
		lib10k_exit_with_error "$E_REQUIRED_FILE_NOT_FOUND" "$msg" 	

	fi
	
	setup_dst_dir

	create_last_minute_src_files

	backup_regulars_and_dirs

	change_file_ownerships

	report_summary
	

} ## end main




###############################################################################################
####  FUNCTION DECLARATIONS  
###############################################################################################

function import_json() 
{
	#
	######## FOR THE SPECIFIC HOST WE'RE ON...

	EXTERNAL_DRV_DATA_STRING=$(cat "$CONFIG_FILE_FULLPATH" | jq -r --arg THIS_HOST "$THIS_HOST" '.hosts[] | select(.hostname==$THIS_HOST) | .dstBackupDirSet[] | select(.location=="external_drive") | .[]') 

	echo "EXTERNAL_DRV_DATA_STRING: $EXTERNAL_DRV_DATA_STRING"
	echo && echo

	# note: the sequence of data in these arrays has been designed to suit the order in which we'll soon process them in setup_dst_dir().
	## 	# TODO: generalise TODO: cleanup_and_validate_program_arguments
	EXTERNAL_DRV_DATA_ARRAY=( $EXTERNAL_DRV_DATA_STRING )

	echo "${EXTERNAL_DRV_DATA_ARRAY[@]}"
	echo && echo

	LOCAL_DRV_DATA_STRING=$(cat "$CONFIG_FILE_FULLPATH" | jq -r --arg THIS_HOST "$THIS_HOST" '.hosts[] | select(.hostname==$THIS_HOST) | .dstBackupDirSet[] | select(.location=="local_drive") | .[]') 

	echo "LOCAL_DRV_DATA_STRING: $LOCAL_DRV_DATA_STRING"
	echo && echo

	LOCAL_DRV_DATA_ARRAY=( $LOCAL_DRV_DATA_STRING )
	
	echo "${LOCAL_DRV_DATA_ARRAY[@]}"
	echo && echo

	NETWORK_DRV_DATA_STRING=$(cat "$CONFIG_FILE_FULLPATH" | jq -r --arg THIS_HOST "$THIS_HOST" '.hosts[] | select(.hostname==$THIS_HOST) | .dstBackupDirSet[] | select(.location=="network_drive") | .[]') 

	echo "NETWORK_DRV_DATA_STRING: $NETWORK_DRV_DATA_STRING"
	echo && echo

	NETWORK_DRV_DATA_ARRAY=( $NETWORK_DRV_DATA_STRING )

	echo "${NETWORK_DRV_DATA_ARRAY[@]}"
	echo && echo

	
	######## THE TYPE OF BACKUP WE'RE DOING...
	######## FIRST... ASSIGNING THE JSON ARRAY DATA TO CORRESPONDING BASH ARRAY DATA STRUCTURES...


	SRC_FILES_FULLPATHS_STRING=$(cat "$CONFIG_FILE_FULLPATH" | jq -r --arg BACKUP_SCHEME_TYPE "$BACKUP_SCHEME_TYPE" '.backupSchemes[] | select(.backupType==$BACKUP_SCHEME_TYPE) | .srcFilesFullpaths[]')

	echo $SRC_FILES_FULLPATHS_STRING

	SRC_FILES_FULLPATHS_LIST=( $SRC_FILES_FULLPATHS_STRING ) # input sanitation done later in backup_regulars_and_dirs()
	echo && echo "###########" && echo

	########

	#-j option doesn't print newline after each output - so we can pattern match single string
	EXCLUDED_FILE_PATTERN_STRING=$(cat "$CONFIG_FILE_FULLPATH" | jq -j --arg BACKUP_SCHEME_TYPE "$BACKUP_SCHEME_TYPE" '.backupSchemes[] | select(.backupType==$BACKUP_SCHEME_TYPE) | .excludedFilePatterns[]')

	# remove spaces to match a single pattern
	#EXCLUDED_FILE_PATTERN_STRING=$(echo "$EXCLUDED_FILE_PATTERN_STRING" | sed 's/[[:space:]]//g')

	echo "$EXCLUDED_FILE_PATTERN_STRING"

	EXCLUDED_FILE_PATTERN_LIST=( $EXCLUDED_FILE_PATTERN_STRING ) # this array may not be needed
	# TODO: cleanup_and_validate_program_arguments
	echo && echo "###########" && echo


	######## THE TYPE OF BACKUP WE'RE DOING...
	######## NEXT... ASSIGNING THE JSON VALUES DATA TO CORRESPONDING BASH SCALAR VARIABLES...



	BACKUP_DESCRIPTION=$(cat "$CONFIG_FILE_FULLPATH" | jq -r --arg BACKUP_SCHEME_TYPE "$BACKUP_SCHEME_TYPE" '.backupSchemes[] | select(.backupType==$BACKUP_SCHEME_TYPE) | .backupDescription')

	# TODO: cleanup_and_validate_program_arguments
	echo $BACKUP_DESCRIPTION
	echo && echo "###########" && echo

	########

	REGULAR_USER=$(cat "$CONFIG_FILE_FULLPATH" | jq -r --arg BACKUP_SCHEME_TYPE "$BACKUP_SCHEME_TYPE" '.backupSchemes[] | select(.backupType==$BACKUP_SCHEME_TYPE) | .regularUser')

	# TODO: cleanup_and_validate_program_arguments
	echo $REGULAR_USER
	echo && echo "###########" && echo

	########

	REGULAR_USER_HOME_DIR=$(cat "$CONFIG_FILE_FULLPATH" | jq -r --arg BACKUP_SCHEME_TYPE "$BACKUP_SCHEME_TYPE" '.backupSchemes[] | select(.backupType==$BACKUP_SCHEME_TYPE) | .regularUserHomeDir')

	# TODO: cleanup_and_validate_program_arguments
	echo $REGULAR_USER_HOME_DIR
	echo && echo "###########" && echo

	########

	LOG_FILE=$(cat "$CONFIG_FILE_FULLPATH" | jq -r --arg BACKUP_SCHEME_TYPE "$BACKUP_SCHEME_TYPE" '.backupSchemes[] | select(.backupType==$BACKUP_SCHEME_TYPE) | .logFile')

	# TODO: generalise TODO: cleanup_and_validate_program_arguments
	echo $LOG_FILE
	echo && echo "###########" && echo

	########


	# NOW THAT WE'VE SET LOG_FILE, WE CAN START TEEING PROGRAM OUTPUTS THERE...

	touch "$LOG_FILE" && chown ${REGULAR_USER}:${REGULAR_USER} "${LOG_FILE}"
	echo "$(date)" > "$LOG_FILE"
	echo "THIS_HOST: $THIS_HOST" >> "$LOG_FILE" # debug
	#echo "ALL_THE_PARAMETERS_STRING: $ALL_THE_PARAMETERS_STRING" >> "$LOG_FILE" # debug
	#echo "PROGRAM_PARAM_1: $PROGRAM_PARAM_1" >> "$LOG_FILE" # debug	
	#echo "program:" && echo "$0" && exit 0 # debug
	#output=$(dummy 2)
	#echo $output && exit 0 # debug
	echo >> "$LOG_FILE"
	echo "Program being run by user: $(whoami)" >> "$LOG_FILE"
	echo "Current working directory: $(pwd)" >> "$LOG_FILE"
	echo "RUN_MODE: $RUN_MODE" >> "$LOG_FILE" # debug

	echo >> "$LOG_FILE"

}

###############################################################################################


###############################################################################################
# this program is allowed to have ... arguments
function cleanup_and_validate_program_arguments()
{	
	# only the regular user can call using zero parameters as in an interactive shell
	# the root user is non-interactive, so must provide exactly one parameter
	if [ "$actual_no_of_program_parameters" -eq 1 ]
	then			
		# sanitise_program_args
		#sanitise_absolute_path_value "$PROGRAM_PARAM_1"
		#echo "test_line has the value: $test_line"

		make_abs_pathname "$PROGRAM_PARAM_1"
		echo "test_line has the value: $test_line"
		
		PROGRAM_PARAM_TRIMMED=$test_line
		validate_absolute_path_value "$PROGRAM_PARAM_TRIMMED"			
			
	elif [ "$actual_no_of_program_parameters" -eq 0 ] && [ "$RUN_MODE" == "batch" ]
	then
		msg="Incorrect number of command line arguments. Exiting now..."
		lib10k_exit_with_error "$E_INCORRECT_NUMBER_OF_ARGS" "$msg"

	elif [ "$actual_no_of_program_parameters" -eq 0 ] && [ "$RUN_MODE" == "interactive" ]
	then
		# this script was called by regular user, with zero parameters		
		get_path_to_config_file # get path to the configuration file from user
	
	else
		# ...failsafe case
		msg="Incorrect number of command line arguments. Exiting now..."
		lib10k_exit_with_error "$E_UNEXPECTED_BRANCH_ENTERED" "$msg"
	fi
	

}

###############################################################################################
# here because we're a logged in, regular user with interactive shell
# we're here to provide the absolute path to a backup configuration file
function get_path_to_config_file()
{
	echo "Looks like you forgot to add the configuration file as a program argument..." && echo && sleep 1

	echo "Please enter it now to continue using this program" && echo && sleep 1

	echo "Enter (copy-paste) the absolute path to the backup configuration file:" && echo

	#
	find /home -type f -name "*backup-configs.json" && echo 

	echo && echo
	read path_to_config_file

	if [ -n "$path_to_config_file" ] 
	then
		#sanitise_absolute_path_value "$path_to_config_file"
		#echo "test_line has the value: $test_line"

		make_abs_pathname "$path_to_config_file"
		echo "test_line has the value: $test_line"
		
		path_to_config_file=$test_line

		validate_absolute_path_value "$path_to_config_file"		

	else
		# 
		msg="User entered a zero length argument for the configuration file. Exiting now..."
		lib10k_exit_with_error "$E_UNEXPECTED_ARG_VALUE" "$msg"
	fi
}
###############################################################################################
function validate_absolute_path_value()
{
	#echo && echo "Entered into function ${FUNCNAME[0]}" && echo

	test_filepath="$1"

	# this valid form test works for sanitised file paths
	test_file_path_valid_form "$test_filepath"
	return_code=$?
	if [ "$return_code" -eq 0 ]
	then
		echo "The configuration filename is of VALID FORM"
	else
		msg="The valid form test FAILED and returned: $return_code. Exiting now..."
		lib10k_exit_with_error "$E_UNEXPECTED_ARG_VALUE" "$msg"
	fi

	# if the above test returns ok, ...
	test_file_path_access "$test_filepath"
	return_code=$?
	if [ "$return_code" -eq 0 ]
	then
		#echo "The configuration file is ACCESSIBLE OK"
		CONFIG_FILE_FULLPATH="$test_filepath"

	else
		msg="The configuration filepath ACCESS TEST FAILED and returned: $return_code. Exiting now..."
		lib10k_exit_with_error "$E_FILE_NOT_ACCESSIBLE" "$msg"
	fi


	#echo && echo "Leaving from function ${FUNCNAME[0]}" && echo

}

##########################################################################################################
# write those files we'd like to backup...
# do this until there's a better way of including them in the src_files configuration
function create_last_minute_src_files()
{
	#echo && echo "Entered into function ${FUNCNAME[0]}" | tee -a $LOG_FILE && echo | tee -a $LOG_FILE

	# # write roots' crontab into a file that we can backup
	if [ "$RUN_MODE" == "interactive" ] # if interactive shell
	then
		echo "$(sudo crontab -u root -l 2>/dev/null)" > "${REGULAR_USER_HOME_DIR}/temp_root_cronfile"
	elif [ "$RUN_MODE" == "batch" ] # if non-interactive root shell
	then		
		echo "$(crontab -lu root 2>/dev/null)" > "${REGULAR_USER_HOME_DIR}/temp_root_cronfile"
	else
		# unexpected value for RUN_MODE, so get out now
		msg="UNKNOWN RUN MODE. Exiting now..."
		lib10k_exit_with_error "$E_UNKNOWN_RUN_MODE" "$msg"
	fi

	# write regular users' crontab into a file that we can backup
	echo "$(crontab -u ${REGULAR_USER} -l 2>/dev/null)" > "${REGULAR_USER_HOME_DIR}/temp_user_cronfile"

	#echo && echo "Leaving from function ${FUNCNAME[0]}" | tee -a $LOG_FILE && echo | tee -a $LOG_FILE	
}

##########################################################################################################
# establish whether we're able to backup our src files to configured drives, in order of preference:
function setup_dst_dir()
{
	#echo && echo "Entered into function ${FUNCNAME[0]}" | tee -a $LOG_FILE && echo | tee -a $LOG_FILE
	echo >> "$LOG_FILE"

	# establish whether external drive/network fs/remote fs is mounted
	# iterate over paths/to/backups, testing whether their associated mountpoints are available
	# if so, add path to the mountpoint_mounted_ok_dst_dirs array. We'll try to setup only these ones.
	# for now, we'll NOT attempt to mount if not yet mounted.

	#echo "NETWORK_DRV_DATA_ARRAY has ${#NETWORK_DRV_DATA_ARRAY[@]} elements" | tee -a $LOG_FILE #debug

	declare -a mountpoint_mounted_ok_dst_dirs=() # dir paths whose filesystems are actually mounted at the moment	

	NO_OF_BACKUP_DRIVES=3
	NO_OF_PROPERTIES_PER_DRIVE=3
	MAX_NO_OF_PROPERTIES_TO_CHECK=$((NO_OF_BACKUP_DRIVES * NO_OF_PROPERTIES_PER_DRIVE))
	# aka maximum number of loops to do. ensures this number is exceeded, and we break out of loop, when drives with incomplete data immediately increment count by NO_OF_PROPERTIES_PER_DRIVE in order to move the loop onto the next drive.
	echo "MAX_NO_OF_PROPERTIES_TO_CHECK: $MAX_NO_OF_PROPERTIES_TO_CHECK" | tee -a $LOG_FILE && echo | tee -a $LOG_FILE  #debug

	TOTAL_NUMBER_OF_ARRAY_ELEMENTS=$(( ${#EXTERNAL_DRV_DATA_ARRAY[@]} + ${#LOCAL_DRV_DATA_ARRAY[@]} + ${#NETWORK_DRV_DATA_ARRAY[@]} ))  #debug
	echo "TOTAL_NUMBER_OF_ARRAY_ELEMENTS: $TOTAL_NUMBER_OF_ARRAY_ELEMENTS" | tee -a $LOG_FILE && echo | tee -a $LOG_FILE #debug

	#intialise some variables:
	switch=1 # off
	# TODO: also try this with a nested for-loop
	for ((count=0; count<$MAX_NO_OF_PROPERTIES_TO_CHECK; count++));
	do		
		# expecting NO_OF_PROPERTIES_PER_DRIVE elements in each of the arrays
		mod=$((count % $NO_OF_PROPERTIES_PER_DRIVE))
		div=$((count / $NO_OF_PROPERTIES_PER_DRIVE))

		# in specific order of backup preference...
		# if more arrays (drives) are added, count and div will increase, so add new parent case blocks.
		case $div in 
		0)	case $mod in
			0) 	# if array has less than NO_OF_PROPERTIES_PER_DRIVE elements, \
				# ie - json configuration data is incomplete for this drive...
				if [ "${#EXTERNAL_DRV_DATA_ARRAY[@]}" -lt "$NO_OF_PROPERTIES_PER_DRIVE" ]
				then
					# ...then, echo message about this
					echo "Configuration data was incomplete for \"${EXTERNAL_DRV_DATA_ARRAY[${mod}]:-'external_drive'}\". Skipping drive setup..." | tee -a $LOG_FILE && echo | tee -a $LOG_FILE
					# skip to next drive by setting count = count + no_of_properties_to_skip;
					no_of_properties_to_skip=$((NO_OF_PROPERTIES_PER_DRIVE - 1)) # 
					count=$((count + no_of_properties_to_skip))
				else
					echo "Checking the mount state for: \"${EXTERNAL_DRV_DATA_ARRAY[${mod}]}\" ..." | tee -a $LOG_FILE
				fi
								
				;;
			1) 	if ! mountpoint -q "${EXTERNAL_DRV_DATA_ARRAY[${mod}]}" 2>/dev/null
				then
					# associated backup destination definitely won't be available
					# also handles cases where mountpoint value is empty | no such directory
					echo "\"${EXTERNAL_DRV_DATA_ARRAY[0]}\" is NOT AVAILABLE." | tee -a $LOG_FILE && echo | tee -a $LOG_FILE
					# set a switch for the next loop, where $mod == 2
					switch=1 # (off)
				else
					# positively set the switch to 0 (on)
					echo "mountpoint for \"${EXTERNAL_DRV_DATA_ARRAY[0]}\" is REGISTERED OK." | tee -a $LOG_FILE && echo | tee -a $LOG_FILE
					switch=0
				fi
				;;
			2)	if [ "$switch" -eq 0 ]
				then
					# append mountpoint_mounted_ok_dst_dirs array with backup directory path
					mountpoint_mounted_ok_dst_dirs+=( "${EXTERNAL_DRV_DATA_ARRAY[${mod}]}" )
					# reset the switch to off
					switch=1
				fi
				;;
			esac
			
			;;				
		1)	case $mod in
			0) 	if [ "${#LOCAL_DRV_DATA_ARRAY[@]}" -lt "$NO_OF_PROPERTIES_PER_DRIVE" ]
				then
					echo "Configuration data was incomplete for \"${LOCAL_DRV_DATA_ARRAY[${mod}]:-'local_drive'}\". Skipping drive setup..." | tee -a $LOG_FILE && echo | tee -a $LOG_FILE
					no_of_properties_to_skip=$((NO_OF_PROPERTIES_PER_DRIVE - 1)) # 
					count=$((count + no_of_properties_to_skip))
				else
					echo "Checking the mount state for: \"${LOCAL_DRV_DATA_ARRAY[${mod}]}\" ..." | tee -a $LOG_FILE
				fi
				;;
			1) 	if ! mountpoint -q "${LOCAL_DRV_DATA_ARRAY[${mod}]}" 2>/dev/null
				then					
					echo "\"${LOCAL_DRV_DATA_ARRAY[0]}\" is NOT AVAILABLE." | tee -a $LOG_FILE && echo | tee -a $LOG_FILE
					switch=1
				else
					echo "mountpoint for \"${LOCAL_DRV_DATA_ARRAY[0]}\" is REGISTERED OK." | tee -a $LOG_FILE && echo | tee -a $LOG_FILE
					switch=0
				fi
				;;
			2)	if [ "$switch" -eq 0 ]
				then
					mountpoint_mounted_ok_dst_dirs+=( "${LOCAL_DRV_DATA_ARRAY[${mod}]}" )
					switch=1
				fi
				;;
			esac
			
			;;
		2)	case $mod in
			0) 	if [ "${#NETWORK_DRV_DATA_ARRAY[@]}" -lt "$NO_OF_PROPERTIES_PER_DRIVE" ]
				then
					echo "Configuration data was incomplete for \"${NETWORK_DRV_DATA_ARRAY[${mod}]:-'network_drive'}\". Skipping drive setup..." | tee -a $LOG_FILE && echo | tee -a $LOG_FILE
					no_of_properties_to_skip=$((NO_OF_PROPERTIES_PER_DRIVE - 1)) # 
					count=$((count + no_of_properties_to_skip))
				else
					echo "Checking the mount state for: \"${NETWORK_DRV_DATA_ARRAY[${mod}]}\" ..." | tee -a $LOG_FILE
				fi
				;;
			1) 	if ! mountpoint -q "${NETWORK_DRV_DATA_ARRAY[${mod}]}" 2>/dev/null
				then
					echo "\"${NETWORK_DRV_DATA_ARRAY[0]:-'network_drive'}\" is NOT AVAILABLE." | tee -a $LOG_FILE && echo | tee -a $LOG_FILE
					switch=1
				else
					echo "mountpoint for \"${NETWORK_DRV_DATA_ARRAY[0]:-'network_drive'}\" is REGISTERED OK." | tee -a $LOG_FILE && echo | tee -a $LOG_FILE
					switch=0
				fi
				;;
			2)	if [ "$switch" -eq 0 ]
				then
					mountpoint_mounted_ok_dst_dirs+=( "${NETWORK_DRV_DATA_ARRAY[${mod}]}" )
					switch=1
				fi
				;;
			esac
			
			;;
		*) 	msg="for-loop in setup_dst_dir() in OUT OF BOUNDS ITERATION. Exiting now..."
			lib10k_exit_with_error "$E_OUT_OF_BOUNDS_BRANCH_ENTERED" "$msg"
		 	
			;;
    	esac  

	done


	echo "DST_DIRS WITH GOOD MOUNTPOINT(S): ${mountpoint_mounted_ok_dst_dirs[@]}" | tee -a $LOG_FILE
	echo "HOW MANY DST_DIRS WITH GOOD MOUNTPOINT(S): ${#mountpoint_mounted_ok_dst_dirs[@]}" | tee -a $LOG_FILE

	echo >> "$LOG_FILE"

	# now we know which dst dirs are at least on drives that are currently mounted,
	# we can further check that they're accessible and try to assign them to the dst_dir_current_fullpath variable,
	# trying them one after the other, first winner takes it
	setup_outcome=42 #initialise to fail state (!= 0)

	for dst_dir in "${mountpoint_mounted_ok_dst_dirs[@]}"
	do
		echo "Now trying to find and access the dst dir: $dst_dir" | tee -a $LOG_FILE
		echo >> "$LOG_FILE"

		# test dst_dir exists and accessible
		test_dir_path_access "$dst_dir"
		return_code=$?
		if [ "$return_code" -eq 0 ]
		then
			# dst_dir found and accessible ok
			echo "That dst_dir filepath EXISTS and WORKS OK" | tee -a $LOG_FILE && echo | tee -a $LOG_FILE
			dst_dir_current_fullpath="$dst_dir"
			setup_outcome=0 #success
			break

		elif [ "$return_code" -eq "$E_REQUIRED_FILE_NOT_FOUND" ]
		then
			# dst_dir did not exist
			echo "That dst HOLDING (PARENT) DIRECTORY WAS NOT FOUND. test returned: $return_code"
			
			mkdir "$dst_dir" >/dev/null >&1 && echo "Creating the directory now..." | tee -a $LOG_FILE && echo && \
			dst_dir_current_fullpath="$dst_dir" && setup_outcome=0 && break \
			|| setup_outcome=1 && echo "Directory creation failed for:" | tee -a $LOG_FILE && echo "$dst_dir" && echo && continue			

		else
			# dst_dir found but not accessible
			# stopping execution mid-loop because this should NEVER happen on my own system
			msg="WEIRD, SO LET'S STOP. The dst DIRECTORY filepath ACCESS TEST FAILED and returned: $return_code. Exiting now..."
			lib10k_exit_with_error "$E_FILE_NOT_ACCESSIBLE" "$msg"
		fi

	done

	if [ "$setup_outcome" -ne 0 ]
	then
		# failsafe...
		# couldn't mkdirs, no dirs to make or just something else not good...
		msg="Unexpected, UNKNOWN ERROR setting up the dst dir... Exiting now..."
		lib10k_exit_with_error "$E_UNKNOWN_ERROR" "$msg"
	fi
			
	#echo && echo "Leaving from function ${FUNCNAME[0]}" | tee -a $LOG_FILE && echo

}

############################################################################################
# called for each directory in the list
function traverse() {
	#date_label=$(date +'%F')
	
	for file in "$1"/* # could have used ls "$1"
	do
	    # sanitise copy of file to make it ready for appending as a regular file
		#sanitise_trim_relative_path "${file}"

		make_rel_pathname  "${file}"
		echo "test_line has the value: $test_line"

		rel_filepath=$test_line

		# only happens with the first subdir (TODO: test this with a debug echo!)
		mkdir -p "$(dirname "${dst_dir_current_fullpath}/${rel_filepath}")"
		
		# how does the order of these tests affect performance?
		if  [ -f "${file}" ]  && [ ! -h "${file}" ] && [ "$RUN_MODE" == "interactive" ]; then
			# preserve file metadata, never follow symlinks, update copy if necessary
			# give some user progress feedback
			#echo "Copying file $file ..."
			sudo cp -uvPp "${file}" "${dst_dir_current_fullpath}/${rel_filepath}"

		elif [ -f "${file}" ] && [ ! -h "${file}" ] && [ "$RUN_MODE" == "batch" ]; then
			#echo "Copying file $file ..."
			cp -uvPp "${file}" "${dst_dir_current_fullpath}/${rel_filepath}"

		# if  file is a symlink, reject (irrespective of RUN_MODE)
		elif [ -h "${file}" ]; then
			#echo "Skipping symlink file: $file ..."
			continue 

	    elif [ -d "${file}" ]; then # file must be a directory to have arrived at this branch, but check anyway.
			# skip over excluded subdirectories
			# TODO: exlude .git dirs completely. after all, this is a git-independent backup!
			if  [ -z "$(ls -A $file)" ] || [[ "$EXCLUDED_FILE_PATTERN_STRING" =~ "$file" ]]
			then
				#echo "Skipping excluded dir: $file" | tee -a $LOG_FILE && echo
				continue
			fi
			# enter recursion with a non-empty directory
	        #echo "entering recursion with: ${file}"
	        traverse "${file}"
		else
			# failsafe condition
			echo "FAILSAFE BRANCH ENTERED!! WE SHOULD NOT BE HERE!!"
			echo "WEIRD FILE EXISTS on this host for:"
			echo $file && echo
	    fi
	done
}

###############################################################################################
function backup_regulars_and_dirs()
{
	#echo && echo "Entered into function ${FUNCNAME[0]}" | tee -a $LOG_FILE && echo

	# 
	if [ "$RUN_MODE" == "interactive" ]
	then
		echo "Now is a good time to tidy up the ~/Downloads directory. I'll wait here." && echo
		echo "Press ENTER when ready to continue..." && read
	fi

	#date_label=$(date +'%F')

	# copy sparse sources into $dst_dir_current_fullpath
	for file in ${SRC_FILES_FULLPATHS_LIST[@]}
	do
		# sanitise filepath to make it ready for appending to dst_dir_current_fullpath
		#sanitise_trim_relative_path "${file}"

		make_rel_pathname  "${file}"
		echo "test_line has the value: $test_line"

		#echo "test_line has the value: $test_line"
		rel_filepath=$test_line

		# only happens with the first subdir (TODO: test this with a debug echo!)
		mkdir -p "$(dirname "${dst_dir_current_fullpath}/${rel_filepath}")"

		# if source directory is not empty...
		if [ -d $file ] && [ -n "$(ls -A $file)" ]
		then
			## give user some progress feedback
			echo "Copying dir $file ..." && traverse $file
		elif [ -f $file ] && [ "$RUN_MODE" == "interactive" ] && [ ! -h "${file}" ]
		then
			# give some user progress feedback
			echo "Copying top level file $file ..."
			# preserve file metadata, never follow symlinks, update copy if necessary
			sudo cp -uvPp $file "${dst_dir_current_fullpath}/${rel_filepath}"
		elif [ -f $file ] && [ "$RUN_MODE" == "batch" ] && [ ! -h "${file}" ]
		then
			# give some user progress feedback
			echo "Copying top level file $file ..."
			cp -uvPp $file "${dst_dir_current_fullpath}/${rel_filepath}"
		elif  [ -h "${file}" ]
		then
			echo "Skipping symbolic link in srcFilesFullpaths list..."
			continue
		else
			# failsafe
			echo "Entered the failsafe"
			echo "WEIRD, NO SUCH FILE EXISTS on this host for:"
			echo $file && echo
		fi

	done

	# delete those temporary crontab -l output files
	rm -fv "${REGULAR_USER_HOME_DIR}/temp_root_cronfile" "${REGULAR_USER_HOME_DIR}/temp_user_cronfile"
	
	#echo && echo "Leaving from function ${FUNCNAME[0]}" | tee -a $LOG_FILE && echo

}

###############################################################################################
# chown (but not chmod) privilege level of all backup dir contents.
# why? reg user doesn't need to access them, and we've got sudo tar if needed to prevent inadvertent linking/referencing. .
# preserving ownership etc. might also have more fidelity, and enable any restore operations.
function change_file_ownerships()
{
	#echo && echo "Entered into function ${FUNCNAME[0]}" | tee -a $LOG_FILE && echo && echo

	if [ "$RUN_MODE" == "interactive" ]
	then
		sudo chown -R ${REGULAR_USER}:${REGULAR_USER} "${dst_dir_current_fullpath}"
	else
		chown -R ${REGULAR_USER}:${REGULAR_USER} "${dst_dir_current_fullpath}"
	fi	
	
	#echo && echo "Leaving from function ${FUNCNAME[0]}" && echo
}

###############################################################################################
# if we have an interactive shell, give user a summary of dir sizes in the dst dir
function report_summary()
{
	#echo && echo "Entered into function ${FUNCNAME[0]}" | tee -a $LOG_FILE && echo && echo

	for file in "${dst_dir_current_fullpath}"/*
	do
		if [ -d "$file" ]
		then
			# assuming we're still giving ownership to reg user, else need sudo
			du -h --summarize "$file"
		fi
	done

	#echo && echo "Leaving from function ${FUNCNAME[0]}" | tee -a $LOG_FILE && echo && echo
}

###############################################################################################


main "$@"; exit
