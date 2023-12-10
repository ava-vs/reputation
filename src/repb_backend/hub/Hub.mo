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

import E "./EventTypes";
import Types "./Types";
import List "utils/List";
import Logger "utils/Logger";
import Utils "utils/Utils";

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
    let prefix = Utils.timestampToDate() # " ";

    // For further batch handling
    var batchMakingDurationNano : Int = 1_000_000_000;
    var batchMaxSizeBytes : Nat = 500_000;

    // var listeners : [FilterListenersPair] = [];

    let default_principal : Principal = Principal.fromText("aaaaa-aa");
    let rep_canister_id = "aoxye-tiaaa-aaaal-adgnq-cai";
    let default_doctoken_canister_id = "h5x3q-hyaaa-aaaal-adg6q-cai";

    // subscribers : <canisterId ,

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

    public func clearAllLogs() : async Bool {
        logger.clear();
        true;
    };

    public func getCategories() : async [(E.Category, Text)] {
        let rep_canister : E.InstantReputationUpdateEvent = actor (rep_canister_id);
        let tags = await rep_canister.getCategories();
        tags;
    };

    public func subscribe(subscriber : Subscriber) : async Bool {
        //TODO check the subscriber for the required methods
        eventHub.subscribers.put(subscriber.callback, subscriber);
        true;
    };

    public func unsubscribe(principal : Principal) : async () {
        eventHub.subscribers.delete(principal);
    };

    public shared ({ caller }) func emitEvent(event : E.Event) : async [Subscriber] {
        // TODO save publisher+his doctoken to hub
        logger.append([prefix # "Starting method emitEvent"]);
        eventHub.events := Array.append(eventHub.events, [event]);

        let buffer = Buffer.Buffer<Subscriber>(0);
        for (subscriber in eventHub.subscribers.vals()) {
            // TODO check subscriber
            logger.append([prefix # "emitEvent: check subscriber " # Principal.toText(subscriber.callback) # " with filter " # subscriber.filter.fieldFilters[0].name]);

            if (isEventMatchFilter(event, subscriber.filter)) {
                logger.append([prefix # "emitEvent: event matched"]);
                buffer.add(subscriber);
                var canister_doctoken = Principal.toText(caller);
                if (Principal.fromText("2vxsx-fae") == caller) canister_doctoken := default_doctoken_canister_id;
                let response = await sendEvent(event.reputation_change.reviewer, event, canister_doctoken, subscriber.callback);
            };

        };

        return Buffer.toArray(buffer);
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

        logger.append([prefix # " isEventMatchFilter: Checking subsriber's event type", eventNameToText(Option.get<E.EventName>(filter.eventType, #Unknown))]);
        logger.append([prefix # " with event type: ", eventNameToText(event.eventType)]);
        switch (filter.eventType) {
            case (null) {
                logger.append([prefix # "isEventMatchFilter: Event type is null"]);
            };
            case (?t) if (t != event.eventType) {
                logger.append([prefix # "isEventMatchFilter: Event type does not match: " # eventNameToText(event.eventType) # " and " # eventNameToText(t)]);
                return false;
            };
        };
        logger.append([prefix # " isEventMatchFilter: Event type matched"]);
        logger.append([prefix # " isEventMatchFilter: Checking subsriber's field filters"]);
        logger.append([prefix # " isEventMatchFilter: event topic 1: name = " # event.topics[0].name # " , value = " # Nat8.toText(Blob.toArray(event.topics[0].value)[0])]);
        for (field in filter.fieldFilters.vals()) {
            logger.append([prefix # "isEventMatchFilter: Checking field", field.name, Nat8.toText(Blob.toArray(field.value)[0])]);
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

    // public func testSendEvent(flag : Nat) : async Text {
    //     let canister : E.InstantReputationUpdateEvent = actor ("aoxye-tiaaa-aaaal-adgnq-cai");
    //     let args : E.DocHistoryArgs = {
    //         reviewer = Principal.fromText("bs3e6-4i343-voosn-wogd7-6kbdg-mctak-hn3ws-k7q7f-fye2e-uqeyh-yae");
    //         user = Principal.fromText("bs3e6-4i343-voosn-wogd7-6kbdg-mctak-hn3ws-k7q7f-fye2e-uqeyh-yae");
    //         docId = 1;
    //         caller_doctoken_canister_id = "aaaaa-aa";
    //         value = 10;
    //         comment = "Test passed";
    //     };
    //     let response = await canister.getMintingAccount();
    //     if (flag == 1) return "test 1 done";
    //     if (flag == 0) {
    //         return "ok";
    //     };
    //     if (flag == 3) { return Principal.toText(response) };
    //     "unknown";
    // };

    func sendEvent(reviwer : ?Principal, event : E.Event, caller_doctoken_canister_id : Text, canisterId : Principal) : async Result.Result<[(Text, Text)], Text> {

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
                let args : E.ReputationChangeRequest = event.reputation_change;//{
                //     user : Principal = event.reputation_change.user;
                //     reviewer : ?Principal =event.reputation_change.reviewer;
                //     value : ?Nat = event.reputation_change.value;
                //     category : Text = event.reputation_change.category;
                //     timestamp : Nat = event.reputation_change.timestamp;
                //     source : (Text, Nat) = (caller_doctoken_canister_id, event.reputation_change.source.1); // (doctoken_canisterId, documentId)
                //     comment : ?Text = event.reputation_change.comment;
                //     metadata = event.reputation_change.metadata;
                    
                // };
                let rep_value = Nat.toText(Option.get<Nat>(args.value, 0));
                logger.append([
                    prefix # "sendEvent: args created, user=" # Principal.toText(args.user) # " token Id = " # Nat.toText(args.source.1)
                    # " caller_doctoken_canister_id = " # args.source.0 # " value = " # rep_value # " comment " # Option.get<Text>(args.comment, "null")
                ]);

                // Call eventHandler method from subscriber canister
                let response = await canister.eventHandler(args);
                logger.append([prefix # "sendEvent: eventHandler method has been executed. Response: " # response]);
                if (response == "Event InstantReputationUpdateEvent was handled") {
                    return #ok([(
                        "updateDocHistory done",
                        "reputation of " # Principal.toText(args.user)
                        # " increased by " # rep_value,
                    )]);
                } else {
                    return #err("updateDocHistory failed");
                };
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

    public func getAllSubscribers() : async [Subscriber] {
        Iter.toArray(eventHub.subscribers.vals());
    };

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

    stable var eventState : [E.Event] = [];
    stable var eventSubscribers : [Subscriber] = [];

    system func preupgrade() {
        eventState := eventHub.events;
        eventSubscribers := Iter.toArray(eventHub.subscribers.vals());
    };
    system func postupgrade() {
        eventHub.events := eventState;
        eventState := [];
        for (subscriber in eventSubscribers.vals()) {
            eventHub.subscribers.put(subscriber.callback, subscriber);
        };
        eventSubscribers := [];
    };
};
