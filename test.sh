#!/usr/bin/env bash

CONFIG=bspi.config
LATEST_IMG='http://192.168.1.190/2020-08-20-raspios-buster-armhf-lite.zip'

set_config_var() {
  lua - "$1" "$2" "$3" <<EOF > "$3.bak"
local key=assert(arg[1])
local value=assert(arg[2])
local fn=assert(arg[3])
local file=assert(io.open(fn))
local made_change=false
for line in file:lines() do
  if line:match("^#?%s*"..key.."=.*$") then
    line=key.."="..value
    made_change=true
  end
  print(line)
end
if not made_change then
  print(key.."="..value)
end
EOF
mv "$3.bak" "$3"
}

clear_config_var() {
  lua - "$1" "$2" <<EOF > "$2.bak"
local key=assert(arg[1])
local fn=assert(arg[2])
local file=assert(io.open(fn))
for line in file:lines() do
  if line:match("^%s*"..key.."=.*$") then
    line="#"..line
  end
  print(line)
end
EOF
mv "$2.bak" "$2"
}

get_config_var() {
  lua - "$1" "$2" <<EOF
local key=assert(arg[1])
local fn=assert(arg[2])
local file=assert(io.open(fn))
local found=false
for line in file:lines() do
  local val = line:match("^%s*"..key.."=(.*)$")
  if (val ~= nil) then
    print(val)
    found=true
    break
  end
end
if not found then
   print(0)
end
EOF
}

# load config from file or defaults
ZIP_IMG_URL=$(get_config_var zipimgurl $CONFIG)
if [ -z $ZIP_IMG_URL ] || [ $ZIP_IMG_URL -eq 0 ]; then
  ZIP_IMG_URL=$LATEST_IMG
fi

set_config_var zipimgurl $ZIP_IMG_URL $CONFIG


echo $ZIP_IMG_URL
