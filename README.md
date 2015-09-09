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

### Result
So what's the result? Essentially, what you'll get after serializing a `CoreData` object graph is a dictionary with two keys for: 
  1. Top level objects
  2. Object references

```json
{
  "CDSerializationTopReferences" : [
    "D5B3A1A4-F68E-4E9A-9DAA-F9324207FC97"
  ],
  "CDSerializationReferences" : {
    "4B6BD7E8-3183-4E66-900C-AA406E384701" : { "property" : "value" },
    "BAAFE914-FE15-4023-83DB-8E8CFA2D104C" : { "property" : "value" },
    "2BDF35A8-0883-42E3-8D38-D034AFCA89ED" : { "property" : "value" },
    "33EB804B-6DCD-4F8C-BB2C-E4BEAB7D3EAA" : { "property" : "value" },
    "9FC1BAF2-529D-4A03-B521-24C1B3FD9153" : { "property" : "value" },
    "2E6E4110-78FE-41EC-802A-8038048154F7" : { "property" : "value" },
    "E0B93135-7B0F-44BF-8294-E9E823F18325" : { "property" : "value" },
    "045704C1-AABE-4659-9273-92EA224C3BEA" : { "property" : "value" },
    "D5B3A1A4-F68E-4E9A-9DAA-F9324207FC97" : { "property" : "value" },
    "09F26566-1D53-4271-8080-3A259F29E837" : { "property" : "value" },
    "45AE3400-22AB-40B8-91E3-BC1F69788FD1" : { "property" : "value" },
    "672167EB-8104-41BC-BC0B-FDD740E9CCBA" : { "property" : "value" },
    "379F4C76-243E-4732-9874-1622C24BCD84" : { "property" : "value" },
    "45DF3E88-5355-495C-8FA0-E3244B76978B" : { "property" : "value" },
    "AAAD66EB-1D0A-44C7-821D-F66E96D1ACFC" : { "property" : "value" },
    "FDF35E28-B726-4088-B611-1EF6CDF100D6" : { "property" : "value" },
    "C751526F-798B-4DAA-9161-D7D4B58968DD" : { "property" : "value" },
    "58BA362C-7423-436B-822A-D0F9E8399D54" : { "property" : "value" },
    "13D9F39B-F466-407B-AEDF-9AE88F0D014C" : { "property" : "value" }
  }
}
```
`CDSerializationTopReferences` represents the objects added directly to the context and are simply a pointer into the global object table. `CDSerializationReferences` provides the global object table and includes all objects that are recursively derived from the top level object fed into the context.

### Delegates
Both contexts provide a way for delegates to be part of the serialization & deserialization process. Assigning a delegate to a context grants delegates the ability to respond to `will` and `did` serialize / deserialize events.

### Limitations
  - as of right now, it's an all or nothing deal, which means that you can't serialize individual objects in isolation, unless the object has no relationships.
  - no way to prevent duplicate imports, monitor the process of inserting deserialized objects into the managed object context
  
The limitations above will likely be addressed some time in the future.
