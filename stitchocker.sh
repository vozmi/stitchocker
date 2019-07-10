#!/bin/bash

################################################################################################
#                                  Stitchoker Interface                                        #
#                                                                                              #
# $self  $path_flag  $path  $command  $first_flag  $second_flag  $flags                        #
#        $1          $2     $3        $4           $5            ${@:4}                        #
# scr    -p          path   up        -d           backend       eg. stacks (basic front back) #
################################################################################################

function scr
{
	local fn="stitchocker"
	local version="0.0.6"
	local version_info="Stitchocker version $version"
	local help="
	Usage:
		$fn [-a <arg>...] [alias] [docker-compose COMMAND] [SETS...]
		$fn [docker-compose COMMAND] [SETS...]
		$fn -h|--help
		$fn -v|--version

	Options:
		-h|--help            Shows this help text
		-v|--version         Shows $fn version
		--update             Updates $fn to the latest stable version
		-p                   Path to stitching directory
		-a                   Alias to stitching directory
		
	Examples:
		$fn up
		$fn up default backend frontend
		$fn -a my-projects-alias-from-env up default backend frontend
	"

	local debug=$(scr_env stitchocker_debug)
	if [[ ! -z $debug && $debug == true ]]; then
		debug=true
	else
		debug=false
	fi

	local self="scr"
	local path_flag="-p"
	local exec="$self $path_flag"

	if [ $# -lt 1 ]; then
		echo "$help"
		exit 1
	fi

    # Entrypoint
	case $1 in
		# --------------------------------------------------------------
		# Help info
		# --------------------------------------------------------------
		"-h" | "--help")
			echo "$help"
			exit 0
		;;
		# --------------------------------------------------------------
		# Version info
		# --------------------------------------------------------------
		"-v" | "--version")
			echo "$version_info"
			exit 0
		;;
		# --------------------------------------------------------------
		# Updates to the latest stable version
		# --------------------------------------------------------------
		"--update")
			sudo bash -c "$(curl -H 'Cache-Control: no-cache' -fsSL https://raw.githubusercontent.com/alexaandrov/stitchocker/master/install.sh)"
			exit 0
		;;
		# --------------------------------------------------------------
		# The entry point for all commands
		# --------------------------------------------------------------
		$path_flag)
			# Function arguments
			local path="$2"
			local command="$3"
			local first_flag="$4"
			local second_flag="$5"
			local flags="${@:4}"
			local scr_config_env="test"

			if [[ -z $path ]]; then
				scr_error "Path not specified"
			fi

			if [[ -z $command ]]; then
				scr_error "Command not specified"
			fi

			# if [[ $first_flag == "--all" ]]; then
			# 	for service_name in $(cd $path && ls -d */) ; do
			# 		local path="$path/$service_name"
			# 		local cmd="$exec $path $command"
			# 		if [[ $command != "up" ]]; then
			# 			local cmd="$cmd $flags"
			# 		else
			# 			local cmd="$cmd -d"
			# 		fi
			# 		eval $cmd
			# 	done
			# fi

			# General variables
			local config="docker-compose.yaml"
			local config_path="$path/$config"

			if [[ ! -e $config_path ]]; then
				config="docker-compose.yml"
				config_path="$path/$config"
				if [[ ! -e $config_path ]]; then
					scr_error "No such file or directory: '$config_path'"
				fi
			fi

			local default_set=$(scr_env stitchocker_default_set)
			if [[ ! -z $default_set && $default_set != "null" ]]; then
				default_set="$default_set"
			else
				default_set="default"
			fi

			local sets_field="scr_config_sets"

			scr_create_yaml_variables $config_path "scr_config_"

			local sets_data="$(eval echo \$${sets_field}_${default_set})"

			if [[ ! -z $sets_data ]]; then
				if	[[ ! -z $first_flag ]]; then
					if [[ ! -z $second_flag ]]; then
						for set in $flags; do
							eval "$exec $path $command $set"
						done
						exit 1
					fi
					local set="$first_flag"
				else
					local set="$default_set"
				fi

				local services="$(eval echo \${${sets_field}_${set}[*]})"

				if [[ -z $services ]]; then
					scr_error "Your config doesn't have \"$set\" value"
				fi

				echo
				scr_info "$(echo "$command" | awk '{print toupper(substr($0,0,1))tolower(substr($0,2))}') $set set:"
				
				for service_alias in ${services}; do
					local service_alias_head="$(echo $service_alias | head -c 1)"
					if [[ $service_alias == *"/"* ]]; then
						if [[ $service_alias_head == "@" ]]; then
							local service_alias="${service_alias//@}"
							local service_path="$(scr_env $service_alias)"
						elif [[ $service_alias_head == "/" || $service_alias_head == "~" ]]; then
							local service_path="$service_alias"
						else
							local service_path="$path/$service_alias"
						fi

						local cmd="$exec $service_path $command"
						if [[ $command != "up" ]]; then
							cmd="$cmd"
						else
							cmd="$cmd -d"
						fi
						eval $cmd
					elif [[ $service_alias_head == "@" ]]; then
						local set="${service_alias//@}"
						eval "$exec $path $command $set"
					else
						local service_path="$path/$service_alias"
						local cmd="$exec $service_path $command"
	
						if [[ $command != "up" ]]; then
							cmd="$cmd"
						else
							cmd="$cmd -d"
						fi
						eval $cmd
					fi
				done
			else
				# --------------------------------------------------------------
				# The main unit where commands are generated for docker compose
				# --------------------------------------------------------------

				scr_env_handle "$initial_path" "$scr_config_env" "$path"

				local cmd="docker-compose -f $config_path $command $flags"

				if [[ $debug == false ]]; then
					eval $cmd
				else
					echo $cmd
				fi

				scr_env_handle -r "$initial_path" "$scr_config_env" "$path"
			fi
		;;
		# --------------------------------------------------------------
		# Entry point wrapper
		# Triggered when stitchocker -a {alias} {command}
		# --------------------------------------------------------------
		"-a")
			if [[ -z $2 ]]; then
				scr_error "Path alias not specified"
			fi

			if [[ -z $3 ]]; then
				scr_error "Command not specified"
			fi

			local path=$(scr_env $2)
			local initial_path=$path
			eval "$exec $path ${@:3}"
		;;
		# --------------------------------------------------------------
		# Default entry point wrapper
		# Triggered when stitchocker {command}
		# --------------------------------------------------------------
		*)
			local path=$(pwd)
			local initial_path=$path
			eval "$exec $path $command $@"
		;;
	esac
}

