
dfx deploy --argument '(record { initial_mints = 
    vec { 
        record { account = record { 
            owner = principal "oa7ab-4elxo-r5ooc-a23ga-lheml-we4wg-z5iuo-ery2n-57uyv-u234p-pae"; subaccount = null }; amount = 1000 } }; 
        minting_account = record { owner = principal "oa7ab-4elxo-r5ooc-a23ga-lheml-we4wg-z5iuo-ery2n-57uyv-u234p-pae"; subaccount = null };
        token_name = "aVa Reputation Token"; 
        token_symbol = "AVAR"; 
        decimals = 10; 
        transfer_fee = 0 })' ledger

dfx deploy --argument '(record { initial_mints = 
    vec { 
        record { account = record { 
            owner = principal "oa7ab-4elxo-r5ooc-a23ga-lheml-we4wg-z5iuo-ery2n-57uyv-u234p-pae"; subaccount = null }; amount = 1000 } }; 
        minting_account = record { owner = principal "oa7ab-4elxo-r5ooc-a23ga-lheml-we4wg-z5iuo-ery2n-57uyv-u234p-pae"; subaccount = null };
        token_name = "aVa Reputation Rating Token"; 
        token_symbol = "ART"; 
        decimals = 10; 
        transfer_fee = 0 })' rating_ledger
dfx deploy rep
