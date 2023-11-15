import Blob "mo:base/Blob";
import HashMap "mo:base/HashMap";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import Result "mo:base/Result";

import E "./EventTypes";

module {
    public type EventField = E.EventField;

    public type Event = E.Event;

    public type EventFilter = {
        eventType : ?E.EventName;
        fieldFilters : [EventField];
    };

    public type RemoteCallEndpoint = {
        canisterId : Principal.Principal;
        methodName : Text;
    };

    public type EncodedEventBatch = {
        content : Blob;
        eventsCount : Nat;
        timestamp : Int;
    };

    public type Subscriber = {
        callback : Principal;
        filter : EventFilter;
    };

};
