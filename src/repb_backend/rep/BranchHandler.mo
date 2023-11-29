import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Nat32 "mo:base/Nat32";
import Nat8 "mo:base/Nat8";
import Principal "mo:base/Principal";

import CRC32 "./CRC32";
import SHA224 "./SHA224";
import Types "./Types";

actor {
//102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20

    type Branch = Types.Branch;
    type Tag = Types.Tag;
    type Account = Types.Account; //{ owner : Principal; subaccount : ?Subaccount };
    type Subaccount = Types.Subaccount;

    func subaccountToNatArray(subaccount : Types.Subaccount) : [Nat8] {
        var buffer = Buffer.Buffer<Nat8>(0);
        for (item in subaccount.vals()) {
            buffer.add(item);
        };
        Buffer.toArray(buffer);
    };

   
    // func beBytes(n : Nat32) : [Nat8] {
    //     func byte(n : Nat32) : Nat8 {
    //         Nat8.fromNat(Nat32.toNat(n & 0xff));
    //     };
    //     [byte(n >> 24), byte(n >> 16), byte(n >> 8), byte(n)];
    // };
    // public func accountIdentifier(principal : Principal, subaccount : Subaccount) : async Blob {
    //     let hash = SHA224.Digest();

    //     hash.write(Blob.toArray(subaccount));
    //     let hashSum = hash.sum();
    //     let crc32Bytes = beBytes(CRC32.ofArray(hashSum));
    //     Blob.fromArray(Array.append(crc32Bytes, hashSum));
    // };
    // func accountToText({ owner : Principal; subaccount : [Nat8] }) : () {
    //     let checksum = beBytes(CRC32.ofBlob(concatBytes(owner), subaccount));
    //     Principal.toText(owner) # "-" # base32LowerCaseNoPadding(checksum) # '.' # trimLeading('0', hex(subaccount));
    // };
    // func concatBytes(principal:Principal, sub : Subaccount) : Blob {

    // };
};
