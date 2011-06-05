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

BRANCH="//depot/dev/..."
if type p4 &> /dev/null
then
  export P4CONFIG=.p4config
  REVISION=`p4 changes -m1 "${BRANCH}" | awk '{ print $2 }'`
  echo "${REVISION}"
else
  echo "p4 tool is not installed on this system or not in ${PATH}"
  exit 1
fi
