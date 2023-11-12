import Blob "mo:base/Blob";
import HashMap "mo:base/HashMap";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import Result "mo:base/Result";

module {
    // Определение типа для поля события
    public type EventField = {
        name : Text;
        value : Blob;
    };

    // Определение типа для события
    public type Event = {
        topics : [EventField];
        values : [EventField];
    };

    // Определение типа для фильтра событий
    public type EventFilter = [EventField];

    // Определение типа для удаленного вызова
    public type RemoteCallEndpoint = {
        canisterId : Principal.Principal;
        methodName : Text;
    };

    // Определение типа для пакета закодированных событий
    public type EncodedEventBatch = {
        content : Blob;
        eventsCount : Nat;
        timestamp : Int;
    };

    public type Callback = {
        filter : EventFilter;
        callback : Principal;
        methodName : Text;
    };

    public type CreateEvent = actor {
        creation : Event -> async Result.Result<[(Text, Text)], Text>;
    };

};
