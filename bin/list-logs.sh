#!/bin/bash
#
# +----------------------------------------------------------------------------+
# |                                list-logs.sh                                |                           
# +----------------------------------------------------------------------------+
#
# A shovel for logfiles. Environmentaly friendly, semi-automatic. Comes without
# a manual.
#
# If this file seems a bit un-organized, you are reading it the wrong way (e.g.
# not in vim). Reload it in vim, type ":set modeline" (without the quotes), and
# ":e" (again without the quotes). This will set the proper stuff (see end of
# file). Do type ":help folds" to read up on vim folding technique.  Hint: use
# "zo" to open, "zc" to close individual folds.

# Global stuff
# Default configuration #{{{
#
set -o pipefail
declare -A LOGFILES                                                             # the array that holds all the stuff

# Default configuration
CONF_DATE_FROM=""
CONF_DATE_TO=""
CONF_DEPS="date pcregrep sed awk"
CONF_LOGFILE_PCRE=""
CONF_LOGFILE_PCRE_OPTS="-o1 -o2 -o3"
CONF_LOG_DIR=""
CONF_PCREGREP_OLD=""
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
  local short_args="a:,b:,c:,d,h,o:,p,v"
  local long_args="config:,debug,no-check-deps,no-abort,help,print-config,print-valid-config,syslog,pattern-opts:,from-date:,to-date:,verbose"
  local g; g=$(getopt -n $CONF_SCRIPT_NAME -o $short_args -l $long_args -- "$@") || die "Could not parse arguments, aborting."
  log_debug "args: $args, getopt: $g"

  eval set -- "$g"
  while true; do
    local a; a="$1"

    # This is the end of arguments, set the stuff we didn't parse (the
    # non-option arguments, e.g. the stuff without the dashes (-))
    if [ "$a" = "--" ] ; then
      shift
      # the log directory
      [ -n "$1" ] && {
        CONF_LOG_DIR="$1"; shift
        # the pcre expression
        [ -n "$1" ] && {
          CONF_LOGFILE_PCRE="$1"; shift
        }
      }
      return 0

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

    # Print the current configuration.
    elif [ "$a" = "--print-valid-config" ] ; then
      CONF_DO_PRINT_VALID_CONFIG="true"

    # Syslog
    elif [ "$a" = "--syslog" ]; then
      CONF_DO_SYSLOG="true"

    # Verbosity
    elif [ "$a" = "-v" -o "$a" = "--verbose" ]; then
      CONF_DO_VERBOSE="true"

    # The pattern options
    elif [ "$a" = "-o" -o "$a" = "--pattern-opts" ]; then
      shift; CONF_LOGFILE_PCRE_OPTS="$1"

    # From date
    elif [ "$a" = "-a" -o "$a" = "--from-date" ]; then
      shift; CONF_DATE_FROM="$1"

    # To date
    elif [ "$a" = "-b" -o "$a" = "--to-date" ]; then
      shift; CONF_DATE_TO="$1"

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
Usage: $CONF_SCRIPT_NAME [option ...] <log-directory> <pcre-pattern>
<log-directory> : where your logfiles are, current: "$CONF_LOG_DIR"
<pcre-pattern>  : Perl pcre pattern to apply to logfiles, current: "$CONF_LOGFILE_PCRE"

[option] is one of the following. Options are optional (doh!):
  -a, --from-date : Process logs from this date, current: "$CONF_DATE_FROM"
  -b, --to-date   : Process logs to this date, current: "$CONF_DATE_TO"
  --pattern-opts  : Options passed to pcregrep, current: "$CONF_LOGFILE_PCRE_OPTS"

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

Due to nature of things, the configuration values in here might not be correct. 
Run "$CONF_SCRIPT_NAME -p" to see the full configuration.

If you use date(1) formats in --from or --to, be sure to quote the arguments.
E.g.: use $CONF_SCRIPT_NAME "--from 1 week ago".
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
#
check_CONF_LOG_DIR() {
  local errors=0
  if [ -z "$CONF_LOG_DIR" ]; then
    log_error "No log directory given."
    errors=$(( $errors + 1 ))
  elif [ ! -e "$CONF_LOG_DIR" ]; then
    log_error "Log directory '$CONF_LOG_DIR' does not exist."
    errors=$(( $errors + 1 ))
  elif [ ! -d "$CONF_LOG_DIR" ]; then
    log_error "Log directory '$CONF_LOG_DIR' is not a directory."
    errors=$(( $errors + 1 ))
  elif [ ! -r "$CONF_LOG_DIR" ]; then
    log_error "Log directory '$CONF_LOG_DIR' is not readable, check its permissions."
    errors=$(( $errors + 1 ))
  elif [ ! -x "$CONF_LOG_DIR" ]; then
    log_error "Can't chdir to '$CONF_LOG_DIR', check its permissions."
    errors=$(( $errors + 1 ))
  fi
  return $errors
}

