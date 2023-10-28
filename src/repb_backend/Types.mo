import Text "mo:base/Text";
module {
    public type Subaccount = Blob;
    public type Account = {
        owner : Principal;
        subaccount : ?Subaccount;
    };

    public type ApprovalInfo = {
        from_subaccount : ?Blob;
        spender : Account; // Approval is given to an ICRC Account
        memo : ?Blob;
        expires_at : ?Nat64;
        created_at_time : ?Nat64;
    };

    public type ApproveTokensError = {
        #NonExistingTokenId;
        #Unauthorized;
        #TooOld;
        #CreatedInFuture : { ledger_time : Nat64 };
        #GenericError : { error_code : Nat; message : Text };
    };

    public type Key = Text;

    public type Value = {
        #Blob : Blob;
        #Text : Text;
        #Nat : Nat;
        #Int : Int;
        #Array : [ Value ];
        #Map : [{ key : Text; value : Value }];
    };

    public type Metadata = {
        symbol: Text;
        name: Text;
        total_supply: Nat;
        description : ?Text;
        supply_cap: ?Nat;
        logo : ?Text; // URL to logo
        extra : ?[{ key : Text; value : Value }]; // Any extra metadata
    };
};
