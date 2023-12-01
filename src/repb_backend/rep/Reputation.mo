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

import Logger "../hub/utils/Logger";
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

  stable var state : Logger.State<Text> = Logger.new<Text>(0, null);
  let logger = Logger.Logger<Text>(state);
  let prefix = "[" # Int.toText(Time.now() / 1_000_000_000) # "] ";

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

  var userReputation = Map.HashMap<Principal, Map.HashMap<Branch, Nat>>(1, Principal.equal, Principal.hash);
  // map tag : branchId
  var tagMap = TrieMap.TrieMap<Text, Branch>(Text.equal, Text.hash);
  var userSharedReputation = Map.HashMap<Principal, Map.HashMap<Branch, Nat>>(1, Principal.equal, Principal.hash);

  public func viewLogs(end : Nat) : async [Text] {
    let view = logger.view(0, end);
    let result = Buffer.Buffer<Text>(1);
    for (message in view.messages.vals()) {
      result.add(message);
    };
    Buffer.toArray(result);
  };

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

  /*
    Test updateDocHistory
  */

  public func testUpdateDocHistory({
    user : Principal;
    docId : DocId;
    value : Nat8;
    comment : Text;
  }) : async Text {
    comment;
  };

  public func test2UpdateDocHistory() : async Types.Result<DocHistory, Types.CommonError> {
    let user = Principal.fromText("aaaaa-aa");
    let docId = 1;
    let value : Nat8 = 1;
    let comment = "Test comment";

    let expectedResult : Types.Result<DocHistory, Types.CommonError> = #Ok({
      docId = docId;
      timestamp = Time.now();
      changedBy = user;
      value = value;
      comment = comment;
    });
    let result = await updateDocHistory({
      user = user;
      docId = docId;
      value = value;
      comment = comment;
    });

    switch (result) {
      case (#Ok(docHistory)) {
        if (docHistory.docId == docId) {
          return expectedResult; //"updateDocHistory test passed";
        } else {
          return #Err(#TemporarilyUnavailable); //"updateDocHistory test failed";
        };
      };
      case (#Err(err)) {
        return #Err(#TemporarilyUnavailable);
      };
    };
  };

  //Method for event handling

  public func eventHandler({
    user : Principal;
    docId : Nat;
    value : Nat8;
    comment : Text;
  }) : async Text {
    logger.append([prefix # " Method eventHandler starts, calling method updateDocHistory"]);

    let result = await updateDocHistory({
      user = user;
      docId = docId;
      value = value;
      comment = comment;
    });
    switch (result) {
      case (#Ok(docHistory)) {
        logger.append([prefix # " eventHandler: updateDocHistory result was received"]);
        "Event InstantReputationUpdateEvent was handled";
      };
      case (#Err(err)) {
        logger.append([prefix # " eventHandler: updateDocHistory result was received with error"]);
        "Event InstantReputationUpdateEvent was handled with error";
      };
    };
  };

  //Key method for update reputation based on document
  public func updateDocHistory({
    user : Principal;
    docId : Nat;
    value : Nat8;
    comment : Text;
  }) : async Types.Result<DocHistory, Types.CommonError> {
    logger.append([prefix # " Method updateDocHistory starts, checking document"]);

    let doc = switch (checkDocument(docId)) {
      case (#Err(err)) {
        logger.append([prefix # " updateDocHistory: document check failed"]);
        return #Err(err);
      };
      case (#Ok(doc)) {
        logger.append([prefix # " updateDocHistory: document ok"]);
        doc;
      };
    };
    let newDocHistory : DocHistory = {
      docId = docId;
      timestamp = Time.now();
      changedBy = user;
      value = value;
      comment = comment;
    };
    docHistory.put(docId, Array.append(Option.get(docHistory.get(docId), []), [newDocHistory]));
    logger.append([prefix # " updateDocHistory: checking tags"]);

    let branch = await getBranchByTagName(doc.tags[0]);
    logger.append([prefix # " updateDocHistory: branch found by tag " # doc.tags[0] # " is " # Nat8.toText(branch) # " for user " # Principal.toText(user) # " with value " # Nat8.toText(value) # " and comment " # comment]);

    let res = await setUserReputation(user, branch, Nat8.toNat(value));
    logger.append([prefix # " updateDocHistory: setUserReputation result "]);
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
      case null {
        logger.append([prefix # " getBranchByTagName: branch not found by tag " # tag]);
        Nat8.fromNat(0);
      };
      case (?br) {
        logger.append([prefix # " getBranchByTagName: branch found by tag " # tag # " is " # Nat8.toText(br)]);
        br;
      };
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

  // Stable tags, docHistory and user reputation storage
  stable var tagEntries : [(Tag, Branch)] = [];
  stable var userReputationArray : [(Principal, [(Branch, Nat)])] = [];
  stable var docHistoryArray : [(DocId, [DocHistory])] = [];
  system func preupgrade() {
    for ((tag, branch) in tagMap.entries()) {
      tagEntries := Array.append(tagEntries, [(tag, branch)]);
    };
    for ((user, entry) in userReputation.entries()) {
      var buffer = Buffer.Buffer<(Branch, Nat)>(0);
      for ((branch, value) in entry.entries()) {
        buffer.add((branch, value));
      };
      userReputationArray := Array.append(userReputationArray, [(user, Buffer.toArray(buffer))]);
    };
    for ((docId, entry) in docHistory.entries()) {
      var buffer = Buffer.Buffer<DocHistory>(0);
      for (item in entry.vals()) {
        buffer.add(item);
      };
      docHistoryArray := Array.append(docHistoryArray, [(docId, Buffer.toArray(buffer))]);
    };
  };

  system func postupgrade() {
    for ((tag, branch) in tagEntries.vals()) {
      tagMap.put(tag, branch);
    };
    tagEntries := [];
    for ((user, entry) in userReputationArray.vals()) {
      var map = Map.HashMap<Branch, Nat>(0, Nat8.equal, hashBranch);
      for ((branch, value) in entry.vals()) {
        map.put(branch, value);
      };
      userReputation.put(user, map);
    };
    userReputationArray := [];
    for ((docId, entry) in docHistoryArray.vals()) {
      docHistory.put(docId, entry);
    };
    docHistoryArray := [];
  };

  public func clearTags() : async Bool {
    tagMap := TrieMap.TrieMap<Text, Branch>(Text.equal, Text.hash);
    true;
  };

  public func clearUserReputation() : async Bool {
    userReputation := Map.HashMap<Principal, Map.HashMap<Branch, Nat>>(0, Principal.equal, Principal.hash);
    true;
  };

  public func clearDocHistory() : async Bool {
    docHistory := Map.HashMap<DocId, [DocHistory]>(0, Nat.equal, Hash.hash);
    true;
  };
};