check_CONF_LOGFILE_PCRE() {
  local errors=0
  [ -z "$CONF_LOGFILE_PCRE" ] && {
    log_error "No pcre pattern given; don't know how to gather logfiles, and don't know how to parse dates from filenames."
    errors=$(( $errors + 1 ))
  }
  return $errors
}

check_CONF_DATE_FROM() {
  [ -z "$CONF_DATE_FROM" ] && {
    log_debug "No from-date given, first logfile that I find sets the from-date."
    return 0
  }
  # If the given date is not simple, make it so.
  is_date_simple "$CONF_DATE_FROM" || CONF_DATE_FROM="$(parse_to_simple_date "$CONF_DATE_FROM")" || return 1
}

check_CONF_DATE_TO() {
  [ -z "$CONF_DATE_TO" ] && {
    log_debug "No to-date given, last logfile I see sets the to-date."
    return 0
  }
  # If the given date is not simple, make it so.
  is_date_simple "$CONF_DATE_TO" || CONF_DATE_TO="$(parse_to_simple_date "$CONF_DATE_TO")" || return 1
  return 0
}

check_pcregrep_version() {
  local ver=$(pcregrep --version 2>&1 | awk '{ print $3 }') || {
    die "Could not figure out pcregrep version." 
  }
  local required_ver="8.32"
  [ "$required_ver" != "$(echo -e "${ver}\n${required_ver}" | sort -V | head -n1)" ] && {
    CONF_PCREGREP_OLD="true"
    log_warning -e "You have an old pcregrep(1) that doesn't support multiple -o switches! Using a\nclumsy workaround that is prone to bugs and doesn't really respect the given pcre-pattern!\nSee http://upstream.rosalinux.ru/changelogs/pcre/8.32/changelog.html for details."
  }
  return 0
}

#}}}
# Date functions#{{{
#
# Check if the given date is in the YYYMMDD format.
#
is_date_simple() {
  local d="$1"
  [ -z "$d" ] && {
    log_error "No date given."
    return 1
  }
  echo "$d" | pcregrep '^\d{4}\d{2}\d{2}$' 2>&1 > /dev/null
}

# Convert given date to YYYYMMDD format.
#
parse_to_simple_date() {
  local d="$@"
  [ -z "$d" ] && {
    log_error "No date given."
    return 1
  }
  local a; a=$(date +%Y%m%d --date="$d") || {
    log_error "could not convert date '$d' to simple date."
    return 1
  }
  echo "$a"
  return 0
}

check_date_interval() {
  local from; from="$1"; shift
  [ -z "$from" ] && return 1
  is_date_simple "$from" || {
    from="$(parse_to_simple_date $from)" || return 1
  }
  
  local to; to="$1"; shift
  [ -z "$to" ] && return 1
  is_date_simple "$to" || {
    to="$(parse_to_simple_date $to)" || return 1
  }

  [ "$from" -gt "$to" ] && {
    log_warning "from-date \"$from\" is greater than to-date \"$to\", switching them around."
    local tmp="$CONF_DATE_FROM"
    CONF_DATE_FROM="$CONF_DATE_TO"
    CONF_DATE_TO="$tmp"
  }
  return 0
}

# get a list of dates from from-date to to-date
#
get_dates() {
  # check for presence
  local from="$1"; shift
  [ -z "$from" ] && {
    log_debug "No from-date given."
    return 1
  }
  local to="$1"; shift
  [ -z "$to" ] && {
    log_debug "No to-date given."
    return 1
  }

  # convert the dates to simple format, if they are not alredy there 
  is_date_simple "$from" || { 
    from="$(parse_to_simple_date)" || return 1 
  }
  is_date_simple "$to" || { 
    to="$(parse_to_simple_date)" || return 1 
  }

  check_date_interval "$from" "$to" || return 1
  local d out; d="$from"
  while [ "$d" -le "$to" ]; do
    out="$out $d"
    d=$(date --date "$d + 1 day" +%Y%m%d)
  done
  echo $out
  return 0
}
#}}}
# Functions that deal with logfiles #{{{
#
# gather all the logfiles
#
get_logfiles() {
  # We use find(1) here instead of ls, because we really want to list the
  # files, not symlinks or directories with the same name. And, we want to do
  # this recursively (I guess?)
  find ${CONF_LOG_DIR}/ -type f | pcregrep "$CONF_LOGFILE_PCRE" | sort
}

# parse a date from the given filename using the configuration
#
parse_date_from_filename() {
  local file="$1"; shift
  [ -z "$file" ] && {
    log_error "No filename given."
    return 1
  }
  if [ -n "$CONF_PCREGREP_OLD" ]; then
    echo "$file" | pcregrep -o "\d{4}\D?\d{2}\D?\d{2}" | sed 's/[^0-9]//g'
  else
    echo "$file" | pcregrep $CONF_LOGFILE_PCRE_OPTS "$CONF_LOGFILE_PCRE"
  fi
}

