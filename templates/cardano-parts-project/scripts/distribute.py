#!/usr/bin/env nix-shell
#!nix-shell -i python -p python3Packages.docopt python3Packages.cbor2

"""distribute

Usage:
    distribute [--testnet-magic INT] [--signing-key-file FILE] [--address ADDRESS] [--payments-json FILE]

Options:
    -h --help                    Show this screen
    -t --testnet-magic <INT>     Testnet Magic
    -s --signing-key-file <FILE> Signing Key, ie: rich-utxo.skey
    -a --address <STRING>        Funding address, ie: rich-utxo address
    -p --payments-json <FILE>    JSON file containing payments to make, ie: list of attrs, where each attr is a single address:amount

"""

# Example payments-json file struct:
# [
#   {"addr_test1...": 10000200000},
#   ...
#   {"addr_test1...": 10000200000}
# ]

import os
from lib import cli
from docopt import docopt
from pathlib import Path

arguments = docopt(__doc__, version='distribute 0.0')
network_args = []

if arguments["--address"]:
  utxo_address = arguments["--address"]
else:
  print("Must specify source address for payments")
  exit(1)

if arguments["--signing-key-file"] and os.path.exists(arguments["--signing-key-file"]):
  utxo_signing_key = Path(arguments["--signing-key-file"])
else:
  print("Must specify signing key file")
  exit(1)

if arguments["--payments-json"]:
  payments_json = arguments["--payments-json"]
else:
  print("Must specify payments file")
  exit(1)

if arguments["--testnet-magic"]:
  network_args = ["--testnet-magic", arguments["--testnet-magic"]]
else:
  network_args = ["--mainnet"]

# Set defaults
accounts_fixed = []
extra_lovelace = 0
fees = 0
last_txin = ""
payments_txouts = []

# Gather required data
accounts = cli.getAccountsFromFile(payments_json)
txin = cli.getLargestUtxoForAddress(utxo_address, *network_args)
ttl = cli.getTTL(*network_args, addnl_sec=86400)
initial = txin[1]

# Convert the signing key to a str so sops decryption and file redirection can be used for the file input arg
with open(utxo_signing_key, "r") as file:
  utxo_signing_key_str = file.read()

# Ensure accounts data is a list
if type(accounts) == dict:
    for k,v in accounts.items():
        accounts_fixed.append({k: v})
elif type(accounts) == list:
    accounts_fixed = accounts

for i,d in enumerate(accounts_fixed):
    (k,v), = d.items()
    if v >= 1000000:
        value = v
    else:
        extra_lovelace += 1000000 - v
        value = 1000000

    payments_txouts.append({ k: value })
    if (i % 100) == 99 or len(accounts) == i + 1:
        start = (i // 100) * 100
        end = i
        print(f"Transferring payments for keys {start} - {end}")
        txin = cli.createTransaction(start, end, txin, payments_txouts, utxo_address, utxo_signing_key_str, *network_args)
        fees += txin[2]
        payments_txouts = []

spent = initial - txin[1]
print(f"total spent: {spent} fees: {fees} min_utxo_extra: {extra_lovelace}")
