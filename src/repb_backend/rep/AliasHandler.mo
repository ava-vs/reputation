import HashMap "mo:base/HashMap";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Iter "mo:base/Iter";
import Principal "mo:base/Principal";

actor AliasHandler {
    type Result<T, E> = Result.Result<T, E>;
    // Alias to use as key is the text identifier from Internet Identity.
    // Value is the user's text identifier from the check.ava.capetown website.
    var aliases : HashMap.HashMap<Text, Text> = HashMap.HashMap<Text, Text>(0, Text.equal, Text.hash);

    public shared ({ caller }) func addAlias(alias : Text) : async Text {
        let textCaller = Principal.toText(caller);
        // Only existing users can add an alias to themselves
        if (aliases.get(textCaller) == null) {
            return textCaller;
        };
        aliases.put(alias, textCaller);
        "No such alias";
    };

    public func getAlias(user : Text) : async Result<Text, Bool> {
        switch (aliases.get(user)) {
            case (?alias) {
                return #ok(alias);
            };
            case (_) {
                return #err(false);
            };
        };
    };

    public func removeAlias(user : Text) : async Bool {
        switch (aliases.remove(user)) {
            case (?_) {
                return true;
            };
            case (_) {
                return false;
            };
        };
    };

    stable var stableAsias : [(Text, Text)] = [];
    system func preupgrade() {
        stableAsias := Iter.toArray(aliases.entries());
    };
    system func postupgrade() {
        for ((user, alias) in stableAsias.vals()) {
            aliases.put(user, alias);
        };
        stableAsias := [];
    };
};