# is a logfile younger than the specified date?
#
#is_logfile_younger() {
  #local logfile="$1"; shift
  #[ -z "$logfile" ] && {
    #log_error "No logfile given."
    #return 2
  #}
  #local d="$1"; shift
  #[ -z "$d" ] && {
    #log_error "No date given."
    #return 2
  #}
  #local logfile_date
  #logfile_date="$(parse_date_from_filename $logfile)"
  #if [ "$logfile_date" -gt "$d" ]; then
    #return 0
  #else
    #return 1
  #fi
#}

# is a logfile older than the specified date?
#
#is_logfile_older() {
  #local logfile="$1"; shift
  #[ -z "$logfile" ] && {
    #log_error "No logfile given."
    #return 2
  #}
  #local d="$1"; shift
  #[ -z "$d" ] && {
    #log_error "No date given."
    #return 2
  #}
  #local logfile_date
  #logfile_date="$(parse_date_from_filename $logfile)"
  #if [ "$logfile_date" -lt "$d" ]; then
    #return 0
  #else
    #return 1
  #fi
#}
#}}}
# Functions that handle the logfiles array#{{{
#
# is logfiles empty?
#
logfiles_is_empty() {
  if [ -z "$(logfiles_keys)" ]; then
    return 0
  else
    return 1
  fi
}

# get a list of all logfiles keys (e.g. the dates)
#
logfiles_keys() {
  echo "${!logfiles[@]}" | sed ':a;$!{N;ta};s/ /\n/g' | sort
}

# get a list of all logfiles values (e.g. the logfiles)
#
logfiles_values() {
  local name
  for name in $(logfiles_keys); do
    echo "$name"
  done
}

# fill up the "logfiles" array with content
#
logfiles_init() {
  local list="$(get_logfiles)"
  [ -z "$list" ] && {
    log_debug "No logfiles found."
    return 1
  }

  local l
  for l in $list; do
    local d
    d=$(parse_date_from_filename "$l")

    # empty date?
    [ -z "$d" ] && {
      if [ -n "$CONF_DO_FORCE" ]; then
        log_warning "Could not parse date for logfile \"$l\"."
      else
        die "Could not parse date for logfile \"$l\"."
      fi
    }

    # Append the logfile(s) found, there might be more than one logfile for a 
    # day. Like in hourly-rotated logfiles.
    if [ -z "${logfiles[$d]}" ]; then
      logfiles[$d]=$l
    else
      logfiles[$d]="${logfiles[$d]} $l"
    fi
  done
  return 0
}

# Prune the logfiles array to include only the selected dates.
#
logfiles_prune() {
  # check for presence
  local from="$1"; shift
  [ -z "$from" ] && {
    log_debug "No from-date given."
    return 1
  }
  local to="$1"; shift
  [ -z "$to" ] && {
    log_debug "No to-date given."
    return 1
  }

  # convert the dates to simple format, if they are not alredy there 
  is_date_simple "$from" || { 
    from="$(parse_to_simple_date)" || return 1 
  }
  is_date_simple "$to" || { 
    to="$(parse_to_simple_date)" || return 1 
  }

  check_date_interval "$from" "$to" || return 1

  local d
  for d in $(logfiles_keys); do
    [ "$d" -lt "$from" -o "$d" -gt "$to" ] && {
      log_debug "Found logfiles for date \"$d\", but this date is out of the list criteria (from: \"$from\", to: \"$to\"). Pruning this entry."
      unset logfiles[$d]
    }
  done
  return 0
}

# Get the smallest date from the logfiles array
#
logfiles_get_first_date() {
  local d="$(logfiles_keys | head -n1)" || {
    log_debug "Could not determine first date."
    return 1
  }
  [ -z "$d" ] && {
    log_debug "No first date found."
    return 1
  }
  echo "$d"
  return 0
}

# Check the sizes of logfiles, and complain if they are not up to our standards.
#
logfiles_check_file_sizes() {
  local d dates empty_files; dates="$(logfiles_keys)"; empty_files=0
  for d in $dates; do
    local f files; files="${logfiles[$d]}"
    for f in $files; do
      log_debug "Checking file \"$f\" for size."
      [ -s "$f" ] || {
        if dont_abort; then
          log_warning "Logfile \"$f\" is empty."
        else
          log_error "Logfile \"$f\" is empty."
          empty_files=$(( $empty_files + 1 ))
        fi
      }
    done
  done
  if [ "$empty_files" -gt 0 ]; then
    return 1
  else
    return 0
  fi
}

