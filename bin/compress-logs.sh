#!/bin/bash
#
# +----------------------------------------------------------------------------+
# |                            compress-logs.sh                                |                           
# +----------------------------------------------------------------------------+
#
# If this file seems a bit un-organized, you are reading it the wrong way (e.g.
# not in vim). Reload it in vim, type ":set modeline" (without the quotes), and
# ":e" (again without the quotes). This will set the proper stuff (see end of
# file). Do type ":help folds" to read up on vim folding technique.  Hint: use
# "zo" to open, "zc" to close individual folds.

# Global stuff
# Default configuration#{{{
#
# Globals
set -o pipefail

# Default configuration
#
CONF_COMPRESS_ARGS="-v"
CONF_COMPRESS_COMMAND="bzip2"
CONF_DEPS="bzip2 gzip"
CONF_LOG_FILES=""

#}}}

# libguru-base.sh initialization
# Command-line parsing and help#{{{
#
# Parse the command line arguments and build a running configuration from them.
#
# Note that this function should be called like this: >parse_args "$@"< and
# *NOT* like this: >parse_args $@< (without the ><, of course). The second
# variant will work but it will cause havoc if the arguments contain spaces!
#
parse_args() {
  local short_args="c:,d,h,n,p,v,z:"
  local long_args="compress-cmd:,compress-args:,config:,debug,no-check-deps,no-abort,help,print-config,print-valid-config,syslog,simulate,verbose"
  local g; g=$(getopt -n $CONF_SCRIPT_NAME -o $short_args -l $long_args -- "$@") || die "Could not parse arguments, aborting."
  log_debug "args: $args, getopt: $g"

  eval set -- "$g"
  while true; do
    local a; a="$1"

    # This is the end of arguments, set the stuff we didn't parse (the
    # non-option arguments, e.g. the stuff without the dashes (-))
    if [ "$a" = "--" ] ; then
      shift
      CONF_LOG_FILES="$@"
      return 0

    # This is the config file .
    elif [ "$a" = "-c" -o "$a" = "--config" ] ; then
      shift; CONF_FILE="$1"

    # The debug switch.
    elif [ "$a" = "-d" -o "$a" = "--debug" ] ; then
      CONF_DO_DEBUG="true"

    # Do not abort on non-fatal errors, issue a warning instead.
    elif [ "$a" = "--no-abort" ] ; then
      CONF_DONT_ABORT="true"

    # Do not check dependencies.
    elif [ "$a" = "--no-check-deps" ] ; then
      CONF_DONT_CHECK_DEPS="true"

    # Help.
    elif [ "$a" = "-h" -o "$a" = "--help" ] ; then
      CONF_DO_PRINT_HELP="true"

    # Print the current configuration.
    elif [ "$a" = "-p" -o "$a" = "--print-config" ] ; then
      CONF_DO_PRINT_CONFIG="true"

    # Print the current configuration.
    elif [ "$a" = "--print-valid-config" ] ; then
      CONF_DO_PRINT_VALID_CONFIG="true"

    # Syslog
    elif [ "$a" = "--syslog" ]; then
      CONF_DO_SYSLOG="true"

    # Verbosity
    elif [ "$a" = "-v" -o "$a" = "--verbose" ]; then
      CONF_DO_VERBOSE="true"

    # Simulate
    elif [ "$a" = "-n" -o "$a" = "--simulate" ]; then
      CONF_DO_SIMULATE="true"

    # The compress command
    elif [ "$a" = "-z" -o "$a" = "--compress-cmd" ] ; then
      shift; CONF_COMPRESS_COMMAND="$1"

    # The compress command
    elif [ "$a" = "--compress-args" ] ; then
      shift; CONF_COMPRESS_ARGS="$1"

    # Dazed and confused...
    else
      die -e "I apparently know about the '$a' argument, but I don't know what to do with it.\nAborting. This is an error in the script. Bug the author, if he is around."
    fi

    shift
  done

  return 0
}

