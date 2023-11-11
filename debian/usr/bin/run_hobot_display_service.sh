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

function get_edid_from_userspace() {
   i2c_bus=5        # bus num
   i2c_address=0x3B # devices address
   edid_length=128  # EDID data length

   # 写入配置寄存器
   i2cset -y -f $i2c_bus $i2c_address 0xff 0x85
   i2cset -y -f $i2c_bus $i2c_address 0x03 0xC9
   i2cset -y -f $i2c_bus $i2c_address 0x04 0xA0
   i2cset -y -f $i2c_bus $i2c_address 0x05 0x00
   i2cset -y -f $i2c_bus $i2c_address 0x06 0x20
   i2cset -y -f $i2c_bus $i2c_address 0x14 0x7F

   declare -a edid_data

   for ((i = 0; i < 8; i++)); do
      i2cset -y -f $i2c_bus $i2c_address 0x05 $((i * 32))
      i2cset -y -f $i2c_bus $i2c_address 0x07 0x36
      i2cset -y -f $i2c_bus $i2c_address 0x07 0x34
      i2cset -y -f $i2c_bus $i2c_address 0x07 0x37
      sleep 0.005

      data=$(i2cget -y -f $i2c_bus $i2c_address 0x40)
      if (((data & 0x02) != 0)); then
         data=$(i2cget -y -f $i2c_bus $i2c_address 0x40)
         if (((data & 0x50) != 0)); then
            echo "read edid failed: no ack"
            echo "read edid failed: no ack"
         else
            # read
            for ((j = 0; j < 32; j++)); do
               data=$(i2cget -y -f $i2c_bus $i2c_address 0x83)
               if [[ -n "$data" ]]; then
                  edid_data+=($data)
               fi

               if ((i == 3 && j == 30)); then
                  extended_flag=$((${edid_data[i * 32 + j]} & 0x03))
               fi
            done

            if ((i == 3 && extended_flag < 1)); then
               i2cset -y -f $i2c_bus $i2c_address 0x03 0xc2
               i2cset -y -f $i2c_bus $i2c_address 0x07 0x1f
               break
            fi
         fi
      fi
   done

   i2cset -y -f $i2c_bus $i2c_address 0x03 0xc2
   i2cset -y -f $i2c_bus $i2c_address 0x07 0x1f

   # echo data
   for ((i = 0; i < ${#edid_data[@]}; i++)); do
      echo -n "0x$(printf '%02X' ${edid_data[i]}) "

      if (((i + 1) % 16 == 0)); then
         echo
      fi
   done
}

function auto_edid() {
   modes=$(get_edid_raw_data | edid-decode-linux-tv -X | grep "Modeline" | sed 's/^[ \t]*//g' | sed 's/.*/"&"/')
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

      second_element=$(echo "$sentence" | awk '{print $2}')

      second_elements+=("$second_element")
   done

   modes_string="$(printf ' %s' "${second_elements[@]}")"

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
   config_file="/boot/config/config.txt"
   if [ ! -f $config_file ]; then
      echo "File $config_file not exists"
      return
   fi
   cfg_parser $config_file
   cfg_section_display_timing
   timing_params="-h $hact -v $vact --hfp $hfp --hs $hs --hbp $hbp --vfp $vfp --vs $vs --vpb $vbp --clk $clk"
}

params="hobot_display_service"
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

   params="$params -a 1 -m $display_mode $timing_params"
   echo $params
}
auto_edid
cmd_line_parse
$($params)





# config_parse

# auto_edid