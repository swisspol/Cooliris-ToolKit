#!/bin/sh

# Copyright 2011 Cooliris, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#
# Run this shell script from an Xcode script phase to patch the Info.plist and InfoPlist.strings files:
# * "__NAME__" is replaced by "$PRODUCT_NAME" from Xcode build settings,
# * "__VERSION__" is replaced by "$CURRENT_PROJECT_VERSION" from Xcode build settings
# * "__REVISION__" is replaced by the current SVN revision
#

# Get and populate variables (NAME, VERSION, REVISION).
SCRIPT_DIRECTORY=`dirname "$0"`
source "${SCRIPT_DIRECTORY}/GetBuildInfo.sh"

# Patch Info.plist
PATH="${CONFIGURATION_BUILD_DIR}/${INFOPLIST_PATH}"
if [ "$INFOPLIST_OUTPUT_FORMAT" == "binary" ]
then
  /usr/bin/plutil -convert xml1 "$PATH"
fi
/usr/bin/perl -p -e "s/__NAME__/$NAME/g;s/__VERSION__/$VERSION/g;s/__REVISION__/$REVISION/g" "$PATH" > "$PATH~"
/bin/mv "$PATH~" "$PATH"
if [ "$INFOPLIST_OUTPUT_FORMAT" == "binary" ]
then
  /usr/bin/plutil -convert binary1 "$PATH"
fi

# Patch Language.lproj/InfoPlist.strings if they exist
if [ -d "${CONFIGURATION_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}" ]
then
  cd "${CONFIGURATION_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
  for LANGUAGE in *.lproj;
  do
    PATH="$LANGUAGE${INFOSTRINGS_PATH}"
    if [ -e "$PATH" ]
    then
      if [ "$INFOPLIST_OUTPUT_FORMAT" == "binary" ]
      then
        /usr/bin/plutil -convert xml1 "$PATH"
      else
        /usr/bin/textutil -format txt -inputencoding UTF-16 -convert txt -encoding UTF-8 "$PATH" -output "$PATH"
      fi
      /usr/bin/perl -p -e "s/__NAME__/$NAME/g;s/__VERSION__/$VERSION/g;s/__REVISION__/$REVISION/g" "$PATH" > "$PATH~"
      /bin/mv "$PATH~" "$PATH"
      if [ "$INFOPLIST_OUTPUT_FORMAT" == "binary" ]
      then
        /usr/bin/plutil -convert binary1 "$PATH"
      else
        /usr/bin/textutil -format txt -inputencoding UTF-8 -convert txt -encoding UTF-16 "$PATH" -output "$PATH"
      fi
    fi
  done
fi
