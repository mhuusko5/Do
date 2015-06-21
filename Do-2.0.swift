//
//  Do.swift
//  Do
//

import Foundation

// MARK: - Concurrent -

/**
    Asynchronously dispatches 'block' on 'queue' if number of concurrent operations in progress with same 'token' is less than 'token.limit', else enqueues operation. TL;DR: Only 'token.limit' number of operations will ever be in progress at a time.

    Usage:

        static token = Do.ConcurrentToken(limit: 1)

        // ...

        Do.loop(0..<100) {
            Do.concurrent(token, highPriorityQueue) { done in
                // some heavy stuff...

                done()
            }

            Do.concurrent(token, backgroundQueue) { done in
                Do.after(0.5) {
                    done()
                }
            }
        }

        // because 'token.limit' is '1', the 200 operations (with different work/logic, and on different queues) will process one at a time... simple!
*/
public func concurrent(token: ConcurrentToken, _ queue: dispatch_queue_t, _ block: ConcurrentBlock) {
    func dispatch() {
        if token.executingCount < token.limit {
            token.executingCount++
            
            async(queue) {
                block {
                    barrierAsync(synchQueue) {
                        if --token.executingCount < token.limit && token.queuedOperations.count > 0 {
                            let operation = token.queuedOperations.removeAtIndex(0)
                            
                            concurrent(token, operation.queue, operation.block)
                        }
                    }
                }
            }
        } else {
            token.queuedOperations.append(queue: queue, block: block)
        }
    }
    
    isCurrentQueue(queue) ? dispatch() : barrierAsync(synchQueue, dispatch)
}

public typealias ConcurrentBlock = (done: () -> Void) -> Void

public class ConcurrentToken {
    public let limit: Int
    
    private var executingCount = 0
    private var queuedOperations = [(queue: dispatch_queue_t, block: ConcurrentBlock)]()
    
    public init(limit: Int = 1) {
        self.limit = limit
    }
}

// MARK: - Throttle; Once (very convenient hacks, but not necessarily performant) -

/**
    Dispatches 'block' (async on 'queue', if provided) maximum of once per 'seconds'.

    Usage:

        Do.throttle(3.4) {
            print("Hello world!")
        }
*/
public func throttle(seconds: Double, _ queue: dispatch_queue_t? = nil, _ file: String = __FILE__, _ line: Int = __LINE__, _ column: Int = __COLUMN__, _ function: String = __FUNCTION__, _ block: dispatch_block_t) {
    let key = "\(file).\(line).\(column).\(function)"
    
    let throttled: Bool = barrierSync(synchQueue) {
        let lastCall = StaticVariable(type: NSDate.self, key: "\(key).lastCall")
        
        if lastCall.value == nil || lastCall.value!.timeIntervalSinceNow <= -seconds {
            lastCall.value = NSDate()
            
            return false
        }
        
        return true
    }
    
    if !throttled {
        queue == nil || isCurrentQueue(queue!) ? block() : async(queue!, block)
    }
}

/**
    Dispatches 'block' only once.

    Usage:

        Do.once { print("Hello world!") }
*/
public func once(file: String = __FILE__, _ line: Int = __LINE__, _ column: Int = __COLUMN__, _ function: String = __FUNCTION__, _ block: dispatch_block_t) {
    let key = "\(file).\(line).\(column).\(function)"
    
    barrierSync(synchQueue) {
        let onceToken = StaticVariable(value: dispatch_once_t(), key: "\(key).onceToken")
        
        dispatch_once(&onceToken.value!, block)
    }
}

/**
    Dispatches 'block' only once, but stores/always returns result of the initial dispatch.

    Usage:

        for i in 0..<10 {
            let message: String = Do.once {
                print("Some lazy/heavy stuff that should only happen once ;)")
                
                return "Hello world!"
            }
            
            print(message)
        }
*/
public func once<T>(file: String = __FILE__, _ line: Int = __LINE__, _ column: Int = __COLUMN__, _ function: String = __FUNCTION__, _ block: () -> T) -> T {
    let key = "\(file).\(line).\(column).\(function)"
    
    return barrierSync(synchQueue) {
        let returnValue = StaticVariable(type: T.self, key: "\(key).returnValue")
        
        let onceToken = StaticVariable(value: dispatch_once_t(), key: "\(key).onceToken")
        dispatch_once(&onceToken.value!) {
            returnValue.value = block()
        }
        
        return returnValue.value!
    }
}

