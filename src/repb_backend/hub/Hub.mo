import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import HashMap "mo:base/HashMap";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Option "mo:base/Option";
import Order "mo:base/Order";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Time "mo:base/Time";

import E "./EventTypes";
import Types "./Types";
import Logger "utils/Logger";

actor class Hub() {
    type EventField = E.EventField;

    type Event = E.Event;

    type EventFilter = Types.EventFilter;

    type RemoteCallEndpoint = Types.RemoteCallEndpoint;

    type EncodedEventBatch = Types.EncodedEventBatch;

    type Subscriber = Types.Subscriber;

    type EventName = E.EventName;

    // Logger

    stable var state : Logger.State<Text> = Logger.new<Text>(0, null);
    let logger = Logger.Logger<Text>(state);
    let prefix = "[" # Int.toText(Time.now() / 1_000_000_000) # "] ";

    // For further batch handling
    var batchMakingDurationNano : Int = 1_000_000_000;
    var batchMaxSizeBytes : Nat = 500_000;

    // var listeners : [FilterListenersPair] = [];

    let default_principal : Principal = Principal.fromText("aaaaa-aa");
    let rep_canister_id = "aoxye-tiaaa-aaaal-adgnq-cai";

    var eventHub = {
        var events : [E.Event] = [];
        subscribers : HashMap.HashMap<Principal, Subscriber> = HashMap.HashMap<Principal, Subscriber>(10, Principal.equal, Principal.hash);
    };

    public func viewLogs(end : Nat) : async [Text] {
        let view = logger.view(0, end);
        let result = Buffer.Buffer<Text>(1);
        for (message in view.messages.vals()) {
            result.add(message);
        };
        Buffer.toArray(result);
    };

    public func subscribe(subscriber : Subscriber) : async () {
        let principal = subscriber.callback;
        //TODO check the subscriber for the required methods
        eventHub.subscribers.put(principal, subscriber);
    };

    public func unsubscribe(principal : Principal) : async () {
        eventHub.subscribers.delete(principal);
    };

    public func emitEvent(event : E.Event) : async [Subscriber] {
        // TODO save publisher+his doctoken to hub
        logger.append([prefix # "Starting method emitEvent"]);
        eventHub.events := Array.append(eventHub.events, [event]);

        let subscribersArray = Iter.toArray(eventHub.subscribers.vals());

        for (subscriber in eventHub.subscribers.vals()) {
            // TODO check subscriber
            logger.append([prefix # "emitEvent: check subscriber"]);

            if (isEventMatchFilter(event, subscriber.filter)) {
                logger.append([prefix # "emitEvent: event matched"]);
                let response = await sendEvent(event, subscriber.callback);
            };

        };

        return subscribersArray;
    };

    func eventNameToText(eventName : EventName) : Text {
        switch (eventName) {
            case (#CreateEvent) { "CreateEvent" };
            case (#BurnEvent) { "BurnEvent" };
            case (#CollectionCreatedEvent) { "CollectionCreatedEvent" };
            case (#CollectionUpdatedEvent) { "CollectionUpdatedEvent" };
            case (#CollectionDeletedEvent) { "CollectionDeletedEvent" };
            case (#AddToCollectionEvent) { "AddToCollectionEvent" };
            case (#RemoveFromCollectionEvent) { "RemoveFromCollectionEvent" };
            case (#InstantReputationUpdateEvent) {
                "InstantReputationUpdateEvent";
            };
            case (#AwaitingReputationUpdateEvent) {
                "AwaitingReputationUpdateEvent";
            };
            case (#FeedbackSubmissionEvent) { "FeedbackSubmissionEvent" };
            case (#NewRegistrationEvent) { "NewRegistrationEvent" };
            case (#Unknown) { "Unknown" };
        };
    };

    func isEventMatchFilter(event : E.Event, filter : EventFilter) : Bool {
        logger.append([prefix # "Starting method isEventMatchFilter"]);

        logger.append([prefix # "isEventMatchFilter: Checking event type", eventNameToText(Option.get<E.EventName>(filter.eventType, #Unknown))]);

        switch (filter.eventType) {
            case (null) {
                logger.append([prefix # "isEventMatchFilter: Event type is null"]);
            };
            case (?t) if (t != event.eventType) {
                logger.append([prefix # "isEventMatchFilter: Event type does not match", eventNameToText(event.eventType)]);
                return false;
            };
        };

        for (field in filter.fieldFilters.vals()) {
            let found = Array.find<EventField>(
                event.topics,
                func(topic : EventField) : Bool {
                    topic.name == field.name and topic.value == field.value
                },
            );
            if (found == null) {
                logger.append([prefix # "isEventMatchFilter: Field not found", field.name]);
                return false;
            };
        };
        logger.append([prefix # "isEventMatchFilter: Event matched"]);
        return true;
    };

    // TEST sendEvent

    public func testSendEvent(flag : Nat) : async Text {
        let canister : E.InstantReputationUpdateEvent = actor ("aoxye-tiaaa-aaaal-adgnq-cai");
        let args : E.DocHistoryArgs = {
            user = Principal.fromText("bs3e6-4i343-voosn-wogd7-6kbdg-mctak-hn3ws-k7q7f-fye2e-uqeyh-yae");
            docId = 1;
            value = 10;
            comment = "Successful completion of the Motoko Basic course";
        };
        let response = await canister.getMintingAccount();
        if (flag == 1) return "test 1 done";
        if (flag == 0) {
            return "ok";
        };
        if (flag == 3) { return Principal.toText(response) };
        "unknown";
    };

    func sendEvent(event : E.Event, canisterId : Principal) : async Result.Result<[(Text, Text)], Text> {
        logger.append([prefix # "Starting method sendEvent"]);
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
            case (#InstantReputationUpdateEvent(_)) {
                logger.append([prefix # "sendEvent: case #InstantReputationUpdateEvent, start updateDocHistory"]);
                let canister : E.InstantReputationUpdateEvent = actor (subscriber_canister_id);
                logger.append([prefix # "sendEvent: canister created"]);

                let args : E.DocHistoryArgs = {
                    user = Option.get<Principal>(event.owner, default_principal);
                    docId = Option.get<Nat>(event.tokenId, 0);
                    value = 10;
                    comment = "Successful completion of the Motoko Basic course";
                };
                logger.append([prefix # "sendEvent: args created", Principal.toText(args.user), Nat.toText(args.docId), Nat8.toText(args.value), args.comment]);

                let response = await canister.eventHandler(args);
                logger.append([prefix # "sendEvent: updateDocHistory, done, check result"]);
                // switch (response) {
                //     case (#ok(res)) {
                //         logger.append([prefix # "sendEvent: updateDocHistory done", "reputation increase by " # Nat8.toText(args.value)]);
                //     };
                //     case (#err(err)) {
                //         logger.append([prefix # "sendEvent: updateDocHistory failed", err]);
                //     };
                // };
                logger.append([prefix # "sendEvent: eventHandler method has been executed. Response: ", response]);
                #ok([("updateDocHistory done", "reputation increase by " # Nat8.toText(args.value))]);
            };
            case (#AwaitingReputationUpdateEvent(_)) {
                let canister : E.AwaitingReputationUpdateEvent = actor (subscriber_canister_id);
                let response = await canister.updateReputation(event);
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

    // func updateDocHistory(event : E.Event) : async Types.Result<Types.DocHistory, Types.CommonError> {
    //     // TODO - add to InstantReputationUpdateEvent event handler rep.updateDocHistory();

    //     return #Err(#TemporarilyUnavailable);
    // };

    // TODO add postupgrade
};
