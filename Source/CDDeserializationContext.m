//
//  CDDeserializationContext.m
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

#import "CDDeserializationContext.h"
#import "CDSerializationPrivate.h"

@interface CDDeserializationContext ()

@property (strong, nonatomic) NSManagedObjectContext *context;
@property (strong, nonatomic) NSDictionary *availableEntities;

@property (strong, nonatomic) NSArray *topReferences;
@property (strong, nonatomic) NSDictionary *serializedObjects;
@property (strong, nonatomic) NSMutableDictionary *deserializedObjects;

@end

@implementation CDDeserializationContext

#pragma mark - Init -
+ (instancetype)contextWithManagedObjectContext:(NSManagedObjectContext *)context {
    return [[[self class] alloc] initWithManagedObjectContext:context];
}

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)context {
    self = [super init];
    if (self) {
        _context             = context;
        _availableEntities   = [context.persistentStoreCoordinator.managedObjectModel entitiesByName];
        _deserializedObjects = [NSMutableDictionary new];
    }
    return self;
}

- (void)dealloc {
    
}

#pragma mark - Setters -
- (void)setSerializedContents:(NSDictionary *)serializedContents {
    if (serializedContents.count > 0) {
        _topReferences     = serializedContents[CDSerializationTopReferences];
        _serializedObjects = serializedContents[CDSerializationReferences];
    }
}

- (void)setSerializedContentsWithJSON:(NSData *)jsonData error:(NSError **)error {
    if (jsonData.length > 0) {
        id json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:error];
        if (!json && error) {
            NSLog(@"Failed to deserialize json data in context: %@", (*error).localizedDescription);
        }
        self.serializedContents = json;
    }
}

- (void)setSerializedContentsWithPropertyList:(NSData *)plistData error:(NSError **)error {
    if (plistData.length > 0) {
        id plist = [NSPropertyListSerialization propertyListWithData:plistData options:0 format:NULL error:error];
        if (!plist && error) {
            NSLog(@"Failed to deserialize property list in context: %@", (*error).localizedDescription);
        }
        self.serializedContents = plist;
    }
}

#pragma mark - Actions -
- (NSSet *)deserialize {
    
    /* -----------------------------------------
     * If the references dictionary doesn't have
     * any objects, we have no data to work with.
     */
    if (_serializedObjects.count < 1 || _topReferences.count < 1) {
        return nil;
    }
    
    /* -------------------------------------------
     * Check to see if the model contains entities
     * that would be available for deserialization.
     */
    if (_availableEntities.count < 1) {
        return nil;
    }
    
    /* ----------------------------------------
     * Inform the delegate that deserialization
     * will commence shortly.
     */
    if ([_delegate respondsToSelector:@selector(deserializationContextWillBeginDeserializing:)]) {
        [_delegate deserializationContextWillBeginDeserializing:self];
    }
    
    /* ----------------------------------------
     * Run through all top level objects and
     * recursively deserialize their children.
     */
    NSMutableSet *topLevelObjects = [NSMutableSet new];
    for (NSString *reference in _topReferences) {
        
        NSManagedObject *deserializedObject = [self deserializedValueForObject:reference type:NSObjectIDAttributeType];
        [topLevelObjects addObject:deserializedObject];
    }
    
    /* ----------------------------------------
     * Inform the delegate that deserialization
     * has finished.
     */
    if ([_delegate respondsToSelector:@selector(deserializationContextDidFinishDeserializing:)]) {
        [_delegate deserializationContextDidFinishDeserializing:self];
    }
    
    if (topLevelObjects.count > 0) {
        return [topLevelObjects copy];
    }
    return nil;
}

