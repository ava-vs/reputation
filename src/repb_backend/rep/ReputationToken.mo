import Ledger "canister:ledger";

import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Bool "mo:base/Bool";
import Buffer "mo:base/Buffer";
import Error "mo:base/Error";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import { now } "mo:base/Time";
import { recurringTimer; setTimer } "mo:base/Timer";
import HashMap "mo:base/HashMap";

import Types "Types";

actor ReputationToken {
  let main_principal = Principal.fromText("36m6a-jxboo-zbvze-io5r2-gc64j-dcjoy-bovog-5dqvl-p66rb-ck3un-uqe");

  // null subaccount will be use as shared token wallet
  // 1 subaccount is incenitive subaccount
  // other subaccounts are branch ids
  let pre_mint_account = {
    owner = main_principal;
    subaccount = null;
  };

  // TODO get token consts from front-end
  let token_name = "aVa Shared reputation token";
  let token_symbol = "AVAR";
  let token_fee = 6;
  let max_supply = 1_000_000;
  let token_init_balance = 100_000;
  let min_burn_amount = 1;
  let decimals = 3;

  func add_decimals(n : Nat) : Nat {
    n * 10 ** decimals;
  };

  //ledger part

  type Account = Types.Account; //{ owner : Principal; subaccount : ?Subaccount };
  type Subaccount = Types.Subaccount; //Blob;
  type Tokens = Types.Tokens; //Nat;
  type Memo = Types.Memo;
  type Timestamp = Types.Timestamp; //Nat64;
  type Duration = Types.Duration;
  type TxIndex = Types.TxIndex;
  type TxLog = Buffer.Buffer<Types.Transaction>;

  type Value = Types.Value;

  let permittedDriftNanos : Duration = 60_000_000_000;
  let transactionWindowNanos : Duration = 24 * 60 * 60 * 1_000_000_000;
  let defaultSubaccount : [Nat8] = Array.freeze<Nat8>(Array.init(32, 0 : Nat8));

  type Operation = Types.Operation;

  type CommonFields = Types.CommonFields;

  type Approve = Types.Approve;

  type TransferSource = Types.TransferSource;

  type Transfer = Types.Transfer;

  type Allowance = Types.Allowance;

  type Transaction = Types.Transaction;

  type DeduplicationError = Types.DeduplicationError;

  type CommonError = Types.CommonError;

  type BurnError = Types.BurnError;

  type TransferError = Ledger.TransferError;

  type ApproveError = Ledger.ApproveError;

  type TransferFromError = Ledger.TransferFromError;

  public type Result<T, E> = { #Ok : T; #Err : E };

  type Balance = Nat;

  // Specialists and experts
  type ExpertMap = HashMap.HashMap<Principal, HashMap<Subaccount, Balance>>;
  stable let experts : ExpertMap = HashMap.HashMap<Principal, HashMap<Subaccount, Balance>>(0, Principal.equal, Principal.hash);
  stable let specialists = HashMap.HashMap<Principal, HashMap<Subaccount, Balance>>(0, Principal.equal, Principal.hash);

  // Subaccounts
  func beBytes(n : Nat32) : [Nat8] {
    func byte(n : Nat32) : Nat8 {
      Nat8.fromNat(Nat32.toNat(n & 0xff));
    };
    [byte(n >> 24), byte(n >> 16), byte(n >> 8), byte(n)];
  };

  public func createSubaccountByBranch(branch : Nat8) : async Subaccount {
    let bytes = beBytes(Nat32.fromNat(Nat8.toNat(branch)));
    let padding = Array.freeze(Array.init<Nat8>(28, 0 : Nat8));
    Blob.fromArray(Array.append(bytes, padding));
  };

  public func nullSubaccount() : async Subaccount {
    Blob.fromArrayMut(Array.init(32, 0 : Nat8));
  };

  public func addSubaccount(user : Principal, branch : Nat8) : async Account {
    let sub = await createSubaccountByBranch(branch);
    let newAccount : Account = { owner = user; subaccount = ?sub };
  };

  func getBranchFromSubaccount(subaccount : ?Subaccount) : Nat8 {
    let sub = switch (subaccount) {
      case null return 0;
      case (?sub) sub;
    };
    let bytes = Blob.toArray(sub);
    let b0 = Nat32.fromNat(Nat8.toNat(bytes[0]));
    let b1 = Nat32.fromNat(Nat8.toNat(bytes[1]));
    let b2 = Nat32.fromNat(Nat8.toNat(bytes[2]));
    let b3 = Nat32.fromNat(Nat8.toNat(bytes[3]));

    let n = (b0 << 24) + (b1 << 16) + (b2 << 8) + b3;
    Nat8.fromNat(Nat32.toNat(n));
  };

  func subaccountToNatArray(subaccount : Subaccount) : [Nat8] {
    var buffer = Buffer.Buffer<Nat8>(0);
    for (item in subaccount.vals()) {
      buffer.add(item);
    };
    Buffer.toArray(buffer);
  };

  // Logic part

  public func getMintingAccount() : async Principal {
    let acc = await Ledger.icrc1_minting_account();
    switch (acc) {
      case null Principal.fromText("aaaaa-aa");
      case (?account) account.owner;
    };
  };

  public func getUserBalance(user : Principal) : async Nat {
    await Ledger.icrc1_balance_by_principal({ owner = user; subaccount = null });
  };

  public func userBalanceByBranch(user : Principal, branch : Nat8) : async Nat {
    let sub = await createSubaccountByBranch(branch);
    let addSub : Ledger.Account = {
      owner = user;
      subaccount = ?subaccountToNatArray(sub);
    };
    await Ledger.icrc1_balance_of(addSub);
  };

  // Increase reputation
  // using pre_mint_account as from

  public func awardToken(to : Types.Account, amount : Ledger.Tokens) : async Result<TxIndex, TransferFromError> {
    let memo : ?Ledger.Memo = null;
    let fee : ?Ledger.Tokens = null;
    let created_at_time : ?Ledger.Timestamp = ?Nat64.fromIntWrap(Time.now());
    let new_sub = switch (to.subaccount) {
      case null { [] };
      case (?sub) { subaccountToNatArray(sub) };
    };
    let acc : Ledger.Account = { owner = to.owner; subaccount = ?new_sub };
    let res = await Ledger.icrc2_transfer_from({
      from = pre_mint_account;
      to = acc;
      amount = amount;
      fee = fee;
      memo = memo;
      created_at_time = created_at_time;
    });
  };

  public func sendToken(from : Ledger.Account, to : Ledger.Account, amount : Ledger.Tokens) : async Result<TxIndex, TransferFromError> {
    let sender : ?Ledger.Subaccount = from.subaccount;
    let memo : ?Ledger.Memo = null;
    let fee : ?Ledger.Tokens = null;
    let created_at_time : ?Ledger.Timestamp = ?Nat64.fromIntWrap(Time.now());
    let a : Ledger.Tokens = amount;
    let acc : Ledger.Account = to;
    let res = await Ledger.icrc2_transfer_from({
      from = from;
      to = to;
      amount = amount;
      fee = fee;
      memo = memo;
      created_at_time = created_at_time;
    });
    ignore await awardIncenitive(from, 1);
    res;
  };

  // Decrease reputation
  public func burnToken(from : Ledger.Account, amount : Ledger.Tokens) : async Result<TxIndex, TransferFromError> {
    // TODO caller validation
    let sender : ?Ledger.Subaccount = from.subaccount;
    let memo : ?Ledger.Memo = null;
    let fee : ?Ledger.Tokens = ?0;
    let created_at_time : ?Ledger.Timestamp = ?Nat64.fromIntWrap(Time.now());
    let a : Ledger.Tokens = amount;
    let res = await Ledger.icrc2_transfer_from({
      from = from;
      to = pre_mint_account;
      amount = amount;
      fee = fee;
      memo = memo;
      created_at_time = created_at_time;
    });
  };

  // TODO
  public func askForBurn(
    requester : Account,
    from : Account,
    document : Types.DocId,
    tags : [Types.Tag],
    amount : Ledger.Tokens,
  ) : async Result<TxIndex, Types.TransferBurnError> {
    // check requester's balance
    let branch = getBranchFromSubaccount(requester.subaccount);
    let balance_requester = await userBalanceByBranch(requester.owner, branch);
    // check from balance
    let branch_author = getBranchFromSubaccount(from.subaccount);
    if (not Nat8.equal(branch, branch_author)) return #Err(#WrongBranch { current_branch = branch; target_branch = branch_author });
    let balance_author = await userBalanceByBranch(from.owner, branch);
    if (balance_requester < balance_author) return #Err(#InsufficientReputation { current_branch = branch; balance = balance_author });
    // TODO check document's tags for equity to requester's subaccount
    // let checkTag = Array.find<Types.Tag>(tags, func x = (x == branch));

    // TODO burn requester's token
    // TODO burn from token
    // TODO create history log

    return #Err(#TemporarilyUnavailable);
  };

  // Incenitive
  public func awardIncenitive(to : Ledger.Account, amount : Ledger.Tokens) : async Result<TxIndex, TransferFromError> {
    let memo : ?Ledger.Memo = null;
    let created_at_time : ?Ledger.Timestamp = ?Nat64.fromIntWrap(Time.now());
    let receiver : Ledger.Account = {
      owner = to.owner;
      subaccount = ?(subaccountToNatArray(await createSubaccountByBranch(1)));
    };
    let res = await Ledger.icrc2_transfer_from({
      from = pre_mint_account;
      to = receiver;
      amount = amount;
      fee = ?0;
      memo = memo;
      created_at_time = created_at_time;
    });
  };

  // Scheduler part
  system func timer(setGlobalTimer : Nat64 -> ()) : async () {
    let next = Nat64.fromIntWrap(Time.now()) + 86_400_000_000_000;
    setGlobalTimer(next); // absolute time in nanoseconds
    distributeTokens();
  };

  func distributeTokens() : () {
    // scan log for experts and specialist accounts and add them to maps)
    // calculate their balances
    // mint tokens to "1" subaccounts
    // TODO batch mint tokens
  };

  // func distributeTokens(user: Principal, branch : Nat8, value : Nat) : async Result<TxIndex, TransferFromError>  {
  //  awardToken({owner=user; subaccount=null;}, value);
  // };

  func lookingForExperts() : ExpertMap {
    // TODO batch check balance
    let balance_requester = await userBalanceByBranch(requester.owner, branch);
  };
};
