#!/usr/bin/perl

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

$project = $ARGV[0];
if (length("$project") == 0) {
  die("No project specified");
}
$bump = $ARGV[1];

$oldVersion = `grep "CURRENT_PROJECT_VERSION" "$project/project.pbxproj" | head -n 1`;
$start = index("$oldVersion", "CURRENT_PROJECT_VERSION = ");
$end = index("$oldVersion", ";");
if (($start >= 0) && ($end >= 0)) {
  $start += length("CURRENT_PROJECT_VERSION = ");
  $oldVersion = substr($oldVersion, $start, $end - $start);
} else {
  $oldVersion = "";
}

if ("$bump" eq "bump") {
  $index = index("$oldVersion", "a");
  if ($index < 0) {
    $index = index("$oldVersion", "b");
  }
  if ($index >= 0) {
    $value = substr($oldVersion, $index + 1);
    $value = $value + 1;
    $newVersion = substr($oldVersion, 0, $index + 1);
    $newVersion = "$newVersion$value";
    
    `/usr/bin/perl -p -e "s/$oldVersion/$newVersion/g" "$project/project.pbxproj" > "$project/project.pbxproj~"`;
    `/bin/mv -f "$project/project.pbxproj~" "$project/project.pbxproj"`;
    
    print("Project version incremented from '$oldVersion' to '$newVersion'\n");
  } else {
    print("Project version is not alpha or beta and cannot be incremented\n");
  }
} else {
  print("$oldVersion\n");
}
