
# dfx start --background --clean
# dfx canister create --all

# dfx build


dfx deploy --argument '(record { initial_mints = 
    vec { 
        record { account = record { 
            owner = principal "bs3e6-4i343-voosn-wogd7-6kbdg-mctak-hn3ws-k7q7f-fye2e-uqeyh-yae"; subaccount = null }; amount = 1000 } }; 
        minting_account = record { owner = principal "bs3e6-4i343-voosn-wogd7-6kbdg-mctak-hn3ws-k7q7f-fye2e-uqeyh-yae"; subaccount = null };
        token_name = "aVa Reputation Token"; 
        token_symbol = "AVAR"; 
        decimals = 10; 
        transfer_fee = 0 })' ledger

# echo "Getting init balance of branch 0: "
# dfx canister call rep_token userBalanceByBranch '(principal "ao6hk-x5zgr-aa6y2-zq5ei-meewq-doeim-hwbws-zzxql-rjtcc-hmabt-xqe", 0)'

# dfx canister call rep setNewTag '( "Shared Reputation" )'
# dfx canister call rep setNewTag '( "Incenitive Reputation" )'
# dfx canister call rep setNewTag '( "IT" )'

# echo "Getting init balance of branch 2: "


# dfx canister call rep getReputationByBranch '(principal "ao6hk-x5zgr-aa6y2-zq5ei-meewq-doeim-hwbws-zzxql-rjtcc-hmabt-xqe", 2)'
# echo "Trasfer:"

# dfx canister call rep setUserReputation '(
#     principal "ao6hk-x5zgr-aa6y2-zq5ei-meewq-doeim-hwbws-zzxql-rjtcc-hmabt-xqe",
#     2,
#     5
#     )'

# echo "Getting new balance of branch 2: "


# dfx canister call rep getReputationByBranch '(principal "ao6hk-x5zgr-aa6y2-zq5ei-meewq-doeim-hwbws-zzxql-rjtcc-hmabt-xqe", 2)'