# Get the largest date from the logfiles array
#
logfiles_get_last_date() {
  local d="$(logfiles_keys | tail -n1)" || {
    log_debug "Could not determine last date."
    return 1
  }
  [ -z "$d" ] && {
    log_debug "No last date found."
    return 1
  }
  echo "$d"
  return 0
}

# print the status of the logfiles array and be verbose about it
#
logfiles_verbose_status() {
  log "The first date I found a logfile for is \"$(logfiles_get_first_date)\", the last is \"$(logfiles_get_last_date)\". All number of dates: ${#logfiles[@]}"
  local d all=0
  for d in $(logfiles_keys); do
    say; log "Logfiles for date \"$d\":"
    local output="$(echo ${logfiles[$d]} | sed ':a;$!{N;ta};s/ /\\n/g')"
    log -e "$output"
    local current=$(count_words ${logfiles[$d]})
    log "total: $current"
    all=$(( $all + $current ))
  done
  say; log "All logfiles found: $all"
  return 0
}

# print the status of the logfiles array 
#
logfiles_status() {
  local output
  for d in $(logfiles_keys); do
    if [ -z "$output" ]; then
      output="$(echo ${logfiles[$d]} | sed ':a;$!{N;ta};s/ /\\n/g')"
    else
      output="${output}\n$(echo ${logfiles[$d]} | sed ':a;$!{N;ta};s/ /\\n/g')"
    fi
  done
  log -e "$output"
  return 0
}

# get all the dates for which logfiles are missing
#
logfiles_get_missing_dates() {
  # go through each day from from-date to to-date and check if we've got a
  # logfile for that day
  local dates; dates="$(get_dates $CONF_DATE_FROM $CONF_DATE_TO)" || return 1
  [ -z "$dates" ] && return 1

  # output missing dates
  local d;
  for d in $dates; do
    [ -z "${logfiles[$d]}" ] && echo "$d"
  done
  return 0
}
#}}}
# Generic functions that don't fit anywhere else#{{{
#
# Count the number of words given
#
count_words() {
  local words=0
  while [ -n "$1" ]; do
    shift;
    words=$(( $words + 1 ))
  done
  echo "$words"
}
#}}}

# Go go go!
# Init#{{{
#
# Then, let's check the actual configuration.
check_CONF_LOG_DIR; errors=$(( $errors + $? ))
check_CONF_LOGFILE_PCRE; errors=$(( $errors + $? ))
check_CONF_DATE_FROM; errors=$(( $errors + $? ))
check_CONF_DATE_TO; errors=$(( $errors + $?))
check_pcregrep_version

# check the date interval
[ -n "$CONF_DATE_FROM" -a -n "$CONF_DATE_TO" ] && {
  check_date_interval "$CONF_DATE_FROM" "$CONF_DATE_TO"; errors=$(( $errors + $? ))
}

# Stop if there are any errors in the configuration.
[ "$errors" -gt 0 ] && die "$errors error(s) found in the configuration, aborting."
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
# fill up the logfiles array
logfiles_init

# Exit if there were no logfiles found. 
logfiles_is_empty && {
  log_stderr "No log files found."
  exit 1
}

# Check to see if we have from-date and to-date given in the configuration. If
# not, set it according to the dates we determined from the logfiles
[ -z "$CONF_DATE_FROM" ] && {
  CONF_DATE_FROM="$(logfiles_get_first_date)" || die "Cannot determine from-date."
  log_stderr "No from-date given, set to: \"$CONF_DATE_FROM\"."
}
[ -z "$CONF_DATE_TO" ] && {
  CONF_DATE_TO="$(logfiles_get_last_date)" || die "Cannot determine to-date."
  log_stderr "No to-date given, set to: \"$CONF_DATE_TO\"."
}

# Prune the array to contain only the logfiles for the dates we are interested
# in 
logfiles_prune "$CONF_DATE_FROM" "$CONF_DATE_TO" || die "Could not prune the logfiles array."

# Exit if there were no logfiles found that would match the criteria.
logfiles_is_empty && {
  log_stderr "Log files found, but none match the given criteria."
  exit 1
}

# Check for missing logfiles
missing_dates="$(logfiles_get_missing_dates)" || die "Could not check for missing dates."
[ -n "$missing_dates" ] && {
  die_or_warn "Logfiles for dates \"$missing_dates\" are missing."
}

# Check the sizes of the logfiles
logfiles_check_file_sizes || {
  die_or_warn "Some of the logfiles have zero size."
}

# Show the status of logfiles, depending on the mode we are in
if do_verbose; then
  logfiles_verbose_status
else
  logfiles_status
fi

exit 0
#}}}

# vim: set tabstop=2 shiftwidth=2 expandtab colorcolumn=80 foldmethod=marker foldcolumn=3 foldlevel=0:
