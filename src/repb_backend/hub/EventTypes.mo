import Result "mo:base/Result";

module {

    public type EventField = {
        name : Text;
        value : Text;
    };

    public type EventName = {
        #CreateEvent;
        #BurnEvent;
        #CollectionCreatedEvent;
        #CollectionUpdatedEvent;
        #CollectionDeletedEvent;
        #AddToCollectionEvent;
        #RemoveFromCollectionEvent;
        #Unknown;
    };

    public type Event = {
        eventType : EventName;
        topics : [EventField];
    };

    public type CreateEvent = actor {
        creation : Event -> async Result.Result<[(Text, Text)], Text>;
    };

    public type BurnEvent = actor {
        burn : Event -> async Result.Result<[(Text, Text)], Text>;
    };

    public type CollectionCreatedEvent = actor {
        collectionCreated : Event -> async Result.Result<[(Text, Text)], Text>;
    };
    public type CollectionUpdatedEvent = actor {
        collectionUpdated : Event -> async Result.Result<[(Text, Text)], Text>;
    };
    public type CollectionDeletedEvent = actor {
        collectionDeletedd : Event -> async Result.Result<[(Text, Text)], Text>;
    };
    public type AddToCollectionEvent = actor {
        addToCollection : Event -> async Result.Result<[(Text, Text)], Text>;
    };
    public type RemoveFromCollectionEvent = actor {
        removeFromCollection : Event -> async Result.Result<[(Text, Text)], Text>;
    };

    public type Events = {
        #CreateEvent : CreateEvent;
        #BurnEvent : BurnEvent;
        #CollectionCreatedEvent : CollectionCreatedEvent;
        #CollectionUpdatedEvent : CollectionUpdatedEvent;
        #CollectionDeletedEvent : CollectionDeletedEvent;
        #AddToCollectionEvent : AddToCollectionEvent;
        #RemoveFromCollectionEvent : RemoveFromCollectionEvent;
    };

    public func textToEventName(text : Text) : EventName {
        switch (text) {
            case ("CreateEvent") return #CreateEvent;
            case ("BurnEvent") return #BurnEvent;
            case ("CollectionCreatedEvent") return #CollectionCreatedEvent;
            case ("CollectionUpdatedEvent") return #CollectionUpdatedEvent;
            case ("CollectionDeletedEvent") return #CollectionDeletedEvent;
            case ("AddToCollectionEvent") return #AddToCollectionEvent;
            case ("RemoveFromCollectionEvent") return #RemoveFromCollectionEvent;
            case (_) #Unknown;
        };
    };

};
