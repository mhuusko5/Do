# Do!

[![](http://img.shields.io/badge/OS%20X-10.9%2B-blue.svg)]() [![](http://img.shields.io/badge/iOS-7.0%2B-blue.svg)]() [![](http://img.shields.io/badge/Swift-1.2 | 2.0-blue.svg)]() [![](https://img.shields.io/badge/CocoaPods-compatible-4BC51D.svg)](https://github.com/CocoaPods/CocoaPods) [![](http://img.shields.io/badge/Hackery-partially guilty-red.svg)]()

#### A Swift-er way to do [GCD](https://developer.apple.com/library/prerelease/ios/documentation/Performance/Reference/GCD_libdispatch_Ref/index.html)-related things.

## Installation

### CocoaPods

```ruby
pod 'Do' # Latest Swift compatible

pod 'Do/2.0' # Swift 2.0 compatible

pod 'Do/1.2' # Swift 1.2 compatible
```

### Manual

Drag Do-[Swift version].swift into your project.

## Usage

### Contents

- [Queues](#queues) (access to global queues, and current queue checking)
- [Sync](#sync) (deadlock safe `dispatch_sync`/`dispatch_barrier_sync` with return values)
- [Loop](#loop) (deadlock safe `dispatch_apply` with range version)
- [After](#after) (cancellable `dispatch_after`)
- [Concurrent](#concurrent) (simple way to have async operations with a limit to how many can concurrently process)
- [Once](#once) (hackery-enabled succinct `dispatch_once`)
- [Throttle](#throttle) (hackery-enabled succinct throttling)
- [Async](#async) (convenience functions related to `dispatch_async`)

### Queues ###

***Do!*** provides easy access to the main queue, global priority queues, as well as the global 'quality of service' queues available in `OS X 10.10` and `iOS 8.0` and later (with appropriate fallbacks in place).

```swift
Do.mainQueue // The "main" dispatch queue.

Do.highPriorityQueue // The global "high priority" dispatch queue.

Do.defaultQueue // The global "default" dispatch queue.

Do.lowPriorityQueue // The global "low priority" dispatch queue.

Do.backgroundQueue // The global "background" dispatch queue.

Do.userInteractiveQueue // The global "user interactive" (super high priority?) dispatch queue.

Do.userInitiatedQueue // The global "user initiated" (equivalent to "high priority") dispatch queue.

Do.utilityQueue // The global "utility" (equivalent to "low priority") dispatch queue.
```

***Do!*** also provides a way to check whether you are currently dispatched on a specific queue by comparing labels (give your queues labels!).

```swift
if Do.isCurrentQueue(mainQueue) {
    print("Hello from the main queue!")
}
```
### Sync

***Do!*** provides a wrapper around `dispatch_sync` and `dispatch_barrier_sync` that is succinct and deadlock safe (well, *more* deadlock safe – it uses `Do.isCurrentQueue` to avoid this, but that only helps if you try to dispatch to the current queue, not one higher up in the dispatch tree).

```swift
Do.sync(someSerialQueue) {
    print("Hello world!")
}
```

```swift
Do.barrierSync(someConcurrentQueue) {
    print("Hello world!")
}
```

More importantly, ***Do!*** provides versions which returns values, which is perfect for synchronizing access to resources...

```swift
let resource: Resource = Do.sync(someSerialQueue) {
    // .. heavy work that should happen serially...
    
    return importantResource
}
```

```swift
let resource: Resource = Do.barrierSync(someConcurrentQueue) {
    // .. heavy work that should block queue...
    
    return importantResource
}
```

.. or even synchronizing properties.

```swift
class Variable {
    private var _value: Any
    
    var value: Any {
        get { return barrierSync(someConcurrentQueue) { self._value } }
        set { barrierSync(someConcurrentQueue) { self._value = newValue } }
    }
}
```

### Loop

***Do!*** provides a wrapper around `dispatch_apply` that is succinct and deadlock safe (again, *more* deadlock safe). If the targetted queue is the current dispatch queue (or nil), it reverts to a plain loop.

```swift
Do.loop(100, highPriorityQueue) { i in
    print(i)
}
```

```swift
Do.loop(10) { i in
    print(i)
}
```

***Do!*** also provides a version which takes a range instead of an iterations count.

```swift
Do.loop(15..<55, highPriorityQueue) { i in
    print(i)
}
```

### After

***Do!*** provides a wrapper around `dispatch_after` that is succinct, defaults to the main queue, and returns a block for cancellation of the scheduled dispatch.

```swift
Do.after(3.0) {
    print("Hello world!")
}
```

```swift
Do.after(0.5, backgroundQueue) {
    print("Hello world!")
}
```

```swift
let cancel = Do.after(10) {
    print("Hello world!")
}

Do.after(2) {
    cancel()
}
```

### Concurrent

***Do!*** provides a simple but powerful mechanism for dispatching async operations (which might have async/nested dispatches themselves) that can be limited to processing sequentially or N at a time.

```swift
static token = Do.ConcurrentToken() // store this somewhere!

// ...

for i in 0..<100 {
    Do.concurrent(token, highPriorityQueue) { done in
        // some heavy stuff...

        done()
    }
}

// the 100 operations will process one at a time...
```

```swift
static token = Do.ConcurrentToken(limit: 5)

for i in 0..<50 {
    Do.concurrent(token, mainQueue) { done in
        Do.after(0.5) {
            done()        
        }
    }
    
    Do.concurrent(token, backgroundQueue) { done in
        Do.after(1.0) {
            done()        
        }
    }
}

// the 100 operations (with different logic/queues) will process 5 at a time
```

### Once

***Do!*** provides an uber-succinct wrapper around `dispatch_once` (using hackery.. so beware, it works/is stable, but is not guaranteed to be the most performant solution).

```swift
Do.once {
    print("Hello world!")
}
```

***Do!*** also provides a version which stores the result of the initial dispatch, and simply returns the value on all subsequent dispatches (again, hackery).

```swift
for i in 0..<10 {
    let message: String = Do.once {
        print("Some lazy/heavy stuff that should only happen once ;)")
        
        return "Hello world!"
    }
    
    print(message)
}
```

### Throttle

***Do!*** provides an uber-succinct way to dispatch a block a max of once per N seconds (again, hackery).

```swift
Do.throttle(3.4) {
    print("Hello world!")
}
```

```swift
Do.throttle(0.5, backgroundQueue) {
    print("Hello world!")
}
```

### Async

***Do!*** provides a wrapper around `dispatch_async` that is succinct, and convenient. That's it really, though. For added features (e.g. chaining) I recommend [Async](https://github.com/duemunk/Async) by [duemunk](https://github.com/duemunk).

```swift
Do.async(userInitiatedQueue) {}
```

```swift
Do.barrierAsync(userInitiatedQueue) {}
```

```swift
let group = dispatch_group_create()

Do.groupAsync(group, userInitiatedQueue) {}

Do.barrierGroupAsync(group, userInitiatedQueue) {}
```

```swift
Do.main {}

Do.background {}

Do.userInteractive {}

Do.userInitiated {}
```
