import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Map "mo:base/HashMap";
import List "mo:base/List";
import Principal "mo:base/Principal";
import Text "mo:base/Text";

import E "./EventTypes";
import Hub "./Hub";
import T "./Types";
import Json "./utils/JSON";

actor class API(hub : Hub.Hub) {
    type HeaderField = (Text, Text);

    type HttpResponse = {
        status_code : Nat16;
        headers : [HeaderField];
        body : Blob;
    };

    type HttpRequest = {
        method : Text;
        url : Text;
        headers : [HeaderField];
        body : Blob;
    };

    type Hash = Blob;
    type Key = Blob;
    type Value = Blob;

    type EventField = {
        name : Text;
        value : Blob;
    };

    type Event = {
        fields : [EventField];
    };

    func body_content() : Blob {
        return Text.encodeUtf8("Test body");
    };

    let default_principal = Principal.fromText("3vwje-wuxnt-7mlef-3wwhk-inngl-r7lgf-hjbtu-rp3wk-x6brq-npyle-6ae");

    //TODO add stable Map
    let whitelist = Map.HashMap<Principal, Event>(0, Principal.equal, Principal.hash);

    public shared func http_request(req : HttpRequest) : async HttpResponse {
        switch (req.url) {
            case "/subscribe" {
                let res = await subscribe(req);
                return {
                    status_code = 200;
                    headers = [("content-type", "text/plain")];
                    body = "Subscribed successfully.\n";
                };
            };
            case "/unsubscribe" {
                let res = await unsubscribe(req);
                return {
                    status_code = 200;
                    headers = [("content-type", "text/plain")];
                    body = "Unsubscribed successfully.\n";
                };
            };
            case "/emit" {
                let res = await emit(req);
                return {
                    status_code = 200;
                    headers = [("content-type", "text/plain")];
                    body = "Event emitted successfully.\n";
                };
            };
            // Add other endpoints here
            case _ {
                return {
                    status_code = 404;
                    headers = [("content-type", "text/plain")];
                    body = "404 Not found.\n";
                };
            };
        };
    };

    func parseSubscriberFromJson(json : Json.JSON) : ?T.Subscriber {
        switch (json) {
            case (#Object(kvs)) {
                var callbackStr : ?Text = null;
                var eventFilterJson : ?Json.JSON = null;

                for ((key, val) in kvs.vals()) {
                    switch (key) {
                        case "callback" {
                            switch (val) {
                                case (#String(s)) {
                                    callbackStr := ?s;
                                };
                                case _ {
                                    /* Wrong callback format */
                                };
                            };
                        };
                        case "filter" {
                            eventFilterJson := ?val;
                        };
                        case _ { /* Ignore other keys */ };
                    };
                };

                switch (callbackStr, eventFilterJson) {
                    case (?cbStr, ?efJson) {
                        let callback = Principal.fromText(cbStr);
                        switch (decodeEventFilter(efJson)) {
                            case (null) { return null };
                            case (?eventFilter) {
                                return ?{
                                    callback = callback;
                                    filter = eventFilter;
                                };
                            };
                        };
                    };
                    case _ { return null };
                };
            };
            case _ { return null };
        };
    };

    public func subscribe(req : HttpRequest) : async HttpResponse {
        switch (Text.decodeUtf8(req.body)) {
            case (null) {
                return errorResponse("Invalid request body.", 400);
            };
            case (?bodyText) {
                switch (Json.parse(bodyText)) {
                    case (null) {
                        return errorResponse("Invalid JSON format.", 400);
                    };
                    case (?json) {
                        let subscriberOpt = parseSubscriberFromJson(json);
                        switch (subscriberOpt) {
                            case (null) {
                                return errorResponse("Invalid JSON data for subscription.", 400);
                            };
                            case (?subscriber) {
                                await hub.subscribe(subscriber);
                                return successResponse("Subscribed successfully.\n", 200);
                            };
                        };
                    };
                };
            };
        };
    };

    func errorResponse(message : Text, status : Nat16) : HttpResponse {
        return {
            status_code = status;
            headers = [("content-type", "text/plain")];
            body = Text.encodeUtf8(message);
        };
    };

    func successResponse(message : Text, status : Nat16) : HttpResponse {
        return {
            status_code = status;
            headers = [("content-type", "text/plain")];
            body = Text.encodeUtf8(message);
        };
    };

    func decodeEventFilter(obj : Json.JSON) : ?T.EventFilter {
        switch (obj) {
            case (#Object(filterObj)) {
                var eventType : ?Text = null;
                var fieldFilters : [T.EventField] = [];

                for ((key, val) in filterObj.vals()) {
                    switch (key) {
                        case "eventType" {
                            switch (val) {
                                case (#String(t)) { eventType := ?t };
                                case _ { eventType := null };
                            };
                        };
                        case "fieldFilters" {
                            switch (val) {
                                case (#Array(arr)) {
                                    fieldFilters := Array.map<Json.JSON, T.EventField>(
                                        arr,
                                        func(jsonField : Json.JSON) : T.EventField {
                                            var name : Text = "";
                                            var value : Text = "";
                                            switch (jsonField) {
                                                case (#Object(fieldObj)) {
                                                    for ((fKey, fVal) in fieldObj.vals()) {
                                                        switch (fKey) {
                                                            case "name" {
                                                                switch (fVal) {
                                                                    case (#String(n)) {
                                                                        name := n;
                                                                    };
                                                                    case _ {
                                                                        // Wrong name
                                                                    };
                                                                };
                                                            };
                                                            case "value" {
                                                                switch (fVal) {
                                                                    case (#String(v)) {
                                                                        value := v;
                                                                    };
                                                                    case _ {
                                                                        // Wrong value
                                                                    };
                                                                };
                                                            };
                                                            case _ {};
                                                        };
                                                    };
                                                    {
                                                        name = name;
                                                        value = value;
                                                    };
                                                };
                                                case _ {
                                                    { name = ""; value = "" };
                                                };
                                            };
                                        },
                                    );
                                };
                                case _ {
                                    // Wrong format fieldFilters
                                };
                            };
                        };
                        case _ {};
                    };
                };
                let textType = switch (eventType) {
                    case (null) "";
                    case (?t) t;
                };
                return ?{
                    eventType = ?E.textToEventName(textType);
                    fieldFilters = fieldFilters;
                };
            };
            case _ { return null };
        };
    };

    public func emit(req : HttpRequest) : async HttpResponse {
        //  Blob to Text
        let optJson : ?Text = Text.decodeUtf8(req.body);
        let json = switch (optJson) {
            case (?json) json;
            case (_) return {
                status_code = 400;
                headers = [("content-type", "text/plain")];
                body = Text.encodeUtf8("Invalid data format.\n");
            };
        };
        let optParsedJson = Json.parse(json);
        switch (optParsedJson) {
            case (null) {
                return {
                    status_code = 400;
                    headers = [("content-type", "text/plain")];
                    body = Text.encodeUtf8("Invalid JSON format.\n");
                };
            };
            case (? #Object(obj)) {
                var eventName : ?Text = null;
                var eventFields : [EventField] = [];

                for ((key, val) in obj.vals()) {
                    switch (key) {
                        case "eventName" {
                            switch (val) {
                                case (#String(name)) {
                                    eventName := ?name;
                                };
                                case _ {
                                    return {
                                        status_code = 400;
                                        headers = [("content-type", "text/plain")];
                                        body = Text.encodeUtf8("Invalid JSON format for eventName.\n");
                                    };
                                };
                            };
                        };
                        case "fieldFilters" {
                            switch (val) {
                                case (#Array(arr)) {
                                    eventFields := parseFieldFilters(arr);
                                };
                                case _ {
                                    return {
                                        status_code = 400;
                                        headers = [("content-type", "text/plain")];
                                        body = Text.encodeUtf8("Invalid JSON format for fieldFilters.\n");
                                    };
                                };
                            };
                        };
                        case _ { /* Игнорировать другие ключи */ };
                    };
                };

                // Проверка eventName и вызов соответствующего метода хаба
                // ...
                return {
                    status_code = 200;
                    headers = [("content-type", "text/plain")];
                    body = Text.encodeUtf8("Event emitted successfully.\n");
                };
            };
            case _ {
                return {
                    status_code = 400;
                    headers = [("content-type", "text/plain")];
                    body = Text.encodeUtf8("Invalid JSON format.\n");
                };
            };
        };
    };

    func parseFieldFilters(arr : [Json.JSON]) : [EventField] {
        Array.map<Json.JSON, EventField>(
            arr,
            func(jsonField : Json.JSON) : EventField {
                var name : Text = "";
                var value : Blob = Blob.fromArray([]);

                switch (jsonField) {
                    case (#Object(fieldObj)) {
                        for ((fKey, fVal) in fieldObj.vals()) {
                            switch (fKey) {
                                case "name" {
                                    switch (fVal) {
                                        case (#String(n)) { name := n };
                                        case _ {
                                            /* Некорректное значение для name */
                                        };
                                    };
                                };
                                case "value" {
                                    switch (fVal) {
                                        case (#String(v)) {
                                            value := Text.encodeUtf8(v);
                                        };
                                        case _ {
                                            /* Некорректное значение для value */
                                        };
                                    };
                                };
                                case _ { /* Игнорировать другие ключи */ };
                            };
                        };
                        { name = name; value = value };
                    };
                    case _ {
                        { name = ""; value = Blob.fromArray([]) }; // Пустые значения для некорректных данных
                    };
                };
            },
        );
    };

    public func unsubscribe(req : HttpRequest) : async HttpResponse {
        //  Blob to Text
        let optJson : ?Text = Text.decodeUtf8(req.body);
        let json = switch (optJson) {
            case (?json) json;
            case (_) return {
                status_code = 400;
                headers = [("content-type", "text/plain")];
                body = Text.encodeUtf8("Invalid data format.\n");
            };
        };
        let optParsedJson = Json.parse(json);
        switch (optParsedJson) {
            case (null) {
                return {
                    status_code = 400;
                    headers = [("content-type", "text/plain")];
                    body = Text.encodeUtf8("Invalid JSON format.\n");
                };
            };
            case (? #Object(obj)) {
                var subscriberId : ?Text = null;
                for ((key, value) in obj.vals()) {
                    if (key == "subscriberId") {
                        switch (value) {
                            case (#String(s)) subscriberId := ?s;
                            case (_) return {
                                status_code = 400;
                                headers = [("content-type", "text/plain")];
                                body = Text.encodeUtf8("Invalid JSON format.\n");
                            };
                        };
                    };
                };
                switch (subscriberId) {
                    case (?id) {
                        await hub.unsubscribe(Principal.fromText(id));
                        return {
                            status_code = 200;
                            headers = [("content-type", "text/plain")];
                            body = Text.encodeUtf8("Unsubscribed successfully.\n");
                        };
                    };
                    case null {
                        return {
                            status_code = 400;
                            headers = [("content-type", "text/plain")];
                            body = Text.encodeUtf8("Subscriber ID not found.\n");
                        };
                    };
                };
            };
            case _ {
                // Invalid JSON format
                return {
                    status_code = 400;
                    headers = [("content-type", "text/plain")];
                    body = Text.encodeUtf8("Invalid data format.\n");
                };
            };
        };
    };

    public shared ({ caller = deployer }) func register(user : Principal) {
        whitelist.put(user, { fields = [] });
    };

    func check(user : Principal) {
        //TODO check is user exist in whitelist
    };

};
