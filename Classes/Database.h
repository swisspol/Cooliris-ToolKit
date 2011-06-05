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

#import <Foundation/Foundation.h>
#ifndef NDEBUG
#import <libkern/OSAtomic.h>
#endif

typedef long DatabaseSQLRowID;
typedef struct DatabaseSQLColumnDefinition* DatabaseSQLColumn;
typedef struct DatabaseSQLTableDefinition* DatabaseSQLTable;

typedef enum {
  kDatabaseSQLColumnType_Invalid = 0,
  kDatabaseSQLColumnType_Int,
  kDatabaseSQLColumnType_Double,
  kDatabaseSQLColumnType_String,
  kDatabaseSQLColumnType_URL,
  kDatabaseSQLColumnType_Date,
  kDatabaseSQLColumnType_Data
} DatabaseSQLColumnType;

enum {
  kDatabaseSQLColumnOptionsNone = 0,
  kDatabaseSQLColumnOption_Unique = (1 << 0),
  kDatabaseSQLColumnOption_NotNull = (1 << 1),  // Object properties only
  kDatabaseSQLColumnOption_CaseInsensitive_ASCII = (1 << 2),  // String or URL properties only
  kDatabaseSQLColumnOption_CaseInsensitive_UTF8 = (1 << 3)  // String or URL properties only
};
typedef NSUInteger DatabaseSQLColumnOptions;

@interface DatabaseObject : NSObject {
@private
  DatabaseSQLTable __table;
  DatabaseSQLRowID __rowID;
  void* __storage;
  BOOL __modified;
}
@property(nonatomic, readonly) DatabaseSQLTable sqlTable;
@property(nonatomic, readonly) DatabaseSQLRowID sqlRowID;  // Always > 0 if in database
@property(nonatomic, readonly, getter=wasModified) BOOL modified;  // Returns YES if any property was modified since last fetch for existing objects or since creation for new objects
- (id) initWithSQLTable:(DatabaseSQLTable)table;  // Receiver class must match table class
@end

// Bridging of DatabaseObject subclasses to SQL tables
// Non-dynamic properties are ignored
// Properties can be "readonly" to indicate they never update the database
// Scalar and object properties must be "nonatomic"
// Object properties must have "copy" semantic unless "readonly"
// Supported scalar property types are: int, double
// Supported object property types are: NSString, NSURL, NSDate, NSData
// Be aware that setting an NSData property to an empty NSData is equivalent to setting it to nil in the database
// Note that object properties are automatically released on -dealloc
@interface DatabaseObject (ObjCBridge)
+ (NSString*) sqlTableName;  // Default implementation returns class name - Return nil for an abstract DatabaseObject subclass
+ (NSString*) sqlColumnNameForProperty:(NSString*)property;  // Default implementation returns "property"
+ (DatabaseSQLColumnOptions) sqlColumnOptionsForProperty:(NSString*)property;  // Default is kDatabaseSQLColumnOptionsNone
+ (NSString*) sqlTableFetchOrder;  // Default is nil

// To be called on subclasses only
+ (DatabaseSQLTable) sqlTable;
+ (DatabaseSQLColumn) sqlColumnForProperty:(NSString*)property;
- (void) setValue:(id)value forProperty:(NSString*)property;
- (id) valueForProperty:(NSString*)property;
@end

// Native SQL access
@interface DatabaseObject (SQL)
- (void) setInt:(int)value forSQLColumn:(DatabaseSQLColumn)column;
- (void) setDouble:(double)value forSQLColumn:(DatabaseSQLColumn)column;
- (void) setObject:(id)object forSQLColumn:(DatabaseSQLColumn)column;
- (int) intForSQLColumn:(DatabaseSQLColumn)column;
- (double) doubleForSQLColumn:(DatabaseSQLColumn)column;
- (id) objectForSQLColumn:(DatabaseSQLColumn)column;
@end

// Connections are not thread-safe and must be used on no more than one thread at a time
// Use class keys for optimal performance
@interface DatabaseConnection : NSObject {
@private
  void* _database;
  CFMutableDictionaryRef _statements;
#ifndef NDEBUG
  OSSpinLock _lock;
#endif
}
- (id) initWithDatabaseAtPath:(NSString*)path;  // Requires database to have been initialized
- (BOOL) beginTransaction;  // Nestable
- (BOOL) commitTransaction;  // Nestable
- (BOOL) rollbackTransaction;  // Rolls back current transaction
- (BOOL) refetchObject:(DatabaseObject*)object;  // Return NO on error or if object is not in database
- (BOOL) insertObject:(DatabaseObject*)object;
- (BOOL) updateObject:(DatabaseObject*)object;
- (BOOL) deleteObject:(DatabaseObject*)object;
- (BOOL) vacuum;
- (NSArray*) executeRawSQLStatement:(NSString*)sql;  // Returns nil on error or an NSArray of NSDictionaries
- (BOOL) executeRawSQLStatements:(NSString*)sql;
@end

