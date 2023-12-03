import Result "mo:base/Result";
import Nat8 "mo:base/Nat8";

module {

    public type EventField = {
        name : Text;
        value : Blob;
    };

    public type EventName = {
        #CreateEvent;
        #BurnEvent;
        #CollectionCreatedEvent;
        #CollectionUpdatedEvent;
        #CollectionDeletedEvent;
        #AddToCollectionEvent;
        #RemoveFromCollectionEvent;
        #InstantReputationUpdateEvent;
        #AwaitingReputationUpdateEvent;
        #NewRegistrationEvent;
        #FeedbackSubmissionEvent;
        #Unknown;
    };

    public type Event = {
        eventType : EventName;
        topics : [EventField];
        tokenId : ?Nat;
        owner : ?Principal;
        metadata : ?[(Text, Blob)];
        creationDate : ?Int;
    };

    public type DocHistoryArgs = {
        user : Principal;
        docId : Nat;
        value : Nat8;
        comment : Text;
    };

    public type Tag = Text;
    public type Branch = Nat8;

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
        collectionDeleted : Event -> async Result.Result<[(Text, Text)], Text>;
    };
    public type AddToCollectionEvent = actor {
        addToCollection : Event -> async Result.Result<[(Text, Text)], Text>;
    };
    public type RemoveFromCollectionEvent = actor {
        removeFromCollection : Event -> async Result.Result<[(Text, Text)], Text>;
    };
    public type InstantReputationUpdateEvent = actor {
        updateDocHistory : (DocHistoryArgs) -> async Result.Result<[(Text, Text)], Text>;
        getTags : () -> async [(Tag, Branch)];
        getMintingAccount : () -> async Principal;
        eventHandler : (DocHistoryArgs) -> async Text;
    };
    public type AwaitingReputationUpdateEvent = actor {
        updateReputation : Event -> async Result.Result<[(Text, Text)], Text>;
    };
    public type FeedbackSubmissionEvent = actor {
        feedbackSubmission : Event -> async Result.Result<[(Text, Text)], Text>;
    };

    public type Events = {
        #CreateEvent : CreateEvent;
        #BurnEvent : BurnEvent;
        #CollectionCreatedEvent : CollectionCreatedEvent;
        #CollectionUpdatedEvent : CollectionUpdatedEvent;
        #CollectionDeletedEvent : CollectionDeletedEvent;
        #AddToCollectionEvent : AddToCollectionEvent;
        #RemoveFromCollectionEvent : RemoveFromCollectionEvent;
        #InstantReputationUpdateEvent : InstantReputationUpdateEvent;
        #AwaitingReputationUpdateEvent : AwaitingReputationUpdateEvent;
        #FeedbackSubmissionEvent : FeedbackSubmissionEvent;
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
            case ("InstantReputationUpdateEvent") return #InstantReputationUpdateEvent;
            case ("AwaitingReputationUpdateEvent") return #AwaitingReputationUpdateEvent;
            case ("FeedbackSubmissionEvent") return #FeedbackSubmissionEvent;

            case (_) #Unknown;
        };
    };

};