#pragma mark - Deserialization -
- (id)deserializedValueForObject:(id)object type:(NSAttributeType)type {
    
    switch (type) {
        case NSObjectIDAttributeType: {
            return [self deserializedManagedObjectForReference:object];
        } break;
            
        case NSInteger16AttributeType:
        case NSInteger32AttributeType:
        case NSInteger64AttributeType:
        case NSDecimalAttributeType:
        case NSDoubleAttributeType:
        case NSFloatAttributeType:
        case NSBooleanAttributeType:
        case NSStringAttributeType: {
            
            /* -----------------------------------------
             * Strings and numbers can always be wrapped
             * in NSString or NSNumber, therefore all of
             * the above don't need to converted.
             */
            return object;
            
        } break;
            
            
        case NSDateAttributeType: {
            return [NSDate dateWithTimeIntervalSince1970:[object doubleValue]];
        } break;
            
        case NSBinaryDataAttributeType: {
            return [[NSData alloc] initWithBase64EncodedString:object options:0];
        } break;
            
        case NSTransformableAttributeType: {
            NSData *data = [[NSData alloc] initWithBase64EncodedString:object options:NSDataBase64DecodingIgnoreUnknownCharacters];
            return [NSKeyedUnarchiver unarchiveObjectWithData:data];
        } break;
            
        case NSUndefinedAttributeType: {
            return nil;
        } break;
    }
}

- (id)deserializedValueForCollection:(id<NSFastEnumeration>)collection ordered:(BOOL)ordered type:(NSAttributeType)type {
    
    Class containerClass = (ordered) ? [NSMutableOrderedSet class] : [NSMutableSet class];
    id container         = [[containerClass alloc] init];
    
    if ([container respondsToSelector:@selector(addObject:)]) {
        for (id object in collection) {
            [container addObject:[self deserializedValueForObject:object type:type]];
        }
    }
    
    if ([container count] > 0) {
        return container;
    }
    return nil;
}

- (NSManagedObject *)deserializedManagedObjectForReference:(NSString *)reference {
    if (reference) {
        
        /* --------------------------------------------
         * Check the stored deserialized objects if
         * this object already exists. This effectively
         * infinite loops due to recursive calls to
         * deserialization methods.
         */
        NSManagedObject *object = _deserializedObjects[reference];
        if (!object) {
        
            /* -----------------------------------------------
             * Obtain the obejct wrapper which is a dictionary
             * with keys for entity name and property values.
             */
            NSDictionary *objectWrapper = _serializedObjects[reference];
            if (objectWrapper) {
                
                NSString *entityName        = objectWrapper[CDObjectEntityKey];
                NSDictionary *properties    = objectWrapper[CDObjectPropertiesKey];
                
                /* --------------------------------------------
                 * Check to see that the current model actually
                 * has an entity with this name, since the model
                 * could have changed between import / export.
                 */
                NSEntityDescription *entity = _availableEntities[entityName];
                if (entity && properties.count > 0) {

                    /* --------------------------------------
                     * Insert a new managed object into the
                     * managed object context provided during
                     * initialization, and insert it into the
                     * deserialized collection. Any children
                     * referencing the parent will be able to
                     * grab this object without cause infinite
                     * recursion.
                     */
                    object = [NSEntityDescription insertNewObjectForEntityForName:entityName inManagedObjectContext:_context];
                    if (object) {
                        _deserializedObjects[reference] = object;
                    }
                    
                    /* --------------------------------------------
                     * Obtain a list of properties of the current 
                     * entity. We'll need those to reference object 
                     * class names and relationship types when 
                     * inserting property values.
                     */
                    NSDictionary *propertyDescriptions = [entity propertiesByName];
                    
                    /* ------------------------------------------
                     * Enumerate serialized properties. A value
                     * can be either a regular non-managed object
                     * or a relationship of various types: to-one,
                     * to-many, is-ordered, etc.
                     */
                    [properties enumerateKeysAndObjectsUsingBlock:^(NSString *property, id serializedValue, BOOL *stop) {
                        
                        id deserializedValue = nil;
                        id description       = propertyDescriptions[property];
                        if ([description isKindOfClass:[NSAttributeDescription class]]) {
                            
                            deserializedValue = [self deserializedValueForObject:serializedValue type:[description attributeType]];
                            
                        } else if ([description isKindOfClass:[NSRelationshipDescription class]]) {
                            
                            BOOL toMany = [description isToMany];
                            if (!toMany) {
                                deserializedValue = [self deserializedValueForObject:serializedValue type:NSObjectIDAttributeType];
                            } else {
                                deserializedValue = [self deserializedValueForCollection:serializedValue ordered:[description isOrdered] type:NSObjectIDAttributeType];
                            }
                        }
                        
                        [object setValue:deserializedValue forKey:property];
                    }];
                }
            }
        }
        return object;
    }
    return nil;
}

@end
