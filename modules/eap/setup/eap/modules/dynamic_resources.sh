#!/bin/sh

if [ "${SCRIPT_DEBUG}" = "true" ] ; then
    set -x
    echo "Script debugging is enabled, allowing bash commands and their arguments to be printed as they are executed"
fi

# For backward compatibility: CONTAINER_HEAP_PERCENT is old variable name
JAVA_MAX_MEM_RATIO=${JAVA_MAX_MEM_RATIO:-$(echo "${CONTAINER_HEAP_PERCENT:-0.5}" "100" | awk '{ printf "%d", $1 * $2 }')}
JAVA_INITIAL_MEM_RATIO=${JAVA_INITIAL_MEM_RATIO:-${INITIAL_HEAP_PERCENT:+$(echo "${INITIAL_HEAP_PERCENT}" "100" | awk '{ printf "%d", $1 * $2 }')}}

function source_java_run_scripts() {
    local java_scripts_dir="/opt/run-java"
    # set CONTAINER_MAX_MEMORY and CONTAINER_CORE_LIMIT
    source "${java_scripts_dir}/container-limits"
    # load java options functions
    source "${java_scripts_dir}/java-default-options"
}

source_java_run_scripts

# deprecated, left for backward compatibility
function get_heap_size {
    echo $(max_memory)
}

# deprecated, left for backward compatibility
get_initial_heap_size() {
    local max_heap="$1"
    echo "$max_heap" "${INITIAL_HEAP_PERCENT-1.0}" | awk '{ printf "%d", $1 * $2 }'
}

# deprecated, left for backward compatibility
adjust_java_heap_settings() {
    local java_scripts_dir="/opt/run-java"
    
    # nuke any hard-coded memory settings.  java-default-options won't add these
    # if they're already specified
    JAVA_OPTS="$(echo $JAVA_OPTS| sed -re 's/(-Xmx[^ ]*|-Xms[^ ]*)//g')"
    local java_options=$(source "${java_scripts_dir}/java-default-options")
    local max_heap=$(echo "${java_options}" | grep -Eo "\-Xmx[^ ]* ")
    local initial_heap=$(echo "${java_options}" | grep -Eo "\-Xms[^ ]* ")

    if [ -n "$max_heap" ]; then
        # CIAM-1394 correction
        JAVA_OPTS=$(echo $JAVA_OPTS | sed -e "s${AUS}-Xmx[^ ]*${AUS}${max_heap} ${AUS}")
        # EOF CIAM-1394 correction
    fi
    if [ -n "$initial_heap" ]; then
        # CIAM-1394 correction
        JAVA_OPTS=$(echo $JAVA_OPTS | sed -e "s${AUS}-Xms[^ ]* ${AUS}${initial_heap} ${AUS}")
        # EOF CIAM-1394 correction
    fi
}

# Returns a set of options that are not supported by the current jvm.  The idea
# is that java-default-options always configures settings for the latest jvm.
# That said, it is possible that the configuration won't map to previous
# versions of the jvm.  In those cases, it might be better to have different
# implementations of java-default-options for each version of the jvm (e.g. a
# private implementation that is sourced by java-default-options based on the
# jvm version).  This would allow for the defaults to be tuned for the version
# of the jvm being used.
unsupported_options() {
    if [[ $($JAVA_HOME/bin/java -version 2>&1 | awk -F "\"" '/version/{ print $2}') == *"1.7"* ]]; then
        echo "(-XX:NativeMemoryTracking=[^ ]*|-XX:+PrintGCDateStamps|-XX:+UnlockDiagnosticVMOptions|-XX:CICompilerCount=[^ ]*|-XX:GCTimeRatio=[^ ]*|-XX:MaxMetaspaceSize=[^ ]*|-XX:AdaptiveSizePolicyWeight=[^ ]*)"
    else
        echo "(--XX:MaxPermSize=[^ ]*)"
    fi
}

# Merge default java options into the passed argument
adjust_java_options() {
    local options="$@"
    local remove_xms
    local java_scripts_dir="/opt/run-java"
    # nuke any hard-coded memory settings.  java-default-options won't add these
    # if they're already specified
    JAVA_OPTS="$(echo $JAVA_OPTS| sed -re 's/(-Xmx[^ ]*|-Xms[^ ]*)//g')"
    local java_options=$(source "${java_scripts_dir}/java-default-options")
    local unsupported="$(unsupported_options)"
    for option in $java_options; do
        if [[ ${option} == "-Xmx"* ]]; then
            if [[ "$options" == *"-Xmx"* ]]; then
                # CIAM-1394 correction
                options=$(echo $options | sed -e "s${AUS}-Xmx[^ ]*${AUS}${option}${AUS}")
                # EOF CIAM-1394 correction
            else
                options="${options} ${option}"
            fi
            if [ "x$remove_xms" == "x" ]; then
                remove_xms=1
            fi
        elif [[ ${option} == "-Xms"* ]]; then
            if [[ "$options" == *"-Xms"* ]]; then
                # CIAM-1394 correction
                options=$(echo $options | sed -e "s${AUS}-Xms[^ ]*${AUS}${option}${AUS}")
                # EOF CIAM-1394 correction
            else
                options="${options} ${option}"
            fi
            remove_xms=0
        elif $(echo "$options" | grep -Eq -- "${option%=*}(=[^ ]*)?(\s|$)") ; then
            options=$(echo $options | sed -re "s@${option%=*}(=[^ ]*)?(\s|$)@${option}\2@")
        else
            options="${options} ${option}"
        fi
    done

    if [[ "x$remove_xms" == "x1" ]]; then
        options=$(echo $options | sed -e "s/-Xms[^ ]*/ /")
    fi

    options=$(echo "${options}"| sed -re "s@${unsupported}(\s)?@@g")
    echo "${options}"
}