// MARK: - Sync (deadlock safe; with return value versions) -

/// Synchronously dispatches 'block' on 'queue'.
public func sync(queue: dispatch_queue_t, _ block: dispatch_block_t) {
    isCurrentQueue(queue) ? block() : dispatch_sync(queue, block)
}

/**
    Synchronously dispatches 'block' on 'queue' and returns result.

    Usage:

        let resource: Resource = Do.sync(highPriorityQueue) {
            return self.importantResource
        }
*/
public func sync<T>(queue: dispatch_queue_t, _ block: () -> T) -> T {
    var returnValue: T?
    
    sync(queue) {
        returnValue = block()
    }
    
    return returnValue!
}

/// Synchronously (waiting for/blocking other "barrier" calls) dispatches 'block' on 'queue'.
public func barrierSync(queue: dispatch_queue_t, _ block: dispatch_block_t) {
    isCurrentQueue(queue) ? block() : dispatch_barrier_sync(queue, block)
}

/** 
    Synchronously (waiting for/blocking other "barrier" calls) dispatches 'block' on 'queue' and returns result.

    Usage:

        let resource: Resource = Do.barrierSync(highPriorityQueue) {
            return self.importantResource
        }
*/
public func barrierSync<T>(queue: dispatch_queue_t, _ block: () -> T) -> T {
    var returnValue: T?
    
    barrierSync(queue) {
        returnValue = block()
    }
    
    return returnValue!
}

// MARK: - Loop/"apply" (deadlock safe; with range version) -

/**
    Synchronously dispatches 'block' on 'queue' for 'times' iterations, passing index.
    Reverts to plain loop if 'queue' is nil or if currently on 'queue'.

    Usage:

        Do.loop(4, backgroundQueue) { i in
            print(i)
        }
*/
public func loop(times: Int, _ queue: dispatch_queue_t? = nil, _ block: (Int) -> Void) {
    if queue == nil || isCurrentQueue(queue!) {
        for i in 0..<times {
            block(i)
        }
    } else {
        dispatch_apply(times, queue, block)
    }
}

/**
    Synchronously dispatches 'block' on 'queue' for iterations in 'range', passing index.
    Reverts to plain loop if 'queue' is nil or if currently on 'queue'.

    Usage:

        Do.loop(2..<12, backgroundQueue) { i in
            print(i)
        }
*/
public func loop(range: Range<Int>, _ queue: dispatch_queue_t? = nil, _ block: (Int) -> Void) {
    loop(range.endIndex - range.startIndex, queue) { i in
        block(range.startIndex + i)
    }
}

// MARK: - After (with returned cancel block) -

/**
    Schedules 'block' to be dispatched on 'queue' (defaults to "main" queue) after 'seconds'.

    :returns: Block to call to cancel the scheduled dispatch.

    Usage:

        let cancel = Do.after(3.0) {
            print("Hello world!")
        }

        cancel()
*/
public func after(seconds: Double, _ queue: dispatch_queue_t = mainQueue, _ block: dispatch_block_t) -> () -> Void {
    var cancelled = false
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(seconds * Double(NSEC_PER_SEC))), queue) {
        if !barrierSync(synchQueue, { cancelled }) {
            block()
        }
    }
    
    return {
        barrierAsync(synchQueue) { cancelled = true }
    }
}

// MARK: - Async (with convenience queue functions) -

/// Asynchronously dispatches 'block' on 'queue'.
public func async(queue: dispatch_queue_t, _ block: dispatch_block_t) {
    dispatch_async(queue, block)
}

/// Asynchronously (waiting for/blocking other "barrier" calls) dispatches 'block' on 'queue'.
public func barrierAsync(queue: dispatch_queue_t, _ block: dispatch_block_t) {
    dispatch_barrier_async(queue, block)
}

/// Asynchronously dispatches 'block' on 'queue' in 'group'.
public func groupAsync(group: dispatch_group_t, _ queue: dispatch_queue_t, _ block: dispatch_block_t) {
    dispatch_group_async(group, queue, block)
}

/// Asynchronously (waiting for/blocking other "barrier" calls) dispatches 'block' on 'queue' in 'group'.
public func barrierGroupAsync(group: dispatch_group_t, _ queue: dispatch_queue_t, _ block: dispatch_block_t) {
    dispatch_group_enter(group)
    
    barrierAsync(queue) {
        block()
        
        dispatch_group_leave(group)
    }
}

/// Asynchronously dispatches 'block' on the "main" queue.
public func main(block: dispatch_block_t) {
    async(mainQueue, block)
}

/// Asynchronously dispatches 'block' on the global "background" queue.
public func background(block: dispatch_block_t) {
    async(backgroundQueue, block)
}

/// Asynchronously dispatches 'block' on the global "user interactive" queue.
public func userInteractive(block: dispatch_block_t) {
    async(userInteractiveQueue, block)
}

/// Asynchronously dispatches 'block' on the global "user initiated" queue.
public func userInitiated(block: dispatch_block_t) {
    async(userInitiatedQueue, block)
}

// MARK: - Queues -

/// Checks whether 'queue' is the current dispatch queue.
public func isCurrentQueue(queue: dispatch_queue_t) -> Bool {
    return strcmp(dispatch_queue_get_label(queue), dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL)) == 0
}

/// The "main" dispatch queue.
public var mainQueue: dispatch_queue_t {
    return dispatch_get_main_queue()
}

/// The global "high priority" dispatch queue.
public var highPriorityQueue: dispatch_queue_t {
    return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)
}

/// The global "default" dispatch queue.
public var defaultQueue: dispatch_queue_t {
    if #available(OSX 10.10, iOS 8.0, *) {
        return dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0)
    } else {
        return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
    }
}

/// The global "low priority" dispatch queue.
public var lowPriorityQueue: dispatch_queue_t {
    return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0)
}

/// The global "background" dispatch queue.
public var backgroundQueue: dispatch_queue_t {
    if #available(OSX 10.10, iOS 8.0, *) {
        return dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0)
    } else {
        return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)
    }
}

/** 
    The global "user interactive" (super high priority?) dispatch queue.
    Falls back to "high priority" dispatch queue for < OSX 10.10/iOS 8.0.
*/
public var userInteractiveQueue: dispatch_queue_t {
    if #available(OSX 10.10, iOS 8.0, *) {
        return dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0)
    } else {
        return highPriorityQueue
    }
}

/// The global "user initiated" (equivalent to "high priority") dispatch queue.
public var userInitiatedQueue: dispatch_queue_t {
    if #available(OSX 10.10, iOS 8.0, *) {
        return dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)
    } else {
        return highPriorityQueue
    }
}

/// The global "utility" (equivalent to "low priority") dispatch queue.
public var utilityQueue: dispatch_queue_t {
    if #available(OSX 10.10, iOS 8.0, *) {
        return dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)
    } else {
        return lowPriorityQueue
    }
}

// MARK: - Private -

private let synchQueue = dispatch_queue_create("com.mhuusko5.Do.Synch", DISPATCH_QUEUE_CONCURRENT)

private var staticVariables = [String: Any]()

private func StaticVariable<T>(@autoclosure(escaping) value: () -> T? = nil, type: T.Type = T.self, key: String) -> Variable<T> {
    return barrierSync(synchQueue) {
        var variable = staticVariables[key]
        
        if variable == nil {
            variable = Variable<T>(value())
            staticVariables[key] = variable
        }
        
        return variable as! Variable<T>
    }
}

private class Variable<T> {
    var value: T? {
        get {
            return barrierSync(synchQueue) {
                if let typedValue = self._value as? T? {
                    return typedValue
                } else {
                    return unsafeBitCast(self._value, Optional<T>.self)
                }
            }
        }
        set {
            barrierSync(synchQueue) { self._value = newValue }
        }
    }
    
    var _value: Any?
    
    init(_ value: Any?) {
        _value = value
    }
}