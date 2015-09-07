//
//  CDSerializationContext.m
//
//  Copyright (c) 2015 Dima Bart
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  1. Redistributions of source code must retain the above copyright notice, this
//  list of conditions and the following disclaimer.
//  2. Redistributions in binary form must reproduce the above copyright notice,
//  this list of conditions and the following disclaimer in the documentation
//  and/or other materials provided with the distribution.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
//  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
//  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
//  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
//  ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
//  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
//   LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
//  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
//  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
//  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
//  The views and conclusions contained in the software and documentation are those
//  of the authors and should not be interpreted as representing official policies,
//  either expressed or implied, of the FreeBSD Project.

#import "CDSerializationContext.h"
#import "CDSerializationPrivate.h"

@interface CDSerializationContext ()

@property (strong, nonatomic) NSManagedObjectContext *context;
@property (strong, nonatomic) NSMutableSet *objectSet;

@property (strong, nonatomic) NSMutableDictionary *serializedObjects;
@property (strong, nonatomic) NSMapTable *serializedReferences;

@end

@implementation CDSerializationContext

#pragma mark - Init -
+ (instancetype)context {
    return [[[self class] alloc] init];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [_CDSerializationInitializer class];
        
        _objectSet            = [NSMutableSet new];
        _serializedObjects    = [NSMutableDictionary new];
        _serializedReferences = [NSMapTable strongToStrongObjectsMapTable];
    }
    return self;
}

- (void)dealloc {
    
}

#pragma mark - Adding / Removing -
- (void)addManagedObject:(NSManagedObject *)object {
    [_objectSet addObject:object];
}

- (void)addManagedObjects:(NSArray *)objects {
    [_objectSet addObjectsFromArray:objects];
}

- (void)removeManagedObject:(NSManagedObject *)object {
    [_objectSet removeObject:object];
}

- (void)removeManagedObjects:(NSArray *)objects {
    for (NSManagedObject *object in objects) {
        [self removeManagedObject:object];
    }
}

#pragma mark - Actions -
- (NSDictionary *)serialize {
    
    /* ------------------------------------------
     * Check if there is any objects to serialize
     * and avoid doing any extra work if it's not
     * required.
     */
    if (_objectSet.count < 1) {
        return nil;
    }
    
    /* ----------------------------------------
     * Inform the delegate that serialization
     * will commence shortly.
     */
    if ([_delegate respondsToSelector:@selector(serializationContextWillBeginSerializing:)]) {
        [_delegate serializationContextWillBeginSerializing:self];
    }
    
    /* ----------------------------------------
     * Run through all the added object, those
     * will become the top level objects. All
     * referenced children will be serialized
     * as a reference.
     */
    NSMutableArray *topLevelReferences = [NSMutableArray new];
    for (NSManagedObject *object in _objectSet) {
        
        id value = [self serializedValueForObject:object];
        if (value) {
            [topLevelReferences addObject:value];
        }
    }
    
    /* ----------------------------------------
     * Inform the delegate that serialization
     * has finished.
     */
    if ([_delegate respondsToSelector:@selector(serializationContextDidFinishSerializing:)]) {
        [_delegate serializationContextDidFinishSerializing:self];
    }
    
    /* ----------------------------------------
     * Serialized object is always a dictionary
     * with keys that contain top-level objects
     * as an array and a dictionary of type 
     * <referce : object>
     */
    return @{
             CDSerializationTopReferences : topLevelReferences,
             CDSerializationReferences    : _serializedObjects,
             };
}

- (NSData *)serializedJSON:(NSJSONWritingOptions)options error:(NSError *__autoreleasing *)error {
    NSDictionary *contents = [self serialize];
    if (contents.count > 0) {
        
        NSData *json = [NSJSONSerialization dataWithJSONObject:contents options:options error:error];
        if (!json && error) {
            NSLog(@"Failed to serialize JSON from managed objects: %@", (*error).localizedDescription);
        }
        return json;
    }
    return nil;
}

- (NSData *)serializedPropertyList:(NSPropertyListFormat)format error:(NSError *__autoreleasing *)error {
    NSDictionary *contents = [self serialize];
    if (contents.count > 0) {
        
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:contents format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
        if (!data && error) {
            NSLog(@"Failed to serialize property list from managed objects: %@", (*error).localizedDescription);
        }
        return data;
    }
    return nil;
}

#pragma mark - Serialization -
- (id)serializedValueForObject:(id)object {
    
    if ([object isKindOfClass:CDClassManagedObject]) {
        return [self serializedReferenceForManagedObject:object];
        
    } else if ([object isKindOfClass:CDClassString] || [object isKindOfClass:CDClassNumber]) {
        return object;
        
    } else if ([object isKindOfClass:CDClassDate]) {
        return @([(NSDate *)object timeIntervalSince1970]);
        
    } else if ([object isKindOfClass:CDClassData]) {
        return [(NSData *)object base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
        
    } else {
        return nil;
    }
}

- (NSArray *)serializedValueForCollection:(id<NSFastEnumeration>)collection {
    
    NSMutableArray *container = [NSMutableArray new];
    for (id object in collection) {
        
        id value = [self serializedValueForObject:object];
        if (value) {
            [container addObject:value];
        }
    }
    
    if (container.count > 0) {
        return container;
    }
    return nil;
}

- (NSString *)serializedReferenceForManagedObject:(NSManagedObject *)object {
    
    /* ----------------------------------------
     * Check to see if the object has already
     * been serialized. If so, we should have a
     * reference to its serialized counterpart.
     */
    NSString *objectReference = [_serializedReferences objectForKey:object];
    if (!objectReference) {
        
        /* --------------------------------------------
         * If there's no reference we have to serialize
         * the object. Before we do that, however, we'll
         * populate the reference so that any children
         * can safely reference the parent (this object).
         */
        objectReference = [[NSUUID UUID] UUIDString];
        [_serializedReferences setObject:objectReference forKey:object];
        
        /* ------------------------------------------
         * After creating a new reference, we can
         * begin the serialization. We'll then create
         * a container dictionary to store the entity
         * name and all properties.
         */
        NSMutableDictionary *properties = [NSMutableDictionary new];
        [[object.entity propertiesByName] enumerateKeysAndObjectsUsingBlock:^(NSString *property, id description, BOOL *stop) {
            
            /* --------------------------------------
             * If the property value is an attribute,
             * we'll treat as a regular non-managed
             * object. Otherwise, we're dealing with
             * a relationship which can be a to-many
             * or to-one.
             */
            id deserializedValue = [object valueForKey:property];
            id serializedValue   = nil;
            if ([description isKindOfClass:[NSAttributeDescription class]]) {
                
                serializedValue = [self serializedValueForObject:deserializedValue];
                
            } else if ([description isKindOfClass:[NSRelationshipDescription class]]) {
                
                BOOL toMany = [description isToMany];
                if (!toMany) {
                    serializedValue = [self serializedValueForObject:deserializedValue];
                } else {
                    serializedValue = [self serializedValueForCollection:deserializedValue];
                }
            }
            
            /* ----------------------------------------
             * Only set the value if we have it. If an
             * attribute or relationship retuns nil, we
             * will just ignore it.
             */
            if (serializedValue) {
                properties[property] = serializedValue;
            }
        }];
        
        NSDictionary *representation = @{
                                         CDObjectEntityKey     : object.entity.name,
                                         CDObjectPropertiesKey : properties,
                                         };
        [_serializedObjects setObject:representation forKey:objectReference];
    }
    return objectReference;
}

@end
