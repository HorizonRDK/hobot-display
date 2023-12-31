#!/bin/bash
# set -x

PREFIX="cfg_section_"

function debug {
   if ! [ "x$BASH_INI_PARSER_DEBUG" == "x" ]; then
      echo
      echo --start-- $*
      echo "${ini[*]}"
      echo --end--
      echo
   fi
}

function cfg_parser {
   shopt -p extglob &>/dev/null
   CHANGE_EXTGLOB=$?
   if [ $CHANGE_EXTGLOB = 1 ]; then
      shopt -s extglob
   fi
   ini="$(<$1)"       # read the file
   ini=${ini//$'\r'/} # remove linefeed i.e dos2unix

   ini="${ini//[/\\[}"
   debug "escaped ["
   ini="${ini//]/\\]}"
   debug "escaped ]"
   OLDIFS="$IFS"
   IFS=$'\n' && ini=(${ini}) # convert to line-array
   debug
   ini=(${ini[*]/#*([[:space:]]);*/})
   debug "removed ; comments"
   ini=(${ini[*]/#*([[:space:]])\#*/})
   debug "removed # comments"
   ini=(${ini[*]/#+([[:space:]])/}) # remove init whitespace
   debug "removed initial whitespace"
   ini=(${ini[*]/%+([[:space:]])/}) # remove ending whitespace
   debug "removed ending whitespace"
   ini=(${ini[*]/%+([[:space:]])\\]/\\]}) # remove non meaningful whitespace after sections
   debug "removed whitespace after section name"
   if [ $BASH_VERSINFO == 3 ]; then
      ini=(${ini[*]/+([[:space:]])=/=})               # remove whitespace before =
      ini=(${ini[*]/=+([[:space:]])/=})               # remove whitespace after =
      ini=(${ini[*]/+([[:space:]])=+([[:space:]])/=}) # remove whitespace around =
   else
      ini=(${ini[*]/*([[:space:]])=*([[:space:]])/=}) # remove whitespace around =
   fi
   debug "removed space around ="
   ini=(${ini[*]/#\\[/\}$'\n'"$PREFIX"}) # set section prefix
   debug
   for ((i = 0; i < "${#ini[@]}"; i++)); do
      line="${ini[i]}"
      if [[ "$line" =~ $PREFIX.+ ]]; then
         ini[$i]=${line// /_}
      fi
   done
   debug "subsections"
   ini=(${ini[*]/%\\]/ \(}) # convert text2function (1)
   debug
   ini=(${ini[*]/=/=\( }) # convert item to array
   debug
   ini=(${ini[*]/%/ \)}) # close array parenthesis
   debug
   ini=(${ini[*]/%\\ \)/ \\}) # the multiline trick
   debug
   ini=(${ini[*]/%\( \)/\(\) \{}) # convert text2function (2)
   debug
   ini=(${ini[*]/%\} \)/\}})                                          # remove extra parenthesis
   ini=(${ini[*]/%\{/\{$'\n''cfg_unset ${FUNCNAME/#'$PREFIX'}'$'\n'}) # clean previous definition of section
   debug
   ini[0]="" # remove first element
   debug
   ini[${#ini[*]} + 1]='}' # add the last brace
   debug
   eval "$(echo "${ini[*]}")" # eval the result
   EVAL_STATUS=$?
   if [ $CHANGE_EXTGLOB = 1 ]; then
      shopt -u extglob
   fi
   IFS="$OLDIFS"
   return $EVAL_STATUS
}

function cfg_writer {
   local item fun newvar vars
   SECTION=$1
   OLDIFS="$IFS"
   IFS=' '$'\n'
   if [ -z "$SECTION" ]; then
      fun="$(declare -F)"
   else
      fun="$(declare -F $PREFIX$SECTION)"
      if [ -z "$fun" ]; then
         echo "section $SECTION not found" 1>&2
         exit 1
      fi
   fi
   fun="${fun//declare -f/}"
   for f in $fun; do
      [ "${f#$PREFIX}" == "${f}" ] && continue
      item="$(declare -f ${f})"
      item="${item##*\{}"                  # remove function definition
      item="${item##*FUNCNAME*$PREFIX\};}" # remove clear section
      item="${item/FUNCNAME\/#$PREFIX;/}"  # remove line
      item="${item/%\}/}"                  # remove function close
      item="${item%)*}"                    # remove everything after parenthesis
      item="${item});"                     # add close parenthesis
      vars=""
      while [ "$item" != "" ]; do
         newvar="${item%%=*}" # get item name
         vars="$vars$newvar"  # add name to collection
         item="${item#*;}"    # remove readed line
      done
      vars=$(echo "$vars" | sort -u) # remove duplication
      eval $f
      echo "[${f#$PREFIX}]" # output section
      for var in $vars; do
         eval 'local length=${#'$var'[*]}' # test if var is an array
         if [ $length == 1 ]; then
            echo $var=\"${!var}\" #output var
         else
            echo ";$var is an array"          # add comment denoting var is an array
            eval 'echo $var=\"${'$var'[*]}\"' # output array var
         fi
      done
   done
   IFS="$OLDIFS"
}

function cfg_unset {
   local item fun newvar vars
   SECTION=$1
   OLDIFS="$IFS"
   IFS=' '$'\n'
   if [ -z "$SECTION" ]; then
      fun="$(declare -F)"
   else
      fun="$(declare -F $PREFIX$SECTION)"
      if [ -z "$fun" ]; then
         echo "section $SECTION not found" 1>&2
         return
      fi
   fi
   fun="${fun//declare -f/}"
   for f in $fun; do
      [ "${f#$PREFIX}" == "${f}" ] && continue
      item="$(declare -f ${f})"
      item="${item##*\{}"                  # remove function definition
      item="${item##*FUNCNAME*$PREFIX\};}" # remove clear section
      item="${item/%\}/}"                  # remove function close
      item="${item%)*}"                    # remove everything after parenthesis
      item="${item});"                     # add close parenthesis
      vars=""
      while [ "$item" != "" ]; do
         newvar="${item%%=*}" # get item name
         vars="$vars $newvar" # add name to collection
         item="${item#*;}"    # remove readed line
      done
      for var in $vars; do
         unset $var
      done
   done
   IFS="$OLDIFS"
}

function cfg_clear {
   SECTION=$1
   OLDIFS="$IFS"
   IFS=' '$'\n'
   if [ -z "$SECTION" ]; then
      fun="$(declare -F)"
   else
      fun="$(declare -F $PREFIX$SECTION)"
      if [ -z "$fun" ]; then
         echo "section $SECTION not found" 1>&2
         exit 1
      fi
   fi
   fun="${fun//declare -f/}"
   for f in $fun; do
      [ "${f#$PREFIX}" == "${f}" ] && continue
      unset -f ${f}
   done
   IFS="$OLDIFS"
}

function cfg_update {
   SECTION=$1
   VAR=$2
   OLDIFS="$IFS"
   IFS=' '$'\n'
   fun="$(declare -F $PREFIX$SECTION)"
   if [ -z "$fun" ]; then
      echo "section $SECTION not found" 1>&2
      exit 1
   fi
   fun="${fun//declare -f/}"
   item="$(declare -f ${fun})"
   #item="${item##* $VAR=*}" # remove var declaration
   item="${item/%\}/}" # remove function close
   item="${item}
    $VAR=(${!VAR})
   "
   item="${item}
   }" # close function again

   eval "function $item"
}

# vim: filetype=sh

function auto_edid() {
   modes=$(get_edid_raw_data | edid-decode-linux-tv -X | grep "Modeline" | sed 's/^[ \t]*//g' | sed 's/.*/"&"/')
   if [ -z "$modes" ]; then
      #default timing genrate using https://tomverbeure.github.io/video_timings_calculator
      modes=("	Modeline \"1920x1080_30\" 74.25 1920 2008 2052 2200 1080 1084 1089 1125 +HSync +VSync
      Modeline \"1920x1080_60\" 148.5 1920 2008 2052 2200 1080 1084 1089 1125 +HSync +VSync
      Modeline \"1280x720_60\" 74.25 1280 1390 1430 1650 720 725 730 750 +HSync +VSync
      Modeline \"1280x720_30\" 74.25 1280 3040 3080 3300 720 725 730 750 +HSync +VSync
      Modeline \"1024x768_60\" 65 1024 1048 1184 1344 768 771 777 806 -HSync -VSync
      Modeline \"1024x768_30\" 25.932 1024 1032 1064 1104 768 769 777 783 +HSync -VSync
      Modeline \"800x600_60.32\" 40 800 840 968 1056 600 601 605 628 +HSync +VSync
      Modeline \"640x480_75\" 31.5 640 656 720 840 480 481 484 500 -HSync -VSync"

      )
   fi
   modes_array=()
   filtered_output=()

   template_monitor='
Section "Monitor"
    Identifier "default"
    #replace_1
EndSection
'

   while IFS= read -r line; do
      modes_array+=("$line")
   done <<<"$modes"

   while IFS= read -r line; do
      modes_array+=("$line")
   done < <(hobot_parse_std_timing)

   for item in "${modes_array[@]}"; do
      if [[ ! "$item" =~ "Interlace" ]]; then
         filtered_output+=("$item")
      fi
   done

   result=""
   for item in "${filtered_output[@]}"; do
      #echo $(echo "$item" | sed 's/^"\(.*\)"$/\1/')
      result="$result$(echo "$item" | sed 's/^"\(.*\)"$/\1/')"$'\n'
   done

   monitor_result="${template_monitor//#replace_1/$result}"

   echo "$monitor_result"

   template_screen='
Section "Screen"
    Identifier "MyScreen"
    Device "MyVideoCard" 
    Monitor "default" 
    DefaultDepth 24
    SubSection "Display"
        Modes #replace_2
    EndSubSection
EndSection'

   second_elements=()

   for sentence in "${filtered_output[@]}"; do
      if [[ "$sentence" != "#"* ]]; then
         second_element=$(echo "$sentence" | awk '{print $2}' | tr -d '"') 

         # 解析宽、高、刷新率
         width=$(echo "$second_element" | cut -d'x' -f1)
         height_refresh_rate=$(echo "$second_element" | cut -d'x' -f2)

         height=$(echo "$height_refresh_rate" | awk -F'_' '{print $1}')       
         refresh_rate=$(echo "$height_refresh_rate" | awk -F'_' '{print $2}')

         # 过滤条件
         if ((height <= 1080 && width <= 1920 )); then
            if [ -n "$second_element" ]; then
               second_elements+=("\"$second_element\"")
            fi
         fi
      fi
   done

   IFS=$'\n' sorted_second_elements=($(sort -t'x' -k1,1nr -k2,2nr <<<"${second_elements[*]}"))
   unset IFS

   modes_string="$(printf ' %s' "${sorted_second_elements[@]}")"

   result="${template_screen//#replace_2/$modes_string}"

   fbdev_temp='
Section "Device"
    Identifier "MyVideoCard"
    Driver "fbdev" # Framebuffer 驱动程序
        Option "fbdev" "/dev/fb0"
EndSection
'
   echo "$monitor_result" >/usr/share/X11/xorg.conf.d/01-monitor.conf
   echo "$fbdev_temp" >>/usr/share/X11/xorg.conf.d/01-monitor.conf
   echo "$result" >>/usr/share/X11/xorg.conf.d/01-monitor.conf
}
timing_params=""
function config_parse() {
   config_file="/boot/config.txt"
   if [ ! -f $config_file ]; then
      echo "File $config_file not exists"
      return
   fi
   cfg_parser $config_file
   cfg_section_display_timing
   timing_params="-h $hact -v $vact --hfp $hfp --hs $hs --hbp $hbp --vfp $vfp --vs $vs --vpb $vbp --clk $clk"
}
get_value_by_key() {
   file="$1"
   key="$2"

   if [ ! -f "$file" ]; then
      echo ""
      return 1
   fi

   value=$(grep "^$key=" "$file" | awk -F '=' '{print $2}')

   if [ -n "$value" ]; then
      echo "$value"
   else
      echo ""
      return 1
   fi
}

params="hobot_display_service"
server_mode=1
function cmd_line_parse() {

   display_mode=0 #0: BT1120,1: MIPI_DSI
   hdmi_auto=1    #0: Use custom timing, 1: Use EDID timing

   cmdline=$(cat /proc/cmdline)
   video_type=$(echo $cmdline | awk -F' ' '{ for (i=1; i<=NF; i++) { if ($i ~ /^video=/) { sub("video=", "", $i); print $i } } }')

   if [ -n "$video_type" ]; then
      echo $video_type
   else
      echo "video_type not found,using hdmi as default video_type"
      video_type="hdmi"
   fi

   if echo "$video_type" | grep -q "hdmi"; then
      echo "HDMI SCREEN"
      display_mode=0
   fi
   # TODO: Support HDMI using custom timing
   if echo "$video_type" | grep -q "mipi"; then
      echo "MIPI-DSI SCREEN"
      display_mode=1
      config_parse
   fi
   server_env="-s $server_mode"
   params="$params -a 1 -m $display_mode $timing_params $server_env"
}
display_manager=""

if [ -e "/etc/X11/default-display-manager" ]; then
   display_manager=$(basename $(cat /etc/X11/default-display-manager))
fi

config_file="/boot/config.txt"

if [ $? -eq 0 ] && [ -n "$display_manager" ] && [ "$(systemctl get-default)" == "graphical.target" ]; then
   auto_edid
   echo desktop >/sys/devices/virtual/graphics/iar_cdev/iar_test_attr
   server_mode=0
else
   echo "Server mode!"
   server_mode=1
fi

cmd_line_parse
if [ $server_mode == 1 ]; then
   fb_width=$(get_value_by_key $config_file "fb_console_width")
   fb_height=$(get_value_by_key $config_file "fb_console_height")
   fb_refresh_rate=$(get_value_by_key $config_file "fb_console_refresh_rate")
   if [ -z "$fb_width" ] || [ -z "$fb_height" ] || [ -z "$fb_refresh_rate" ]; then
      params="$params"
   else
      echo desktop >/sys/devices/virtual/graphics/iar_cdev/iar_test_attr
      params="$params -a 1 -m $display_mode $timing_params $server_env --fb_width $fb_width --fb_height $fb_height -r $fb_refresh_rate"
   fi
fi
echo $params
$params
# config_parse

# auto_edid
