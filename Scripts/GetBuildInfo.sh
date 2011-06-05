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
# Called by other scripts to populate NAME, VERSION, and REVISION.
#

# Retrieve SCM revision
DIRECTORY=`dirname "$0"`
REVISION=""
if [ -d ".svn" ]
then
  REVISION=`$DIRECTORY/SVNRevision.pl`
elif [ -d ".hg" ]
then
  REVISION=`$DIRECTORY/MercurialRevision.sh`
elif [ -d ".git" ]
then
  REVISION=`$DIRECTORY/GitTag.sh`
else
  REVISION=`"$DIRECTORY/P4Changeset.sh"`
fi
if [[ $? -ne 0 ]]
then
  REVISION=""
fi
if [ "$REVISION" == "" ]
then
  if [ "$CONFIGURATION" != "Debug" ]
  then
    echo "Unable to retrieve SCM revision which is required to tag non-Debug builds with"
    exit 1
  else
    REVISION="0"
  fi
fi

# Retrieve product name and version
NAME="$PRODUCT_NAME"
VERSION="$CURRENT_PROJECT_VERSION"