// Bridging of DatabaseObject subclasses to SQL tables
@interface DatabaseConnection (ObjCBridge)
+ (NSString*) defaultDatabasePath;
+ (DatabaseConnection*) defaultDatabaseConnection;  // Initializes and uses the database at +defaultDatabasePath for all subclasses of DatabaseObject
+ (BOOL) initializeDatabaseAtPath:(NSString*)path;  // Uses all subclasses of DatabaseObject
+ (BOOL) initializeDatabaseAtPath:(NSString*)path usingObjectClasses:(NSSet*)classes extraSQLStatements:(NSString*)sql;  // Can be called safely on an already initialized database
- (NSUInteger) countObjectsOfClass:(Class)class;  // Returns 0 on error or if none
- (NSUInteger) countObjectsOfClass:(Class)class withProperty:(NSString*)property matchingValue:(id)value;  // Returns 0 on error or if none
- (NSArray*) fetchAllObjectsOfClass:(Class)class;  // Returns nil on error
- (BOOL) hasObjectOfClass:(Class)class withSQLRowID:(DatabaseSQLRowID)rowID;  // Returns NO on error or if none - Faster than fetching the object
- (id) fetchObjectOfClass:(Class)class withSQLRowID:(DatabaseSQLRowID)rowID;  // Returns nil on error or if none
- (id) fetchObjectOfClass:(Class)class withUniqueProperty:(NSString*)property matchingValue:(id)value;  // Returns nil on error or if none
- (NSArray*) fetchObjectsOfClass:(Class)class withProperty:(NSString*)property matchingValue:(id)value;  // Returns nil on error
- (NSArray*) fetchObjectsOfClass:(Class)class withSQLWhereClause:(NSString*)clause;  // Returns nil on error
- (BOOL) deleteAllObjectsOfClass:(Class)class;
- (BOOL) deleteObjectOfClass:(Class)class withSQLRowID:(DatabaseSQLRowID)rowID;
- (BOOL) deleteObjectsOfClass:(Class)class withProperty:(NSString*)property matchingValue:(id)value;  // Returns NO on error or if none
@end

// SQL column definition
@interface DatabaseSchemaColumn : NSObject {
@private
  NSString* _name;
  DatabaseSQLColumnType _type;
  DatabaseSQLColumnOptions _options;
  DatabaseSQLColumn _column;
}
@property(nonatomic, readonly) NSString* name;
@property(nonatomic, readonly) DatabaseSQLColumnType type;
@property(nonatomic, readonly) DatabaseSQLColumnOptions options;
@property(nonatomic, readonly) DatabaseSQLColumn sqlColumn;  // Only valid after DatabaseSchemaTable initialization
- (id) initWithName:(NSString*)name type:(DatabaseSQLColumnType)type options:(DatabaseSQLColumnOptions)options;
@end

// SQL table definition
@interface DatabaseSchemaTable : NSObject {
@private
  NSString* _name;
  NSString* _order;
  NSMutableArray* _columns;
  Class _class;
  DatabaseSQLTable _table;
}
@property(nonatomic, readonly) NSString* name;
@property(nonatomic, readonly) NSString* fetchOrder;
@property(nonatomic, readonly) NSArray* columns;
@property(nonatomic, readonly) Class objectClass;
@property(nonatomic, readonly) DatabaseSQLTable sqlTable;
+ (DatabaseSchemaTable*) schemaTableFromObjectClass:(Class)class;
- (id) initWithName:(NSString*)name fetchOrder:(NSString*)order columns:(NSArray*)columns;  // Uses DatabaseObject class
- (id) initWithObjectClass:(Class)class name:(NSString*)name fetchOrder:(NSString*)order extraColumns:(NSArray*)columns;  // Table will inherit all property columns from object class
@end

// Native SQL access
@interface DatabaseConnection (SQL)
+ (BOOL) initializeDatabaseAtPath:(NSString*)path usingSchema:(NSSet*)schema extraSQLStatements:(NSString*)sql;  // Can be called safely on an already initialized database
- (NSUInteger) countObjectsInSQLTable:(DatabaseSQLTable)table;  // Returns 0 on error or if none
- (NSUInteger) countObjectsInSQLTable:(DatabaseSQLTable)table withSQLColumn:(DatabaseSQLColumn)column matchingValue:(id)value;  // Returns 0 on error or if none
- (NSArray*) fetchAllObjectsInSQLTable:(DatabaseSQLTable)table;  // Returns nil on error
- (BOOL) hasObjectInSQLTable:(DatabaseSQLTable)table withSQLRowID:(DatabaseSQLRowID)rowID;  // Returns NO on error or if none - Faster than fetching the object
- (id) fetchObjectInSQLTable:(DatabaseSQLTable)table withSQLRowID:(DatabaseSQLRowID)rowID;  // Returns nil on error or if none
- (id) fetchObjectInSQLTable:(DatabaseSQLTable)table withUniqueSQLColumn:(DatabaseSQLColumn)column matchingValue:(id)value;  // Returns nil on error or if none
- (NSArray*) fetchObjectsInSQLTable:(DatabaseSQLTable)table withSQLColumn:(DatabaseSQLColumn)column matchingValue:(id)value;  // Returns nil on error
- (NSArray*) fetchObjectsInSQLTable:(DatabaseSQLTable)table withSQLWhereClause:(NSString*)clause;  // Returns nil on error
- (BOOL) deleteAllObjectsInSQLTable:(DatabaseSQLTable)table;
- (BOOL) deleteObjectInSQLTable:(DatabaseSQLTable)table withSQLRowID:(DatabaseSQLRowID)rowID;
- (BOOL) deleteObjectsInSQLTable:(DatabaseSQLTable)table withSQLColumn:(DatabaseSQLColumn)column matchingValue:(id)value;  // Returns NO on error or if none
@end

// Thread-safe pool of database connections
@interface DatabaseConnectionPool : NSObject {
@private
  NSString* _path;
  NSMutableSet* _pool;
  NSLock* _lock;
}
- (id) initWithDatabasePath:(NSString*)path;
- (DatabaseConnection*) retrieveNewConnection;
- (void) recycleUsedConnection:(DatabaseConnection*)connection;
- (void) purge;  // Destroy all unused connections
@end
