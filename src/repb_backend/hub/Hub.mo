import Array "mo:base/Array";
import Blob "mo:base/Blob";
import HashMap "mo:base/HashMap";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Order "mo:base/Order";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Text "mo:base/Text";

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

    type Callback = Types.Callback;

    type EventHub = {
        var events : [Event];
        var subscribers : [Callback];
    };

    type CreateEvent = Types.CreateEvent;

    var batchMakingDurationNano : Int = 1;
    var batchMaxSizeBytes : Nat = 500_000;
    var listeners : [FilterListenersPair] = [];

    stable let eventHub : EventHub = {
        var events = [];
        var subscribers = [];
    };

    func compareEventFields(field1 : EventField, field2 : EventField) : Order.Order {
        if (field1.name < field2.name) {
            return #less;
        } else if (field1.name > field2.name) {
            return #greater;
        } else {
            if (field1.value < field2.value) {
                return #less;
            } else if (field1.value > field2.value) {
                return #greater;
            } else {
                return #equal;
            };
        };
    };

    func equalEventFilters(filter1 : EventFilter, filter2 : EventFilter) : Bool {
        // Сортировка фильтров перед сравнением
        let sortedFilter1 = Array.sort(filter1, compareEventFields);
        let sortedFilter2 = Array.sort(filter2, compareEventFields);

        return Array.equal<EventField>(
            sortedFilter1,
            sortedFilter2,
            func(field1, field2) {
                field1.name == field2.name and field1.value == field2.value
            },
        );
    };

    public func addEventListener(filter : EventFilter, endpoint : RemoteCallEndpoint) : async () {
        let existingPair = Array.find<FilterListenersPair>(
            listeners,
            func(pair) {
                equalEventFilters(pair.filter, filter);
            },
        );

        switch (existingPair) {
            case (?pair) {
                let updatedListeners = Array.append(pair.listeners, [endpoint]);
                let updatedPair = {
                    filter = filter;
                    listeners = updatedListeners;
                };
                let newListenersPairs = Array.map<FilterListenersPair, FilterListenersPair>(
                    listeners,
                    func(p) {
                        if (equalEventFilters(p.filter, pair.filter)) {
                            updatedPair;
                        } else { p };
                    },
                );
                listeners := newListenersPairs;
            };
            case null {
                listeners := Array.append(listeners, [{ filter = filter; listeners = [endpoint] }]);
            };
        };
    };

    public func removeEventListener(filter : EventFilter, endpoint : RemoteCallEndpoint) : async () {
        listeners := Array.filter<FilterListenersPair>(
            listeners,
            func(pair : FilterListenersPair) : Bool {
                if (equalEventFilters(pair.filter, filter)) {
                    let newListeners = Array.filter<RemoteCallEndpoint>(
                        pair.listeners,
                        func(ep : RemoteCallEndpoint) : Bool {
                            ep.canisterId != endpoint.canisterId or ep.methodName != endpoint.methodName;
                        },
                    );
                    return Array.size(newListeners) > 0;
                } else {
                    return true;
                };
            },
        );
    };

    public func emitEvent(event : Event) : async () {
        // Добавляем событие в список событий
        eventHub.events := Array.append(eventHub.events, [event]);

        // Перебираем всех подписчиков
        for (subscriber in eventHub.subscribers.vals()) {
            // Проверяем, соответствует ли событие фильтру подписчика
            if (isEventMatchFilter(event, subscriber.filter)) {
                ignore await sendEvent(event, subscriber.callback);
            };
        };
    };

    func sendEvent(event : Event, canister_id : Principal) : async Result.Result<[(Text, Text)], Text> {
        let subscriber_canister : CreateEvent = actor (Principal.toText(canister_id));

        switch (await subscriber_canister.creation(event)) {
            case (#ok(result)) {
                #ok(result);
            };
            case (#err(errorMsg)) {
                #err("Ошибка вызова: " # errorMsg);
            };
        };
    };

    func isEventMatchFilter(event : Event, filter : EventFilter) : Bool {
        // Для каждого поля фильтра проверяем, присутствует ли оно в темах события
        for (field in filter.vals()) {
            // Ищем поле фильтра в темах события
            let found = Array.find<EventField>(
                event.topics,
                func(topic : EventField) : Bool {
                    topic.name == field.name and topic.value == field.value
                },
            );
            if (found == null) {
                // Если поле фильтра не найдено в темах события, событие не соответствует фильтру
                return false;
            };
        };
        // Все поля фильтра найдены в темах события
        return true;
    };

    public func getSubscribers(filter : EventFilter) : async [RemoteCallEndpoint] {
        // Используем Array.find для поиска пары с соответствующим фильтром
        let maybePair = Array.find<FilterListenersPair>(
            listeners,
            func(pair : FilterListenersPair) : Bool {
                equalEventFilters(pair.filter, filter);
            },
        );

        // Возвращаем список слушателей или пустой список, если фильтр не найден
        switch (maybePair) {
            case (?pair) {
                return pair.listeners;
            };
            case null {
                return [];
            };
        };
    };
};
