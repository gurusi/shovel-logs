#!/bin/bash
#
# +----------------------------------------------------------------------------+
# |                            shovel-logs.sh                                  |
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
# Okay, these variable names are really long. But they are descriptive.
# Anything shorter, and confusion would set in.
CONF_COMPRESS_CMD="compress-logs.sh"
CONF_COMPRESS_LIST_CMD="list-logs.sh -c nonexisting-listlogs-for-compress.conf"
CONF_DELETE_CMD="delete-logs.sh"
CONF_DELETE_LIST_CMD="list-logs.sh -c nonexisting-deletelogs.conf" 
CONF_TRANSPORT_CMD="copy-logs.sh -c nonexisting-copylogs.conf"
CONF_TRANSPORT_LIST_CMD="list-logs.sh -c nonexisting-listlogs-for-transport.conf" 
#}}}

# libguru-base.sh initialization
# Command-line parsing and help #{{{
#
# Parse the command line arguments and build a running configuration from them.
#
# Note that this function should be called like this: >parse_args "$@"< and
# *NOT* like this: >parse_args $@< (without the ><, of course). The second
# variant will work but it will cause havoc if the arguments contain spaces!
#
parse_args() {
  local short_args="c:,d,h,n,p,v"
  local long_args="config:,compress-cmd:,debug,delete-cmd:,no-check-deps,no-abort,help,list-cmd-compress:,list-cmd-delete:,list-cmd-transport:,mail-from:,mail-to:,mail-subject:,print-config,print-valid-config,syslog,simulate,transport-cmd:,verbose"
  local g; g=$(getopt -n $CONF_SCRIPT_NAME -o $short_args -l $long_args -- "$@") || die "Could not parse arguments, aborting."
  log_debug "args: $args, getopt: $g"

  eval set -- "$g"
  while true; do
    local a; a="$1"

    # This is the end of arguments, set the stuff we didn't parse (the
    # non-option arguments, e.g. the stuff without the dashes (-))
    if [ "$a" = "--" ] ; then
      shift
      return 0

    # mail-from
    elif [ "$a" = "--mail-from" ] ; then
      shift; CONF_MAIL_FROM="$1"

    # mail-to
    elif [ "$a" = "--mail-to" ] ; then
      shift; CONF_MAIL_TO="$1"

    # mail-subject
    elif [ "$a" = "--mail-subject" ] ; then
      shift; CONF_MAIL_SUBJECT="$1"

    # This is the config file.
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

    # Print the current valid configuration.
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

    # compress-logs
    elif [ "$a" = "--compress-cmd" ] ; then
      shift; CONF_COMPRESS_CMD="$1"

    # list-logs command for compress
    elif [ "$a" = "--list-cmd-compress" ] ; then
      shift; CONF_COMPRESS_LIST_CMD="$1"

    # transport-logs
    elif [ "$a" = "--transport-cmd" ] ; then
      shift; CONF_TRANSPORT_CMD="$1"

    # list-logs command for transport
    elif [ "$a" = "--list-cmd-transport" ] ; then
      shift; CONF_TRANSPORT_LIST_CMD="$1"

    # delete-logs
    elif [ "$a" = "--delete-cmd" ] ; then
      shift; CONF_DELETE_CMD="$1"

    # list-logs command for delete
    elif [ "$a" = "--list-cmd-delete" ] ; then
      shift; CONF_DELETE_LIST_CMD="$1"

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
A shovel for logfiles. Probably too generic and complex. 

Usage: $CONF_SCRIPT_NAME [option ...] 

[option] is one of the following. Some options are MANDATORY, others are
entirely optional (doh).

MANDATORY options:
  --compress-cmd      : an executable that compresses the logs, current: "$CONF_COMPRESS_CMD"
  --list-cmd-compress : an executable that lists the logs we wish to compress, 
                         current: "$CONF_COMPRESS_LIST_CMD"

  --transport-cmd      : an executable that transports the logs, current: "$CONF_TRANSPORT_CMD"
  --list-cmd-transport : an executable that lists the logs we wish to transport, 
                         current: "$CONF_TRANSPORT_LIST_CMD"

  --delete-cmd      : an executable that deletes the logs, current: "$CONF_DELETE_CMD"
  --list-cmd-delete : an executable that lists the logs we wish to delete, 
                         current: "$CONF_DELETE_LIST_CMD"

Options:
  Mail stuff:
  --mail-to        : Send the report to this email address, current: "$CONF_MAIL_TO"
  --mail-from      : Send the report from this email address, current: "$CONF_MAIL_FROM"
  --mail-subject   : The mail subject, current: "$CONF_MAIL_SUBJECT"

  Configuration stuff:
  -c, --config         : Path to config file, current: "$CONF_FILE"
  -p, --print-config   : Print the current configuration, then exit. Current: "$CONF_DO_PRINT_CONFIG"
  --print-valid-config : Print the configuration after all checks have passed, current: "$CONF_DO_PRINT_VALID_CONFIG"

  General:
  -h, --help      : This text, current: "$CONF_DO_PRINT_HELP"
  -v, --verbose   : I am a human, so be more verbose. Not suitable as a machine
                    input, current "$CONF_DO_VERBOSE"
  -d, --debug     : Enable debug output, current: "$CONF_DO_DEBUG"
  -n, --simulate  : Don't actually do anything, just report what would have been
                    done, current: "$CONF_DO_SIMULATE"
  --syslog        : Log to syslog, too. Current: "$CONF_DO_SYSLOG"
  --no-check-deps : Don't check dependencies to external programs, current: "$CONF_DONT_CHECK_DEPS"
  --no-abort      : Don't abort on non-fatal errors, issue a warning instead.  Current: "$CONF_DONT_ABORT"

Due to nature of things, the configuration values in here might not be correct. 
Run "$CONF_SCRIPT_NAME -p" to see the full configuration, or you might even try
"$CONF_SCRIPT_NAME --print-valid-config" to see the vaildated config.
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
# Checkers/validator functions #{{{
check_executable() {
  local bin="$1"; [ -z "$bin" ] && {
    log_error "No commandline given."
    return 1
  }
  [ ! -x "$(which $bin)" ] && {
      log_error "External program '$bin' not found anywhere in PATH ($PATH)."
      return 1
    }
  return 0
}

check_CONF_COMPRESS_LIST_CMD() {
  [ -z "$CONF_COMPRESS_LIST_CMD" ] && {
    log_error "No executable given for listing the logs we wish to compress."
    return 1
  }
  check_executable $CONF_COMPRESS_LIST_CMD || {
    log_error "The executable for listing the logs we wish to compress cannot be found."
    return 1
  }
  return 0
}

check_CONF_TRANSPORT_LIST_CMD() {
  [ -z "$CONF_TRANSPORT_LIST_CMD" ] && {
    log_error "No executable given for listing the logs we wish to transport."
    return 1
  }
  check_executable $CONF_TRANSPORT_LIST_CMD || {
    log_error "The executable for listing the logs we wish to transport cannot be found."
    return 1
  }
  return 0
}

check_CONF_TRANSPORT_CMD() {
  [ -z "$CONF_TRANSPORT_CMD" ] && {
    log_error "No executable given for compressing the logfiles."
    return 1
  }
  check_executable $CONF_TRANSPORT_CMD || {
    log_error "The executable given for compressing the logfiles cannot be found."
    return 1
  }
  return 0
}

check_CONF_COMPRESS_CMD() {
  [ -z "$CONF_COMPRESS_CMD" ] && {
    log_error "No executable given for compressing the logfiles."
    return 1
  }
  check_executable $CONF_COMPRESS_CMD || {
    log_error "The executable given for compressing the logfiles cannot be found."
    return 1
  }
  return 0
}
#}}}

# Go go go!
# Init#{{{
## Then, let's check the actual configuration.
#check_CONF_COMPRESS_CMD; errors=$(( $errors + $? ))
#check_CONF_COMPRESS_LIST_CMD; errors=$(( $errors + $? ))
#check_CONF_TRANSPORT_CMD; errors=$(( $errors + $? ))
#check_CONF_TRANSPORT_LIST_CMD; errors=$(( $errors + $? ))

## Stop if there are any errors in the configuration.
#[ "$errors" -gt 0 ] && die "$errors error(s) found in the configuration."
#unset errors

# Print the config after validation.
[ -n "$CONF_DO_PRINT_VALID_CONFIG" ] && {
  print_config
  remove_mail_body
  exit 0
}
#}}}
# Do the actual work#{{{

# First, behave like a good wraper script would and export the variables that
# might interset list-logs.sh, compress-logs.sh, and copy-logs.sh etc, into the
# environment.
export CONF_DONT_ABORT CONF_DONT_CHECK_DEPS CONF_DO_DEBUG CONF_DO_SIMULATE CONF_DO_SYSLOG CONF_DO_VERBOSE

# Output the name of the configuration file if running with it
[ -n "$CONF_FILE" ] && {
  log "Running with configuration file: '$CONF_FILE'"; log
  CONF_MAIL_SUBJECT="$CONF_MAIL_SUBJECT with config file $CONF_FILE"
}

# The weirdness flag. If this is set, something is weird.
weirdness=""

# Do the compressing of logfiles. First, Gather the logfiles we need to
# compress.
log "Step #1 (out of 3): Compressing the logfiles."
if [ -z "$CONF_COMPRESS_CMD" ]; then
  log "Skipping, because no compress-command defined."
else
  log "Gathering the logfiles to compress."
  if do_mail; then
    tmp=$(mktemp)
    logs=$($CONF_COMPRESS_LIST_CMD 2> $tmp); retval=$?
    [ -s "$tmp" ] && {
      cat $tmp >> $CONF_MAIL_BODY; cat $tmp
      rm "$tmp"
    }
    if [ $retval -eq 1 ]; then
      weirdness="true"
    elif [ $retval -gt 1 ]; then
      die "Something went wrong while gathering the logfiles to compress."
    fi
    unset retval tmp
  else 
    logs=$($CONF_COMPRESS_LIST_CMD); retval=$?
    if [ $retval -eq 1 ]; then
      weirdness="true"
    elif [ $retval -gt 1 ]; then
      die "Something went wrong while gathering the logfiles to compress."
    fi
    unset retval
  fi
  # run the compress-logs step if there are any logs available
  if [ -z "$logs" ]; then
    log "No logfiles found to compress, skipping."
  else
    run="$CONF_COMPRESS_CMD $logs"
    log
    if do_debug; then
      log_debug; log_debug "Compressing the logfiles. Running '$run'"
    else
      log "Compressing the logfiles. Running '$CONF_COMPRESS_CMD'"
    fi
    # run, redirect output to the mail body file if we are logging to mail
    $run 2>&1 | tee ${CONF_MAIL_BODY:+-a $CONF_MAIL_BODY} || {
      die_or_warn "Could not compress some of the logs."
    }
  fi
  unset logs
fi

# Do the transporting of logfiles. First, gather the logfiles we need to
# transport
log; log "Step #2 (out of 3): Transporting the logs."
if [ -z "$CONF_TRANSPORT_CMD" ]; then
  log "Skipping, because no transport-command defined."
else
  log "Gathering the logfiles to transport."
  if do_mail; then
    tmp=$(mktemp)
    logs=$($CONF_TRANSPORT_LIST_CMD 2> $tmp); retval=$?
    [ -s "$tmp" ] && {
      cat $tmp >> $CONF_MAIL_BODY; cat $tmp
      rm "$tmp"
    }
    if [ $retval -eq 1 ]; then
      weirdness="true"
    elif [ $retval -gt 1 ]; then
      die "Something went wrong while gathering the logfiles to transport."
    fi
    unset retval tmp
  else 
    logs=$($CONF_TRANSPORT_LIST_CMD); retval=$?
    [ "$retval" -gt "1" ] && {
      die "Something went wrong while gathering the logfiles to transport."
    }
    unset retval
  fi
  # run the transport-logs step
  if [ -z "$logs" ]; then
    log "No logfiles found to transport, skipping."
  else
    run="$CONF_TRANSPORT_CMD $logs"
    if do_debug; then
      log "Transporting the logfiles. Running '$run'."
    else
      log "Transporting the logfiles. Running '$CONF_TRANSPORT_CMD'."
    fi
    # run, redirect output to the mail body file if we are logging to mail
    $run 2>&1 | tee ${CONF_MAIL_BODY:+-a $CONF_MAIL_BODY} || {
      die "Could not transport logs."
    }
  fi
fi

# TODO: delete the logfiles. Do this only if the user so whishes explicitly.
log; log "Step #3 (out of 3): Deleting the logs. "
if [ -z "$CONF_DELETE_CMD" ]; then
  log "Skipping, because no delete-command defined."
else
  log "Gathering the logfiles to delete."
  if do_mail; then
    tmp=$(mktemp)
    logs=$($CONF_DELETE_LIST_CMD 2> $tmp); retval=$?
    [ -s "$tmp" ] && {
      cat $tmp >> $CONF_MAIL_BODY; cat $tmp
      rm "$tmp"
    }
    if [ $retval -eq 1 ]; then
      weirdness="true"
    elif [ $retval -gt 1 ]; then
      die "Something went wrong while gathering the logfiles to delete."
    fi
    unset retval tmp
  else 
    logs=$($CONF_DELETE_LIST_CMD); retval=$?
    [ "$retval" -gt "1" ] && {
      die "Something went wrong while gathering the logfiles to delete."
    }
    unset retval
  fi
  # run the delete-logs step
  if [ -z "$logs" ]; then
    log "No logfiles found to delete, skipping."
  else
    run="$CONF_DELETE_CMD $logs"
    if do_debug; then
      log "Deleting the logfiles. Running '$run'."
    else
      log "Deleting the logfiles. Running '$CONF_DELETE_CMD'."
    fi
    # run, redirect output to the mail body file if we are logging to mail
    $run 2>&1 | tee ${CONF_MAIL_BODY:+-a $CONF_MAIL_BODY} || {
      die "Could not delete logs."
    }
  fi
fi

# exit cleanly
if [ -n "$weirdness" ]; then
  CONF_MAIL_SUBJECT="WEIRD: $CONF_MAIL_SUBJECT"
  log; log "Done, but something is weird. See above for details."
else
  CONF_MAIL_SUBJECT="OK: $CONF_MAIL_SUBJECT"
  log; log "All done."
fi
send_mail 
exit 0
#}}}

# vim: set tabstop=2 shiftwidth=2 expandtab colorcolumn=80 foldmethod=marker foldcolumn=3 foldlevel=0:
