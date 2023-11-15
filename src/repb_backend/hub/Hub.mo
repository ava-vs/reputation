import Array "mo:base/Array";
import Blob "mo:base/Blob";
import HashMap "mo:base/HashMap";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Order "mo:base/Order";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Text "mo:base/Text";

import E "./EventTypes";
import Types "./Types";

actor class Hub() {
    type EventField = Types.EventField;

    type Event = Types.Event;

    type EventFilter = Types.EventFilter;

    type RemoteCallEndpoint = Types.RemoteCallEndpoint;

    type EncodedEventBatch = Types.EncodedEventBatch;

    type FilterListenersPair = {
        filter : EventFilter;
        listeners : [RemoteCallEndpoint];
    };

    type Subscriber = Types.Subscriber;

    type EventName = E.EventName;

    // For further batch handling
    var batchMakingDurationNano : Int = 1_000_000_000;
    var batchMaxSizeBytes : Nat = 500_000;

    var listeners : [FilterListenersPair] = [];

    var eventHub = {
        var events : [E.Event] = [];
        subscribers : HashMap.HashMap<Principal, Subscriber> = HashMap.HashMap<Principal, Subscriber>(10, Principal.equal, Principal.hash);
    };

    // for TrieSet
    // func compareEventFields(field1 : EventField, field2 : EventField) : Order.Order {
    //     if (field1.name < field2.name) {
    //         return #less;
    //     } else if (field1.name > field2.name) {
    //         return #greater;
    //     } else {
    //         if (field1.value < field2.value) {
    //             return #less;
    //         } else if (field1.value > field2.value) {
    //             return #greater;
    //         } else {
    //             return #equal;
    //         };
    //     };
    // };

    // func equalEventFilters(filter1 : EventFilter, filter2 : EventFilter) : Bool {
    //     let sortedFilter1 = Array.sort(filter1, compareEventFields);
    //     let sortedFilter2 = Array.sort(filter2, compareEventFields);

    //     return Array.equal<EventField>(
    //         sortedFilter1,
    //         sortedFilter2,
    //         func(field1, field2) {
    //             field1.name == field2.name and field1.value == field2.value
    //         },
    //     );
    // };

    public func subscribe(subscriber : Subscriber) : async () {
        let principal = subscriber.callback;
        //TODO check the subscriber for the required methods
        eventHub.subscribers.put(principal, subscriber);
    };

    public func unsubscribe(principal : Principal) : async () {
        eventHub.subscribers.delete(principal);
    };

    public func emitEvent(event : E.Event) : async [Subscriber] {
        eventHub.events := Array.append(eventHub.events, [event]);

        let subscribersArray = Iter.toArray(eventHub.subscribers.vals());

        for (subscriber in eventHub.subscribers.vals()) {
            // TODO check subscriber
            if (isEventMatchFilter(event, subscriber.filter)) {
                ignore await sendEvent(event, subscriber.callback);
            };

        };

        return subscribersArray;
    };

    // func mappingEventDaoEvent(eventDao : EventDAO) : E.Event {
    //     switch (eventDao.eventType) {
    //         case (#CreateEvent) {
    //             let ev : E.Events = ?#CreateEvent;
    //             let result : E.Event = {
    //                 eventType = ev;
    //                 topics = eventDao.topics;
    //             };
    //         };
    //         case (_) {
    //             let result : E.Event = {
    //                 eventType = null;
    //                 topics = eventDao.topics;
    //             };
    //         };
    //     };

    // };

    func isEventMatchFilter(event : E.Event, filter : EventFilter) : Bool {
        switch (filter.eventType) {
            case (null) {};
            case (?t) if (t != event.eventType) { return false };
        };

        for (field in filter.fieldFilters.vals()) {
            let found = Array.find<EventField>(
                event.topics,
                func(topic : EventField) : Bool {
                    topic.name == field.name and topic.value == field.value
                },
            );
            if (found == null) {
                return false;
            };
        };

        return true;
    };

    func sendEvent(event : E.Event, canisterId : Principal) : async Result.Result<[(Text, Text)], Text> {
        let subscriber_canister_id = Principal.toText(canisterId);

        switch (event.eventType) {
            case (#CreateEvent(_)) {
                let canister : E.CreateEvent = actor (subscriber_canister_id);
                await canister.creation(event);
            };
            case (#BurnEvent(_)) {
                let canister : E.BurnEvent = actor (subscriber_canister_id);
                await canister.burn(event);
            };
            // TODO Add other types here
            case _ {
                return #err("Unknown Event Type");
            };
        };
    };

    // public func addEventListener(filter : EventFilter, endpoint : RemoteCallEndpoint) : async () {
    //     let existingPair = Array.find<FilterListenersPair>(
    //         listeners,
    //         func(pair) {
    //             equalEventFilters(pair.filter, filter);
    //         },
    //     );

    //     switch (existingPair) {
    //         case (?pair) {
    //             let updatedListeners = Array.append(pair.listeners, [endpoint]);
    //             let updatedPair = {
    //                 filter = filter;
    //                 listeners = updatedListeners;
    //             };
    //             let newListenersPairs = Array.map<FilterListenersPair, FilterListenersPair>(
    //                 listeners,
    //                 func(p) {
    //                     if (equalEventFilters(p.filter, pair.filter)) {
    //                         updatedPair;
    //                     } else { p };
    //                 },
    //             );
    //             listeners := newListenersPairs;
    //         };
    //         case null {
    //             listeners := Array.append(listeners, [{ filter = filter; listeners = [endpoint] }]);
    //         };
    //     };
    // };

    // public func removeEventListener(filter : EventFilter, endpoint : RemoteCallEndpoint) : async () {
    //     listeners := Array.filter<FilterListenersPair>(
    //         listeners,
    //         func(pair : FilterListenersPair) : Bool {
    //             if (equalEventFilters(pair.filter, filter)) {
    //                 let newListeners = Array.filter<RemoteCallEndpoint>(
    //                     pair.listeners,
    //                     func(ep : RemoteCallEndpoint) : Bool {
    //                         ep.canisterId != endpoint.canisterId or ep.methodName != endpoint.methodName;
    //                     },
    //                 );
    //                 return Array.size(newListeners) > 0;
    //             } else {
    //                 return true;
    //             };
    //         },
    //     );
    // };

    // public func emitEvent(event : Event) : async () {
    //     let tasks = Array.map(
    //         eventHub.subscribers.vals(),
    //         func(subscriber : Subscriber) : async () {
    //             if (isEventMatchFilter(event, subscriber.filter)) {
    //                 ignore await sendEvent(event, subscriber.callback);
    //             };
    //         },
    //     );
    //     await Async.par(parallel_calls);
    // };

    // func sendEvent(event : Event, canisterId : Principal) : async Result.Result<[(Text, Text)], Text> {
    //     let subscriber_canister_id = Principal.toText(canisterId);
    //     switch (event.topics) {
    //         case (#CreateEvent(createActor)) {
    //             let canister = actor (subscriber_canister_id);
    //             await canister.creation(event);
    //         };
    //         case (#BurnEvent) {
    //             let canister : E.BurnEvent = actor (subscriber_canister_id);
    //             await canister.burn(event);
    //         };
    //         case _ {
    //             return #err("Unknown Event Type");
    //         };
    //     };
    // };

    // func isEventMatchFilter(event : Event, filter : EventFilter) : Bool {
    //     for (field in filter.vals()) {
    //         if (Array.find<EventField>(event.topics, func(topic) { topic == field }) == null) {
    //             return false;
    //         };
    //     };
    //     return true;
    // };

    public func getSubscribers(filter : EventFilter) : async [Subscriber] {
        let subscribers = Iter.toArray(eventHub.subscribers.vals());

        let filteredSubscribers = Array.filter<Subscriber>(
            subscribers,
            func(subscriber : Subscriber) : Bool {
                return compareEventFilter(subscriber.filter, filter);
            },
        );

        return filteredSubscribers;
    };

    private func compareEventFilter(filter1 : EventFilter, filter2 : EventFilter) : Bool {
        switch (filter1.eventType, filter2.eventType) {
            case (null, null) {};
            case (null, _) {};
            case (_, null) {};
            case (?type1, ?type2) if (type1 != type2) return false;
        };

        let sortedFields1 = Array.sort<EventField>(
            filter1.fieldFilters,
            func(x : EventField, y : EventField) : Order.Order {
                Text.compare(x.name, y.name);
            },
        );
        let sortedFields2 = Array.sort<EventField>(
            filter2.fieldFilters,
            func(x : EventField, y : EventField) : Order.Order {
                Text.compare(x.name, y.name);
            },
        );

        return Array.equal<EventField>(
            sortedFields1,
            sortedFields2,
            func(x : EventField, y : EventField) : Bool {
                x.name == y.name and x.value == y.value
            },
        );
    };

    // TODO add postupgrade
};
