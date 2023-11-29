import Ledger "canister:ledger";

import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Hash "mo:base/Hash";
import Map "mo:base/HashMap";
import HashMap "mo:base/HashMap";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Time "mo:base/Time";
import TrieMap "mo:base/TrieMap";

import Types "./Types";

actor {
  type Document = Types.Document;
  type Branch = Types.Branch;
  type DocId = Types.DocId;
  type Tag = Types.Tag;
  type DocHistory = Types.DocumentHistory;

  type DocDAO = {
    // main_branch : Tag;
    tags : [Tag];
    content : Text;
    imageLink : Text;
  };

  type Account = Types.Account; //{ owner : Principal; subaccount : ?Subaccount };
  type Subaccount = Types.Subaccount; //Blob;
  type Tokens = Types.Tokens; //Nat;
  type Memo = Types.Memo;
  type Timestamp = Types.Timestamp; //Nat64;
  type Duration = Types.Duration;
  type TxIndex = Types.TxIndex;
  type TxLog = Buffer.Buffer<Types.Transaction>;

  type Value = Types.Value;
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

  let hashBranch = func(x : Branch) : Nat32 {
    return Nat32.fromNat(Nat8.toNat(x * 7));
  };

  let ic_rep_ledger = "ajw6q-6qaaa-aaaal-adgna-cai";

  stable var documents : [Document] = [];
  let emptyBuffer = Buffer.Buffer<(Principal, [DocId])>(0);
  stable var userDocuments : [(Principal, [DocId])] = Buffer.toArray(emptyBuffer);
  var userDocumentMap = Map.HashMap<Principal, [DocId]>(10, Principal.equal, Principal.hash);

  // map docId - docHistory
  var docHistory = Map.HashMap<DocId, [DocHistory]>(10, Nat.equal, Hash.hash);
  // map userId - [ Reputation ] or map userId - Map (branchId : value)
  // TODO add stable storage for reputation
  var userReputation = Map.HashMap<Principal, Map.HashMap<Branch, Nat>>(1, Principal.equal, Principal.hash);
  // map tag : branchId
  var tagMap = TrieMap.TrieMap<Text, Branch>(Text.equal, Text.hash);
  // TODO add stable storage for shared reputation
  var userSharedReputation = Map.HashMap<Principal, Map.HashMap<Branch, Nat>>(1, Principal.equal, Principal.hash);

  public func getUserReputation(user : Principal) : async Nat {
    let balance = await getUserBalance(user);
  };

  public func getReputationByBranch(user : Principal, branchId : Nat8) : async ?(Branch, Nat) {
    // Implement logic to get reputation value in a specific branch
    let res = await userBalanceByBranch(user, branchId);
    return ?(branchId, res);
  };

  func subaccountToNatArray(subaccount : Types.Subaccount) : [Nat8] {
    var buffer = Buffer.Buffer<Nat8>(0);
    for (item in subaccount.vals()) {
      buffer.add(item);
    };
    Buffer.toArray(buffer);
  };

  // set reputation value for a given user in a specific branch
  public func setUserReputation(user : Principal, branchId : Nat8, value : Nat) : async Types.Result<(Types.Account, Nat), Types.TransferBurnError> {
    let sub = await createSubaccountByBranch(branchId);

    let res = await awardToken({ owner = user; subaccount = ?Blob.fromArray(subaccountToNatArray(sub)) }, value);
    switch (res) {
      case (#Ok(id)) {
        ignore saveReputationChange(user, branchId, value);
        let bal = await getReputationByBranch(user, branchId);
        let res = switch (bal) {
          case null { 0 };
          case (?(branch, value)) { value };
        };
        return #Ok({ owner = user; subaccount = ?sub }, res);
      };
      case (#Err(err)) {
        return #Err(err);
      };
    };
  };

  func saveReputationChange(user : Principal, branchId : Nat8, value : Nat) : Map.HashMap<Branch, Nat> {
    let state = userReputation.get(user);
    let map = switch (state) {
      case null { Map.HashMap<Branch, Nat>(0, Nat8.equal, hashBranch) };
      case (?map) {
        map.put(branchId, value);
        map;
      };
    };
  };

  // universal method for award/burn reputation
  public func changeReputation(user : Principal, branchId : Branch, value : Int) : async Types.ChangeResult {
    let res : Types.Change = (user, branchId, value);
    // TODO validation: check ownership

    // TODO get exist reputation : getUserReputation

    // TODO change reputation:  setUserReputation

    // ?TODO save new state

    // return new state

    return #Ok(res);
  };

  // Shared part

  public func sharedReputationDistrube() : async Types.Result<Text, Types.TransferBurnError> {
    // let default_acc = { owner = Principal.fromText("aaaaa-aa"); subaccount = null };
    var res = #Ok("Shared ");
    var sum = 0;
    let mint_acc = await getMintingAccount();
    label one for ((user, entry) in userReputation.entries()) {
      if (Principal.equal(mint_acc, user)) continue one;
      var balance = 0;
      for ((branch, value) in entry.entries()) {
        balance += value;
      };
      // switch on error, return #Err
      let result = await awardToken({ owner = user; subaccount = null }, balance);
      userSharedReputation.put(user, entry);
      res := switch (result) {
        case (#Ok(id)) {
          sum += 1;
          #Ok(" Shared");
        };
        case (#Err(err)) return #Err(err);
      };
    };
    return #Ok("Tokens were shared  to " # Nat.toText(sum) # " accounts");
  };

  // Doctoken part

  public func getAllDocs() : async [Document] {
    documents;
  };

  public func getDocumentsByUser(user : Principal) : async [Document] {
    let docIdList = Option.get(userDocumentMap.get(user), []);
    var result = Buffer.Buffer<Document>(1);
    label one for (documentId in docIdList.vals()) {
      let document = Array.find<Document>(documents, func doc = Nat.equal(documentId, doc.docId));
      switch (document) {
        case null continue one;
        case (?d) result.add(d);
      };
    };
    Buffer.toArray(result);
  };

  public func getDocumentById(id : DocId) : async Types.Result<Document, Text> {
    let document = Array.find<Document>(documents, func doc = Nat.equal(id, doc.docId));
    switch (document) {
      case null #Err("No documents found by id " # Nat.toText(id));
      case (?doc) #Ok(doc);
    };
  };

  public func getDocumentsByBranch(branch : Branch) : async [Document] {
    let document = Array.find<Document>(documents, func doc = Text.equal(getTagByBranch(branch), doc.tags[0]));

    switch (document) {
      case null [];
      case (?doc)[doc];
    };
  };

  public func setDocumentByUser(user : Principal, branch : Branch, document : DocDAO) : async Types.Result<Document, Text> {
    let nextId = documents.size();
    let docList = Option.get(userDocumentMap.get(user), []);
    let newTags = Buffer.Buffer<Tag>(1);
    newTags.add(getTagByBranch(branch));
    let existBranches = Buffer.fromArray<Tag>(document.tags);
    newTags.append(existBranches);
    let newDoc = {
      docId = nextId;
      tags = Buffer.toArray(newTags);
      content = document.content;
      imageLink = document.imageLink;
    };
    documents := Array.append(documents, [newDoc]);
    let newList = Array.append(docList, [nextId]);
    userDocumentMap.put(user, newList);
    // TODO documents.add(newDoc) on postupgrade
    return #Ok(newDoc);
  };

  //Key method for update reputation based on document
  public func updateDocHistory(user : Principal, docId : DocId, value : Nat8, comment : Text) : async Types.Result<DocHistory, Types.CommonError> {
    let doc = switch (checkDocument(docId)) {
      case (#Err(err)) { return #Err(err) };
      case (#Ok(doc)) { doc };
    };
    let newDocHistory : DocHistory = {
      docId = docId;
      timestamp = Time.now();
      changedBy = user;
      value = value;
      comment = comment;
    };
    docHistory.put(docId, Array.append(Option.get(docHistory.get(docId), []), [newDocHistory]));
    let branch = await getBranchByTagName(doc.tags[0]);
    ignore await setUserReputation(user, branch, Nat8.toNat(value));
    #Ok(newDocHistory);
  };

  public func getDocHistory(docId : DocId) : async [DocHistory] {
    Option.get(docHistory.get(docId), []);
  };

  public func getDocReputation(docId : DocId) : async Nat {
    var res = 0;
    let history = await getDocHistory(docId);
    for (his in history.vals()) {
      res += Nat8.toNat(his.value);
    };
    res;
  };

  func checkDocument(docId : DocId) : Types.Result<Document, Types.CommonError> {
    let checkDocument = Array.find<Document>(documents, func doc = Nat.equal(docId, doc.docId));
    let doc = switch (checkDocument) {
      case null {
        #Err(#NotFound { message = "No document found by id "; docId = docId });
      };
      case (?doc) { #Ok(doc) };
    };
  };

  public func newDocument(user : Principal, doc : DocDAO) : async Types.Result<DocId, Types.CommonError> {
    let userDocs = userDocumentMap.get(user);
    // TODO choose branch: chooseTag(preferBranch, doc);
    let branch_opt = Nat.fromText(doc.tags[0]);
    let branch = switch (branch_opt) {
      case null return #Err(#NotFound { message = "Cannot find out the branch " # doc.tags[0]; docId = 0 });
      case (?br) Nat8.fromNat(br);
    };
    let document = await setDocumentByUser(user, branch, doc);
    return #Err(#TemporarilyUnavailable);
  };

  public func createDocument(user : Principal, branchs : [Nat8], content : Text, imageLink : Text) : async Document {
    var tags = Buffer.Buffer<Text>(1);
    for (item in branchs.vals()) {
      tags.add(getTagByBranch(item));
    };
    let newDoc = {
      docId = 0;
      tags = Buffer.toArray(tags);
      content = content;
      imageLink = imageLink;
    };
  };

  // Tag part
  public func getBranchByTagName(tag : Tag) : async Branch {
    let res = switch (tagMap.get(tag)) {
      case null Nat8.fromNat(0);
      case (?br) br;
    };
    res;
  };

  func getTagByBranch(branch : Branch) : Tag {
    for ((key, value) in tagMap.entries()) {
      if (Nat8.equal(branch, value)) return key;
    };
    "0";
  };

  public func setNewTag(tag : Tag) : async Types.Result<(Tag, Branch), (Tag, Branch)> {
    switch (tagMap.get(tag)) {
      case null {
        // TODO Create a hierarchical system of industries
        let newBranch = tagMap.size();
        tagMap.put(tag, Nat8.fromNat(newBranch));
        #Ok(tag, Nat8.fromNat(newBranch));
      };
      case (?br) #Err(tag, br);
    };
  };

  public func getTags() : async [(Tag, Branch)] {
    let res = Buffer.Buffer<(Tag, Branch)>(1);
    for ((key, value) in tagMap.entries()) {
      res.add(key, value);
    };
    Buffer.toArray(res);
  };

  /*
Token Handling
*/
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
  let token_symbol = "AVAS";
  let token_fee = 6;
  let max_supply = 1_000_000;
  let token_init_balance = 100_000;
  let min_burn_amount = 1;
  let decimals = 3;

  func add_decimals(n : Nat) : Nat {
    n * 10 ** decimals;
  };

  //ledger part

  let permittedDriftNanos : Duration = 60_000_000_000;
  let transactionWindowNanos : Duration = 24 * 60 * 60 * 1_000_000_000;
  let defaultSubaccount : [Nat8] = Array.freeze<Nat8>(Array.init(32, 0 : Nat8));

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

  // func subaccountToNatArray(subaccount : Subaccount) : [Nat8] {
  //   var buffer = Buffer.Buffer<Nat8>(0);
  //   for (item in subaccount.vals()) {
  //     buffer.add(item);
  //   };
  //   Buffer.toArray(buffer);
  // };

  // Logic part

  public func getMintingAccount() : async Principal {
    let acc = await Ledger.icrc1_minting_account();
    switch (acc) {
      case null main_principal;
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

  public func awardToken(to : Types.Account, amount : Ledger.Tokens) : async Types.Result<TxIndex, TransferFromError> {
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

  public func sendToken(from : Ledger.Account, to : Ledger.Account, amount : Ledger.Tokens) : async Types.Result<TxIndex, TransferFromError> {
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
  public func burnToken(from : Ledger.Account, amount : Ledger.Tokens) : async Types.Result<TxIndex, TransferFromError> {
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
  ) : async Types.Result<TxIndex, Types.TransferBurnError> {
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
  public func awardIncenitive(to : Ledger.Account, amount : Ledger.Tokens) : async Types.Result<TxIndex, TransferFromError> {
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

    // Scheduler part
    // public func distributeTokens(user: Principal, branch : Nat8, value : Nat) : async Result<Bool, TransferFromError> {
    //   sendToken
    // };
  };
};