# Print the help stuff
# 
print_help() {
  cat <<HERE
Usage: $CONF_SCRIPT_NAME [option ...] <file>

[option] is one of the following. Options are optional (doh!):
  -z, --compress-cmd  : The command used to compress logs, Current: "$CONF_COMPRESS_COMMAND"
      --compress-args : Arguments given to compress command, current: "$CONF_COMPRESS_ARGS"

  Configuration stuff:
  -c, --config         : Path to config file, current: "$CONF_FILE"
  -p, --print-config   : Print the current configuration, then exit. Current: "$CONF_DO_PRINT_CONFIG"
  --print-valid-config : Print the configuration after all checks have passed, 
                         current: "$CONF_DO_PRINT_VALID_CONFIG"

  General:
  -h, --help      : This text, current: "$CONF_DO_PRINT_HELP"
  -v, --verbose   : I am a human, so be more verbose. not suitable as a machine
                    input, current "$CONF_DO_VERBOSE"
  --syslog        : Log to syslog, too. Current: "$CONF_DO_SYSLOG"
  --no-check-deps : Don't check dependencies to external programs, current: "$CONF_DONT_CHECK_DEPS"
  --no-abort      : Don't abort on non-fatal errors, issue a warning instead.
                    Current: "$CONF_DONT_ABORT"
  -d, --debug     : Enable debug output, current: "$CONF_DO_DEBUG"
  -n, --simulate  : Don't actually do anything, just report what would have been
                    done, current: "$CONF_DO_SIMULATE"

Due to nature of things, the configuration values in here might not be correct. 
Run "$CONF_SCRIPT_NAME -p" to see the full configuration.
HERE
  return 0
}
#}}}
# Include the libguru-base.sh #{{{
#
files="libguru-base.sh"; directories="/usr/local/lib/libguru /usr/lib/libguru"
for f in $files; do
  included=""
  for d in $directories; do
    path="$d/$f"; [ -x "$path" ] && {
      . $path
      included="true"
      break
    }
  done
  [ -z "$included" ] && {
    echo "Could not include library '$f' from anywhere in paths '$directories', aborting."
    exit 255
  }
done
unset files f directories d included
#}}}

# Script functions
# Checker/validator functions#{{{

check_CONF_COMPRESS_COMMAND() {
  [ -z "$CONF_COMPRESS_COMMAND" ] && {
    log_error "No compress command given."
    return 1
  }
  # test for the execution of the first word, others might be arguments
  local f
  for f in "$CONF_COMPRESS_COMMAND"; do
    [ -x "$(which $f)" ] || {
      log_error "Can't find compress command '$f'."
      return 1
    }
  done
  return 0
}

#}}}

# Go go go!
# Init#{{{
check_CONF_COMPRESS_COMMAND; errors=$(( $errors + $? ))

# Stop if there are any errors in the configuration.
[ "$errors" -gt 0 ] && die "$errors error(s) found in the configuration."
unset errors

# Print the config after validation.
[ -n "$CONF_DO_PRINT_VALID_CONFIG" ] && {
  print_config
  remove_mail_body
  exit 0
}
#}}}
# Do the actual work#{{{
#
# Check if we've got anything to do at all
[ -z "$CONF_LOG_FILES" ] && {
  log "No files given, nothing to do."
  exit 0
}

# Compress the files
# do the stuff if we are not in simulate mode
run="nice -n19 $CONF_COMPRESS_COMMAND $CONF_COMPRESS_ARGS $CONF_LOG_FILES"
if do_simulate; then
  log "Would run: \"$run\"."
else
  log_debug "Running: '$run'"
  eval $run || {
    die_or_warn "Failed compressing."
  }
fi

exit 0
#}}}

# vim: set tabstop=2 shiftwidth=2 expandtab colorcolumn=80 foldmethod=marker foldcolumn=3 foldlevel=0:
