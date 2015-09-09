# CDSerialization
A simple, non-intrusive library for recursively serializing CoreData object-graphs to JSON and property lists.

### Installation
`CDSerialization` is provided as a module (introduced in iOS 8), so installation is as simple as adding this project as a dependency, linking the product framework and adding a "Copy Files" build phase to copy over the framework to be linked at runtime.

### Usage
`CDSerialization` provides a `serialization` and a `deserialization` context for each operation. It's important to note that after the object graph has been serialized or deserialized once, all objects will be cached for the lifetime of the respective context. Future calls to serialize or deserialize will be virtually *free*. Only new objects added will incur any cost.

### Serialization
To serialize an object graph, we'll need to instantiate a `CDSerializationContext`, add some objects, and perform the work.

```objc
NSManagedObject *object = [self fetchManagedObject];

CDSerializationContext *context = [CDSerializationContext context];
[context addManagedObject:company];

// Serialize into a basic NSDictionary
NSDictionary *dictionary = [context serialize];

// Serialize into JSON data
NSData *json = [context serializedJSON:NSJSONWritingPrettyPrinted error:nil];

// Serialize into property list data
NSData *plist = [context serializedPropertyList:NSPropertyListXMLFormat_v1_0 error:nil];
```
### Deserialization
To deserialize an object graph, we'll need to instantiate a `CDDeserializationContext` and pass in a valid `NSManagedObjectContext`. The managed object context will act as a container for all objects created during the deserialization process.

```objc
NSManagedObjectContext *context = [self obtainCurrentContext];

CDDeserializationContext *context = [CDDeserializationContext contextWithManagedObjectContext:context];

// Deserialize a plain NSDictionary
[context setSerializedContents:dictionary];

// Deserialize JSON data
[context setSerializedContentsWithJSON:json error:nil];

// Deserialize property list data
[context setSerializedContentsWithPropertyList:plist error:nil];

NSSet *managedObjects = [context deserialize];
```
Deserialization will return an `NSSet` of all deserialized objects of type `NSManagedObject`. It is not necessary to do anything further with this set.

### Delegates
Both contexts provide a way for delegates to be part of the serialization & deserialization process. Assigning a delegate to a context grants delegates the ability to respond to `will` and `did` serialize / deserialize events.