# -----------------------------------------------
# Tools
# -----------------------------------------------

##
# Returns absolute path to user env
##
function scr_env
{
    local env_alias=$(echo $1 | cut -d "/" -f 1)
    local env_additional_path=${1//"$env_alias/"}
    local env=$(echo $env_alias | awk '{print toupper($0)}')

    local env_path="$(eval "echo \"\$$env\"")"

    if [[ ! -z "$env_additional_path" && "$env_alias" != "$env_additional_path" ]]; then
        env_path="$env_path/$env_additional_path"
    fi

    if [[ $env_path == *"himBHs"* || -z $env_path ]]; then
        echo "null"
    fi

    echo $env_path
}

##
# Adds an environment from config to each service
##
function scr_env_handle
{
	if [[ $1 != "-r" ]]; then
		local scr_path="$1"
		local scr_env="$2"
		local service_path="$3"
	else
		local scr_path="$2"
		local scr_env="$3"
		local service_path="$4"
	fi

	if [[ ! -z $scr_path && ! -z $scr_env ]]; then
		local scr_env_path="$scr_path/$scr_env"
		local service_env_name=".env"
		local service_env_tmp_name=".env.scr"
		local service_env_path="$service_path/$service_env_name"
		local service_env_tmp_path="$service_path/$service_env_tmp_name"
	
		if [[ $1 != "-r" ]]; then
			if [[ -f $scr_env_path ]]; then
				if [[ -f $service_env_path ]]; then
					cp $service_env_path $service_env_tmp_path
				fi
		
				echo >> $service_env_path
				cat $scr_env_path >> $service_env_path
			fi
		else
			if [[ -f $service_env_path ]]; then
				rm $service_env_path
			fi
		
			if [[ -f $service_env_tmp_path ]]; then
				mv $service_env_tmp_path $service_env_path;
			fi
		fi
	fi
}

# --
# Messages
# --

function scr_info {
  local green=$(tput setaf 2)
  local reset=$(tput sgr0)
  echo -e "${green}$@${reset}"
}

function scr_error {
  local red=$(tput setaf 1)
  local reset=$(tput sgr0)
  echo >&2 -e "${red}$@${reset}"
  exit 1
}

# --
# Data parsing
# --

##
# Based on https://gist.github.com/pkuczynski/8665367
# From https://github.com/jasperes/bash-yaml
##
function scr_parse_yaml() {
    local yaml_file=$1
    local prefix=$2
    local s
    local w
    local fs

    s='[[:space:]]*'
    w='[a-zA-Z0-9_.-]*'
    fs="$(echo @|tr @ '\034')"

    (
        sed -e '/- [^\“]'"[^\']"'.*: /s|\([ ]*\)- \([[:space:]]*\)|\1-\'$'\n''  \1\2|g' |

        sed -ne '/^--/s|--||g; s|\"|\\\"|g; s/[[:space:]]*$//g;' \
            -e "/#.*[\"\']/!s| #.*||g; /^#/s|#.*||g;" \
            -e "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
            -e "s|^\($s\)\($w\)${s}[:-]$s\(.*\)$s\$|\1$fs\2$fs\3|p" |

        awk -F"$fs" '{
            indent = length($1)/2;
            if (length($2) == 0) { conj[indent]="+";} else {conj[indent]="";}
            vname[indent] = $2;
            for (i in vname) {if (i > indent) {delete vname[i]}}
                if (length($3) > 0) {
                    vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
                    printf("%s%s%s%s=(\"%s\")\n", "'"$prefix"'",vn, $2, conj[indent-1],$3);
                }
            }' |

        sed -e 's/_=/+=/g' |

        awk 'BEGIN {
                FS="=";
                OFS="="
            }
            /(-|\.).*=/ {
                gsub("-|\\.", "_", $1)
            }
            { print }'
    ) < "$yaml_file"
}

function scr_create_yaml_variables() {
    local yaml_file="$1"
    local prefix="$2"

	if [[ ! -z $prefix ]]; then
		scr_unset_yaml_variables $prefix
	fi

    eval "$(scr_parse_yaml "$yaml_file" "$prefix")"
}

function scr_unset_yaml_variables()
{
	local prefix="$1"
	local variables=$( set -o posix; set |  cut -f1 -d"=" | grep $prefix )

	for variable in $variables; do
		unset $variable
	done
}


# -----------------------------------------------
# Bootstrap
# -----------------------------------------------

scr $@
