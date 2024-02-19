import Ledger "canister:ledger";

import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Cycles "mo:base/ExperimentalCycles";
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
import Trie "mo:base/Trie";
import TrieMap "mo:base/TrieMap";

import Types "./Types";
import Logger "./utils/Logger";
import Utils "./utils/Utils";

actor {
  type Document = Types.Document;
  type Category = Types.Category;
  type DocId = Types.DocId;
  type DocHistory = Types.DocumentHistory;

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

  type Trie<K, V> = Trie.Trie<K, V>;
  type Key<K> = Trie.Key<K>;

  type Set<T> = Trie.Trie<T, ()>;

  // Logger

  stable var state : Logger.State<Text> = Logger.new<Text>(0, null);
  let logger = Logger.Logger<Text>(state);
  var prefix = Utils.timestampToDate();

  // Cosntants
  let ic_rep_ledger = "ajw6q-6qaaa-aaaal-adgna-cai";
  let default_hub_canister = Principal.fromText("a3qjj-saaaa-aaaal-adgoa-cai");
  let default_minting_account = Principal.fromText("oa7ab-4elxo-r5ooc-a23ga-lheml-we4wg-z5iuo-ery2n-57uyv-u234p-pae");
  let default_doctoken_deployer_reputation = 100;
  let default_award_fee = 100_000_000;

  let emptyBuffer = Buffer.Buffer<(Principal, [DocId])>(0);

  // map docId - docHistory
  var docHistory = Map.HashMap<DocId, [DocHistory]>(10, Nat.equal, Hash.hash);

  var userReputation = Map.HashMap<Principal, Map.HashMap<Category, Nat>>(1, Principal.equal, Principal.hash);
  var tagCifer = TrieMap.TrieMap<Text, Text>(Text.equal, Text.hash); // Key - Category, Value - Cifer
  var userSharedReputation = Map.HashMap<Principal, Map.HashMap<Category, Nat>>(1, Principal.equal, Principal.hash);

  let ciferSubaccount = Map.HashMap<Text, Types.Subaccount>(1, Text.equal, Text.hash);

  let specialistMap = Map.HashMap<Principal, [(Category, Nat)]>(1, Principal.equal, Principal.hash); // Key: user, value: [(Category, Balance)]

  let expertMap = Map.HashMap<Principal, [(Category, Nat)]>(1, Principal.equal, Principal.hash); // Key: user, value: [(Category, Balance)]

  private func _keyFromPrincipal(p : Principal) : Key<Principal> {
    { hash = Principal.hash(p); key = p };
  };

  // Whitelist (Allowlist)
  private func initWhitelist() : Set<Principal> {
    let emptyTrie = Trie.empty<Principal, ()>();
    let trieWithFirstKey = Trie.put(emptyTrie, _keyFromPrincipal(default_hub_canister), Principal.equal, ()).0;
    let trieWithSecondKey = Trie.put(trieWithFirstKey, _keyFromPrincipal(default_minting_account), Principal.equal, ()).0;
    return trieWithSecondKey;
  };

  private stable var whitelist : Set<Principal> = initWhitelist();

  public shared ({ caller }) func addUser(userId : Principal) : async Bool {
    if (await isUserInWhitelist(caller)) whitelist := Trie.put(whitelist, _keyFromPrincipal userId, Principal.equal, ()).0;
    await isUserInWhitelist(userId);
  };

  public shared ({ caller }) func removeUser(userId : Principal) : async Bool {
    if ((await isUserInWhitelist(caller)) and Trie.size(whitelist) > 1) whitelist := Trie.remove(whitelist, _keyFromPrincipal userId, Principal.equal).0;
    not (await isUserInWhitelist(userId));
  };

  public query func isUserInWhitelist(userId : Principal) : async Bool {
    switch (Trie.get(whitelist, _keyFromPrincipal(userId), Principal.equal)) {
      case (null) { false }; // User not found
      case (_) { true }; // User found
    };
  };

  // Init reputation for new Doctoken deployers

  stable var doctokenDeployers : Set<Principal> = Trie.empty<Principal, ()>();

  public func initDoctokenDeployerReputation(userId : Principal, subaccount : ?Types.Subaccount) : async () {
    let res = await awardToken({ owner = userId; subaccount = subaccount }, default_doctoken_deployer_reputation);
    doctokenDeployers := Trie.put(doctokenDeployers, _keyFromPrincipal(userId), Principal.equal, ()).0;
  };

  public query func getCiferByCategory(tag : Text) : async ?Text {
    tagCifer.get(tag);
  };

  public query func getTagByCifer(cifer : Text) : async [(Text, Text)] {
    let newMap = TrieMap.mapFilter<Text, Text, Text>(
      tagCifer,
      Text.equal,
      Text.hash,
      func(key, value) = if (Text.startsWith(value, #text cifer)) { ?value } else {
        null;
      },
    );
    Iter.toArray(newMap.entries());
  };

  func ciferToAvaFormat(cifer : Text) : Text {
    Utils.convertCiferToDottedFormat(cifer);
  };

  public func getSubaccountByCategory(category : Category) : async ?Types.Subaccount {
    let cifer = await getCiferByCategory(category);

    //TODO check for collisions

    switch (cifer) {
      case null {
        // Missing cifer means missing category in database
        null;
      };
      case (?c) {
        switch (ciferSubaccount.get(c)) {
          case (null) {
            // An existing CIFER that does not have a subaccount means that we need to create a new one
            ?createNewSubaccount(category);
          };
          case (?sub) { ?sub };
        };
      };
    };
  };

  func createNewSubaccount(cifer : Text) : Types.Subaccount {
    var bytes = Blob.toArray(Text.encodeUtf8(cifer));
    // Cut to 32 bytes if encoded text is too long
    if (bytes.size() > 32) bytes := Array.subArray<Nat8>(bytes, 0, 32);
    // Pad with zeros if encoded text is too short
    if (bytes.size() < 32) {
      let padding = Array.freeze(Array.init<Nat8>((32 - bytes.size()), 0 : Nat8));
      bytes := Array.append(bytes, padding);
    };
    let subaccount = Blob.fromArray(bytes);
    ciferSubaccount.put(cifer, subaccount);
    return subaccount;
  };

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

  public func getReputationByCategory(user : Principal, category : Text) : async ?(Category, Nat) {
    let res = await userBalanceByCategory(user, category);
    return ?(category, res);
  };

  // set reputation value for a given user in a specific branch
  func setUserReputation(reviewer : Principal, user : Principal, category : Text, value : Nat) : async Types.Result<(Types.Account, Nat), Types.TransferBurnError> {
    // logger.append([prefix # " setUserReputation starts, calling method getSubaccountByCategory"]);
    let sub : ?Subaccount = await getSubaccountByCategory(category);
    if (sub == null) return #Err(#NotFound { message = "Cannot find out the category " # category; docId = 0 });
    // logger.append([prefix # " setUserReputation: calling method awardToken"]);
    let to : Types.Account = { owner = user; subaccount = sub };

    // TODO decrease reviewer distributed reputation

    let res = await awardToken(to, value);
    switch (res) {
      case (#Ok(id)) {
        // logger.append([prefix # " setUserReputation: awardToken #Ok result was received: " # Nat.toText(id)]);

        // logger.append([prefix # " setUserReputation: calling getReputationByBranch"]);
        let bal = Option.get(await getReputationByCategory(user, category), ("", 0)).1;
        if (bal >= 100) {
          updateSpecialistMap(user, category, bal);
          if (bal >= 500) updateExpertMap(user, category, bal);
        };
        logger.append([prefix # " setUserReputation: result for: " # Principal.toText(user) # ", category = " # category]);
        let saveRepChangeResult = saveReputationChange(user, category, bal);
        let res = switch (bal) {
          case (0) {
            logger.append([prefix # " setUserReputation: Error: getReputationByBranch result balance is null after award"]);
            0;
          };
          case (value) {
            logger.append([prefix # " setUserReputation: getReputationByBranch result was received: category = " # category # ", value = " # Nat.toText(value)]);
            value;
          };
        };
        return #Ok({ owner = user; subaccount = sub }, res);
      };
      case (#Err(err)) {
        logger.append([prefix # " ERROR: setUserReputation: awardToken #Err result was received"]);
        return #Err(err);
      };
    };
  };

  func updateSpecialistMap(user : Principal, category : Category, bal : Nat) {
    let value = specialistMap.get(user);
    switch (value) {
      // New specialist added
      case null specialistMap.put(user, [(category, bal)]);
      case (?spec) {
        let updatedCategory = Utils.pushIntoArray<(Category, Nat)>((category, bal), spec);
        specialistMap.put(user, updatedCategory);
        logger.append([prefix # " updateSpecialistMap: user " # Principal.toText(user) # " was added to specialistMap"]);
      };
    };
  };

  func updateExpertMap(user : Principal, category : Text, bal : Nat) {
    let value = expertMap.get(user);
    switch (value) {
      // New expert added
      case null expertMap.put(user, [(category, bal)]);
      case (?spec) {
        let updatedCategory = Utils.pushIntoArray<(Category, Nat)>((category, bal), spec);
        expertMap.put(user, updatedCategory);
      };
    };
  };

  public func getBeginnerCategories(user : Principal) : async [(Category, Nat)] {
    let categories = userReputation.get(user);

    let resMap = switch (categories) {
      case (null) {
        Map.HashMap<Category, Nat>(0, Text.equal, Text.hash);
      };
      case (?categoriesMap) {
        // remove specialist and expert categories
        Map.mapFilter<Category, Nat, Nat>(
          categoriesMap,
          Text.equal,
          Text.hash,
          func(category : Category, value : Nat) : ?Nat {
            if (value >= 100) {
              null // remove category
            } else {
              ?value // Hold category
            };
          },
        );
      };
    };
    return Iter.toArray(resMap.entries());
  };

  public query func getSpecialists() : async [(Principal, [(Category, Nat)])] {
    Iter.toArray(specialistMap.entries());
  };

  public query func getSpecialistCategories(user : Principal) : async [(Category, Nat)] {
    let result = switch (specialistMap.get(user)) {
      case null [];
      case (?array) array;
    };
  };

  public query func getExperts() : async [(Principal, [(Category, Nat)])] {
    Iter.toArray(expertMap.entries());
  };

  public query func getExpertCategories(user : Principal) : async [(Category, Nat)] {
    let result = switch (expertMap.get(user)) {
      case null [];
      case (?array) array;
    };
  };

  func saveReputationChange(user : Principal, category : Text, value : Nat) : (Category, Nat) {
    logger.append([prefix # " saveReputationChange: user " # Principal.toText(user) # ", category = " # category # ", value = " # Nat.toText(value)]);
    let userCategories = switch (userReputation.get(user)) {
      case (null) Map.HashMap<Category, Nat>(1, Text.equal, Text.hash);
      case (?categories) categories;
    };
    userCategories.put(category, value);
    userReputation.put(user, userCategories);
    (category, value);
  };

  // Shared part

  func sharedReputationDistrube() : async Types.Result<Text, Types.TransferBurnError> {
    // let default_acc = { owner = Principal.fromText("aaaaa-aa"); subaccount = null };
    var res = #Ok("Shared ");
    var sum = 0;
    let mint_acc = await getMintingAccountPrincipal();
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

  //Method for event handling

  public shared ({ caller }) func eventHandler({
    user : Principal;
    reviewer : ?Principal;
    value : ?Nat;
    category : Text;
    timestamp : Nat;
    source : (Text, Nat); // (doctoken_canisterId, documentId)
    comment : ?Text;
    metadata : ?[(Text, Types.Metadata)];
  }) : async Types.Result<Nat, Text> {
    let amount = Cycles.available();
    ignore Cycles.accept(amount);

    // Only whitelisted canisters allow
    if (not (await isUserInWhitelist(caller))) return #Err("Unauthorized");
    let prefix = Utils.timestampToDate();
    // If reviewer present, then it is a Instant Reputation Change event
    switch (reviewer) {
      case (?r) {
        // document check
        let doc = switch (await checkDocument(source.0, source.1)) {
          case (#Err(err)) {
            logger.append([prefix # " eventHandler: document check failed"]);
            return #Err("Error: document check failed");
          };
          case (#Ok(document)) {
            logger.append([prefix # " eventHandler: document №" # Nat.toText(document.tokenId) # "ok"]);
            document;
          };
        };
        let final_comment = switch (comment) {
          case (?c) c;
          case null "";
        };
        let final_value : Nat8 = Nat8.fromNat(Option.get<Nat>(value, 0));

        // TODO Set Init reputation Category to "Motoko" for doctoken deployer
        var sub : ?Subaccount = await getSubaccountByCategory(category);
        if (sub == null) sub := await getSubaccountByCategory(doc.categories[0]);
        // Reviewer's reputation check
        let reviewer_reputation = Trie.get(doctokenDeployers, _keyFromPrincipal(r), Principal.equal);
        switch (reviewer_reputation) {
          case (null) {
            // doctoken deployer reputation not initialized, initialize it
            await initDoctokenDeployerReputation(r, sub);
          };
          case (?rep) {};
        };

        // TODO Reputation balance check
        // let userReputation = await getUserReputation(user);
        // let reviewerReputation = await getUserReputation(r);
        // if (userReputation >= reviewerReputation) return #Err("Insufficient Reputation, balance = " # Nat.toText(reviewerReputation) # ", user reputation = " # Nat.toText(userReputation));

        let result = await updateDocHistory({
          reviewer = r;
          user = user;
          doc = doc;
          value = final_value;
          comment = final_comment;
        });

        switch (result) {
          case (#Ok(docHistory)) {
            let user_balance = await getUserBalance(user);
            logger.append([prefix # " eventHandler: new user balance was received: " # Nat.toText(user_balance)]);
            #Ok(user_balance);
          };
          case (#Err(err)) {
            logger.append([prefix # " eventHandler: updateDocHistory result was received with error"]);
            #Err("Event InstantReputationUpdateEvent was handled with error");
          };
        };
      };
      case (null) {
        logger.append([prefix # " eventHandler: reviewer is null, cannot update reputation"]);
        #Err("Event InstantReputationUpdateEvent was handled with error");
      };
    };
  };

  //Key method for update reputation based on document
  func updateDocHistory({
    reviewer : Principal;
    user : Principal;
    doc : Document;
    value : Nat8;
    comment : Text;
  }) : async Types.Result<DocHistory, Types.CommonError> {
    logger.append([prefix # " Method updateDocHistory starts, checking document"]);

    let newDocHistory : DocHistory = {
      docId = doc.tokenId;
      timestamp = Time.now();
      changedBy = reviewer;
      value = value;
      comment = comment;
    };

    docHistory.put(doc.tokenId, Array.append(Option.get(docHistory.get(doc.tokenId), []), [newDocHistory]));
    // logger.append([prefix # " updateDocHistory: checking tags"]);

    let category = doc.categories[0];
    // logger.append([prefix # " updateDocHistory: branch found by tag " # doc.categories[0] # " is " # category # " for user " # Principal.toText(user) # " with value " # Nat8.toText(value) # " and comment " # comment]);

    let res = await setUserReputation(reviewer, user, category, Nat8.toNat(value));
    switch (res) {
      case (#Ok(account, value)) {
        logger.append([prefix # " updateDocHistory: setUserReputation result: account= " # Principal.toText(account.owner) # ", subaccount= " # Nat.toText(value)]);
        #Ok(newDocHistory);
      };
      case (#Err(err)) {
        logger.append([prefix # " updateDocHistory: setUserReputation result: error"]);
        #Err(#TemporarilyUnavailable);
      };
    };
  };

  public query func getDocHistory(docId : DocId) : async [DocHistory] {
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

  // Check document by canister id and docId
  func checkDocument(canisterId : Text, docId : DocId) : async Types.Result<Document, Types.CommonError> {
    let check = await getAndCheckDocument(canisterId, docId);
    let doc = switch (check) {
      case null {
        #Err(#NotFound { message = "No document found by canister id " # canisterId; docId = docId });
      };
      case (?doc) { #Ok(doc) };
    };
  };

  func getAndCheckDocument(canisterId : Text, docId : DocId) : async ?Document {
    logger.append([prefix # " rep: getAndCheckDocument starts, calling method getDocumentById with args: canisterId = " # canisterId # ", docId = " # Nat.toText(docId) # "\n"]);
    let canister : Types.Doctoken = actor (canisterId);
    logger.append([prefix # " rep: getAndCheckDocument: calling canister with id " # canisterId]);
    let doc = await canister.getDocumentById(docId);
    switch (doc) {
      case null {
        logger.append([prefix # " rep: getAndCheckDocument: getDocumentById returns: document not found by id " # Nat.toText(docId)]);
        null;
      };
      case (?doc) {
        logger.append([prefix # " rep: getAndCheckDocument: document found by id " # Nat.toText(docId)]);
        ?doc;
      };
    };
  };

  public func setNewCategory(category : Category, cifer : Text) : async Types.Result<(Category, Text), Types.CategoryError> {
    let current_cifer = await getCiferByCategory(category);
    switch (current_cifer) {
      case null {
        if (Text.equal(cifer, "")) {
          return #Err(#WrongCipher { cifer = cifer });
        };
        switch (tagCifer.get(category)) {
          case (null) {
            tagCifer.put(category, cifer);
          };
          case (?t) ignore tagCifer.replace(category, cifer);
        };
        return #Ok(category, cifer);
      };
      case (?t) #Err(#CategoryAlreadyExists { category = category; cifer = t });
    };
  };

  public func removeCategory(category : Category) : async Types.Result<Category, Types.CategoryError> {
    let current_cifer = await getCiferByCategory(category);
    switch (current_cifer) {
      case null {
        return #Err(#CategoryDoesNotExist { category = category });
      };
      case (?c) {
        ignore tagCifer.remove(category);
      };
    };
    #Ok(category);
  };

  public shared query func getCategories() : async [(Category, Text)] {
    let res = Buffer.Buffer<(Category, Text)>(1);
    for ((key, value) in tagCifer.entries()) {
      res.add(key, value);
    };
    Buffer.toArray(res);
  };

  /*
  Token Handling--------------------------------------------------------------------------
  */

  // null subaccount will be use as shared token wallet
  // 1 subaccount is incenitive subaccount
  // other subaccounts are branch ids

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

  func nullSubaccount() : async Subaccount {
    Blob.fromArrayMut(Array.init(32, 0 : Nat8));
  };

  func addSubaccount(user : Principal, category : Text) : async Account {
    let sub = await getSubaccountByCategory(category);
    let newAccount : Account = { owner = user; subaccount = sub };
  };

  // Logic part

  public func getMintingAccountPrincipal() : async Principal {
    let acc = await Ledger.icrc1_minting_account();
    switch (acc) {
      case null Principal.fromText("aaaaa-aa");
      case (?account) account.owner;
    };
  };

  type Badge = {
    user : Text;
    ava_link : Text;
    ic_link : Text;
    total_reputation : Nat;
    beginner : [(Text, Text)]; // (cipher, name)
    specialist : [(Text, Text)]; // (cipher, name)
    expert : [(Text, Text)]; // (cipher, name)
    history_link : Text;
  };

  // Method for dNFT
  public func getSoulboundBadge(user : Principal) : async Badge {
    let badge = {
      user = Principal.toText(user);
      ava_link = "https://ava.capetown/en";
      ic_link = "https://internetcomputer.org";
      total_reputation = await getUserBalance(user);
      beginner = await getBeginnerCiferAndCategories(user);
      specialist = await getSpecialistCiferAndCategories(user);
      expert = await getExpertgetCiferAndCategories(user);
      history_link = "https://check.ava.capetown";
    };
  };

  func getBeginnerCiferAndCategories(user : Principal) : async [(Text, Text)] {
    let beginner = await getBeginnerCategories(user);
    let res = Buffer.Buffer<(Text, Text)>(1);
    for (s in beginner.vals()) {
      let cifer = Option.get(await getCiferByCategory(s.0), "");
      res.add(cifer, s.0);
    };
    Buffer.toArray(res);
  };

  func getSpecialistCiferAndCategories(user : Principal) : async [(Text, Text)] {
    let specialist = await getSpecialistCategories(user);
    let res = Buffer.Buffer<(Text, Text)>(1);
    for (s in specialist.vals()) {
      let cifer = Option.get(await getCiferByCategory(s.0), "");
      res.add(cifer, s.0);
    };
    Buffer.toArray(res);
  };

  func getExpertgetCiferAndCategories(user : Principal) : async [(Text, Text)] {
    let expert = await getExpertCategories(user);
    let res = Buffer.Buffer<(Text, Text)>(1);
    for (e in expert.vals()) {
      let cifer = Option.get(await getCiferByCategory(e.0), "");
      res.add(cifer, e.0);
    };
    Buffer.toArray(res);
  };

  public func getUserBalance(userAlias : Principal) : async Nat {
    let user = _aliasHandler(userAlias);
    await Ledger.icrc1_balance_by_principal({ owner = user; subaccount = null });
  };

  // Check aliases and Replace to real user principal
  func _aliasHandler(user : Principal) : Principal {
    let existingAliasValue = aliases.get(Principal.toText(user));
    switch (existingAliasValue) {
      case (?value) Principal.fromText(value);
      case (null) user;
    };
  };

  public func userBalanceByCategory(userAlias : Principal, category : Text) : async Nat {
    let sub : ?Blob = await getSubaccountByCategory(category);
    let ledger_subaccount : Ledger.Subaccount = switch (sub) {
      case (null) { [] };
      case (?s) { Blob.toArray(s) };
    };
    let registerUser = _aliasHandler(userAlias);
    let addSub : Ledger.Account = {
      owner = registerUser;
      subaccount = ?ledger_subaccount;
    };
    await Ledger.icrc1_balance_of(addSub);
  };

  // Increase reputation

  func subToText(blob : ?Blob) : Text {
    switch (blob) {
      case null { "null" };
      case (?b) {
        let text = Text.decodeUtf8(b);
        switch (text) {
          case null { "null" };
          case (?t) { t };
        };
      };
    };
  };

  func awardToken(
    to : Types.Account,
    amount : Types.Tokens,
  ) : async Types.Result<TxIndex, Types.TransferFromError> {
    let prefix = Utils.timestampToDate();
    logger.append([prefix # " Method awardToken starts"]);
    let memo : ?Ledger.Memo = null;
    let fee : ?Ledger.Tokens = null;
    let created_at_time : ?Types.Timestamp = ?Nat64.fromIntWrap(Time.now());
    let sub : ?Blob = to.subaccount;
    let ledger_subaccount : Ledger.Subaccount = switch (sub) {
      case (null) { [] };
      case (?s) { Blob.toArray(s) };
    };
    let registerUser = _aliasHandler(to.owner);
    let acc : Ledger.Account = {
      owner = registerUser;
      subaccount = ?ledger_subaccount;
    };
    logger.append([prefix # " Method awardToken: calling method Ledger.icrc2_transfer_from \n"]);
    logger.append([prefix # " awardToken: with args: " # Principal.toText(acc.owner) # ", amount = " # Nat.toText(amount)]);
    let pre_mint_account = await getMintingAccountPrincipal();

    Cycles.add(default_award_fee);
    let res = await Ledger.icrc2_transfer_from({
      from = { owner = pre_mint_account; subaccount = null };
      to = acc;
      amount = amount;
      fee = fee;
      memo = memo;
      created_at_time = created_at_time;
    });
    // logger.append([prefix # " Method awardToken: Ledger.icrc2_transfer_from result was received"]);
    res;
  };

  // Decrease reputation
  public shared ({ caller }) func burnReputation({
    from : Principal;
    category : Text;
    amount : Ledger.Tokens;
  }) : async Types.Result<TxIndex, Types.TransferFromError> {

    let sub : Blob = Option.get(await getSubaccountByCategory(category), Blob.fromArray([]));
    let sender : ?Ledger.Subaccount = ?Blob.toArray(sub);
    let memo : ?Ledger.Memo = null;
    let fee : ?Ledger.Tokens = ?0;
    let created_at_time : ?Ledger.Timestamp = ?Nat64.fromIntWrap(Time.now());
    let a : Ledger.Tokens = amount;
    let pre_mint_account = await getMintingAccountPrincipal();
    let registerUser = _aliasHandler(from);
    let res = await Ledger.icrc2_transfer_from({
      from = { owner = registerUser; subaccount = sender };
      to = { owner = pre_mint_account; subaccount = null };
      amount = amount;
      fee = fee;
      memo = memo;
      created_at_time = created_at_time;
    });
  };

  // TODO
  // public func askForBurn(
  //   requester : Account,
  //   from : Account,
  //   document : Types.DocId,
  //   tags : [Types.Category],
  //   amount :
  //   // Ledger.
  //   Tokens,
  // ) : async Types.Result<TxIndex, Types.TransferBurnError> {
  //   // check requester's balance
  //   let branch = getBranchFromSubaccount(requester.subaccount);
  //   let balance_requester = await userBalanceByBranch(requester.owner, branch);
  //   // check from balance
  //   let branch_author = getBranchFromSubaccount(from.subaccount);
  //   if (not Nat8.equal(branch, branch_author)) return #Err(#WrongBranch { current_branch = branch; target_branch = branch_author });
  //   let balance_author = await userBalanceByBranch(from.owner, branch);
  //   if (balance_requester < balance_author) return #Err(#InsufficientReputation { current_branch = branch; balance = balance_author });
  //   // TODO check document's tags for equity to requester's subaccount
  //   // let checkTag = Array.find<Types.Tag>(tags, func x = (x == branch));

  //   // TODO burn requester's token
  //   // TODO burn from token
  //   // TODO create history log

  //   return #Err(#TemporarilyUnavailable);
  // };

  // Incenitive
  // public func awardIncenitive(to :
  // // Ledger.
  // Account, amount :
  // // Ledger.
  // Tokens) : async Types.Result<TxIndex, Types.TransferFromError> {
  //   let memo : ?Ledger.Memo = null;
  //   let created_at_time : ?Ledger.Timestamp = ?Nat64.fromIntWrap(Time.now());
  //   let receiver : Ledger.Account = {
  //     owner = to.owner;
  //     subaccount = ?(subaccountToNatArray(await branchToSubaccount(1)));
  //   };
  //   let pre_mint_account = await getMintingAccountPrincipal();
  //   let res = await Ledger.icrc2_transfer_from({
  //     from = { owner = pre_mint_account; subaccount = null };
  //     to = receiver;
  //     amount = amount;
  //     fee = ?0;
  //     memo = memo;
  //     created_at_time = created_at_time;
  //   });

  // Scheduler part
  // public func distributeTokens(user: Principal, branch : Nat8, value : Nat) : async Result<Bool, TransferFromError> {
  //   TODO handle quantity of tokens for distribution daily
  // };
  // };

  // Aliases

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

  // Stable tags, docHistory and user reputation storage
  stable var tagEntries : [(Category, Text)] = [];
  stable var userReputationArray : [(Principal, [(Category, Nat)])] = [];
  stable var docHistoryArray : [(DocId, [DocHistory])] = [];
  stable var stableAsias : [(Text, Text)] = [];

  system func preupgrade() {
    for ((tag, branch) in tagCifer.entries()) {
      tagEntries := Array.append(tagEntries, [(tag, branch)]);
    };
    for ((user, entry) in userReputation.entries()) {
      var buffer = Buffer.Buffer<(Category, Nat)>(0);
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
    stableAsias := Iter.toArray(aliases.entries());
  };

  system func postupgrade() {
    for ((tag, branch) in tagEntries.vals()) {
      tagCifer.put(tag, branch);
    };
    tagEntries := [];
    for ((user, entry) in userReputationArray.vals()) {
      var map = Map.HashMap<Category, Nat>(0, Text.equal, Text.hash);
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
    for ((user, alias) in stableAsias.vals()) {
      aliases.put(user, alias);
    };
    stableAsias := [];
  };

  // Clearance methods
  public func clearTags() : async Bool {
    tagCifer := TrieMap.TrieMap<Text, Category>(Text.equal, Text.hash);
    true;
  };

  public func clearUserReputation() : async Bool {
    userReputation := Map.HashMap<Principal, Map.HashMap<Category, Nat>>(0, Principal.equal, Principal.hash);
    true;
  };

  public func clearDocHistory() : async Bool {
    docHistory := Map.HashMap<DocId, [DocHistory]>(0, Nat.equal, Hash.hash);
    true;
  };

  public func clearOldestLogs(number : Nat) : async Bool {
    logger.pop_buckets(number);
    true;
  };

  public func clearAllLogs() : async Bool {
    logger.clear();
    true;
  };
};
