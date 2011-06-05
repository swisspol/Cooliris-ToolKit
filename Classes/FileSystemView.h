// Copyright 2011 Cooliris, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import "GridView.h"

// Subclasses GridView and items become paths relative to a base path
// If "basePath" is not nil and is a directory path, "items" are set automatically as relative paths for its contents
// If "basePath" is nil, "items" must be set manually as absolute paths
// FileSystemView also overrides -defaultViewForItem: to return a valid default view
@interface FileSystemView : GridView {
@private
  NSString* _basePath;
  BOOL _showHidden;
}
@property(nonatomic, copy) NSString* basePath;
@property(nonatomic) BOOL showHiddenItems;  // NO by default
@end
