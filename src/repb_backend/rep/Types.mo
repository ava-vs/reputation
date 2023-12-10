import Map "mo:base/HashMap";
import Principal "mo:base/Principal";
import Buffer "mo:base/Buffer";

module {
  public type DocId = Nat;

  public type Document = {
    tokenId : DocId;
    categories : [Category];
    owner : Principal;
    metadata : [(Text, Metadata)];
  };

  public type DocDAO = {
    categories : [Category];
    owner : Principal;
    metadata : [(Text, Metadata)];
  };

  public type Metadata = {
    #Nat : Nat;
    #Nat8 : Nat8;
    #Int : Int;
    #Text : Text;
    #Blob : Blob;
    #Bool : Bool;
  };

  public type Doctoken = actor {
    getDocumentById : (DocId) -> async ?Document;
  };

  // public type UserDocuments = Map.HashMap<Principal, [DocId]>;

  public type Category = Text;

  public type DocumentHistory = {
    docId : DocId;
    timestamp : Int;
    changedBy : Principal;
    value : Nat8;
    comment : Text;
  };

  // public type Tag = Text;

  public type ApiError = {
    #Unauthorized;
    #InvalidTokenId;
    #ZeroAddress;
    #NoNFT;
    #Other;
  };

  public type Result<S, E> = {
    #Ok : S;
    #Err : E;
  };

  // public type Change = (Principal, Branch, Int);

  // public type ChangeResult = Result<Change, ApiError>;

  // public type SharedResult = Result<Change, ApiError>;

  public type Account = { owner : Principal; subaccount : ?Subaccount };
  public type Subaccount = Blob;
  public type Tokens = Nat;
  public type Memo = Blob;
  public type Timestamp = Nat64;
  public type Duration = Nat64;
  public type TxIndex = Nat;
  public type TxLog = Buffer.Buffer<Transaction>;

  public type Value = { #Nat : Nat; #Int : Int; #Blob : Blob; #Text : Text };

  public type Operation = {
    #Approve : Approve;
    #Transfer : Transfer;
    #Burn : Transfer;
    #Mint : Transfer;
  };

  public type CommonFields = {
    memo : ?Memo;
    fee : ?Tokens;
    created_at_time : ?Timestamp;
  };

  public type Approve = CommonFields and {
    from : Account;
    spender : Principal;
    amount : Int;
    expires_at : ?Nat64;
  };

  public type TransferSource = {
    #Init;
    #Icrc1Transfer;
    #Icrc2TransferFrom;
  };

  public type Transfer = CommonFields and {
    spender : Principal;
    source : TransferSource;
    to : Account;
    from : Account;
    amount : Tokens;
  };

  public type Allowance = { allowance : Nat; expires_at : ?Nat64 };

  public type Transaction = {
    operation : Operation;
    // Effective fee for this transaction.
    fee : Tokens;
    timestamp : Timestamp;
  };

  public type DeduplicationError = {
    #TooOld;
    #Duplicate : { duplicate_of : TxIndex };
    #CreatedInFuture : { ledger_time : Timestamp };
  };

  public type CommonError = {
    #InsufficientFunds : { balance : Tokens };
    #BadFee : { expected_fee : Tokens };
    #TemporarilyUnavailable;
    #GenericError : { error_code : Nat; message : Text };
    #NotFound : { message : Text; docId : DocId };
  };

  public type TransferError = DeduplicationError or CommonError or {
    #BadBurn : { min_burn_amount : Tokens };
  };

  public type ApproveError = DeduplicationError or CommonError or {
    #Expired : { ledger_time : Nat64 };
  };

  public type TransferFromError = TransferError or {
    #InsufficientAllowance : { allowance : Nat };
  };

  public type BurnError = CommonError or {
    #WrongBranch : { current_branch : Nat8; target_branch : Nat8 };
    #WrongDocument : { current_branch : Nat8; document : DocId };
    #InsufficientReputation : { current_branch : Nat8; balance : Tokens };
    #DocumentReputationReductionLimitReached : { document : DocId };
  };

  public type TransferBurnError = TransferFromError or BurnError;

  public type CategoryError = CommonError or {
    #CategoryAlreadyExists : { category : Category; cifer : Text };
    #CategoryDoesNotExist : { category : Category };
  };
};
