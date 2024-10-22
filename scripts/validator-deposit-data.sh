#!/bin/bash

amount=32000000000 # Converting From Gwei to Native. 32000000000 = 32 DCOIN Token 
smin=0 # Start Key Validator to Run 
smax=1 # End Key Validator to Run

eth2-val-tools deposit-data \
  --source-min=$smin \
  --source-max=$smax \
  --amount=$amount \
  --fork-version=0x10000293 \
  --withdrawals-mnemonic="test test test test test test test test test test test junk" \
  --validators-mnemonic="test test test test test test test test test test test junk" > mainnet_deposit_$smin\_$smax.txt

while read x; do
   account_name="$(echo "$x" | jq '.account')"
   pubkey="$(echo "$x" | jq '.pubkey')"
   echo "Sending deposit for validator $account_name $pubkey"
   ethereal beacon deposit \
      --allow-unknown-contract=true \
      --address="0xdeadbeef00000000000000000000000000000000" \
      --connection=https://mainnet-rpc.davinchi.bz \
      --data="$x" \
      --allow-excessive-deposit \
      --value="$amount" \
      --from="Paste Here Your Address Have DCOIN Native" \
      --privatekey="Paste Here Your Address Private Key"
   echo "Sent deposit for validator $account_name $pubkey"
   sleep 2
done < mainnet_deposit_$smin\_$smax.txt