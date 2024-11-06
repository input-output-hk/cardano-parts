import json
import os
import subprocess
from typing import Any

def cardanoCliStr() -> str:
    if(os.getenv('USE_SHELL_BINS') == "true"):
        return("cardano-cli")
    elif(os.getenv('UNSTABLE') == "true"):
        return("cardano-cli-ng")
    else:
        return("cardano-cli")


def createTransaction(start, end, txin, payments_txouts, utxo_address, utxo_signing_key_str, *network_args) -> tuple:
    payments_txout_args = []
    total_payments_spent = 0

    for d in payments_txouts:
        (k,v), = d.items()
        payments_txout_args.extend(["--tx-out", f"{k}+{v}"])
        total_payments_spent += v

    txin_str = txin[0]
    ttl = getTTL(*network_args, addnl_sec=86400)
    pparams = getPParams(*network_args)
    tx_prefix = f"tx-payments-{start}-{end}"
    tx_out_amount = int(txin[1]) - 0 - total_payments_spent

    p = subprocess.run([
        cardanoCliStr(), "latest", "transaction", "build-raw",
        "--out-file", f"{tx_prefix}.txbody",
        "--tx-in", txin_str,
        "--tx-out", f"{utxo_address}+{tx_out_amount}",
        *payments_txout_args,
        "--ttl", str(ttl),
        "--fee", "0"])

    fee = estimateFeeTx(f"{tx_prefix}.txbody", 1, len(payments_txouts), pparams)
    tx_out_amount = int(txin[1]) - fee - total_payments_spent

    if tx_out_amount <= 1000000:
        raise Exception("Not enough funds")

    p = subprocess.run([
        cardanoCliStr(), "latest", "transaction", "build-raw",
        "--out-file", f"{tx_prefix}.txbody",
        "--tx-in", txin_str,
        "--tx-out", f"{utxo_address}+{tx_out_amount}",
        *payments_txout_args,
        "--ttl", str(ttl),
        "--fee", str(fee)])

    signed_tx = signTx(tx_prefix, utxo_signing_key_str)

    p = subprocess.run([cardanoCliStr(), "latest", "transaction", "txid", "--tx-file", signed_tx], capture_output=True, text=True)
    new_txin = p.stdout.rstrip()
    return (f"{new_txin}#0", tx_out_amount, fee)


def estimateFeeTx(txbody, txin_count, txout_count, pparams) -> int:
    cmd = [
        cardanoCliStr(), "latest", "transaction", "calculate-min-fee",
        "--reference-script-size", "0",
        "--tx-in-count", str(txin_count),
        "--tx-out-count", str(txout_count),
        "--witness-count", "1",
        "--protocol-params-file", pparams,
        "--tx-body-file", txbody]

    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        print(cmd)
        print(p.stderr)
        raise Exception("error calculating fee")
    return int(p.stdout.rstrip().split(" ")[0])


def getAccountsFromFile(filename) -> list:
    f = open(filename)
    payments = json.load(f)
    f.close()
    return payments


def getLargestUtxoForAddress(address, *network_args) -> tuple:
    subprocess.run([cardanoCliStr(), "latest", "query", "utxo", "--out-file", "tmp_utxo.json", *network_args, "--address", address])
    f = open("tmp_utxo.json")
    utxo = json.load(f)
    f.close()

    if not utxo:
      print("address has no available utxos")
      exit(1)

    lovelace = 0
    txin = None
    for k,v in utxo.items():
      if(len(v['value']) == 1 and v['value']['lovelace'] > lovelace):
        lovelace =v['value']['lovelace']
        txin = (k,lovelace)

    if txin == None:
      print("No suitable utxo could be found")
      exit(1)
    return txin


def getPParams(*network_args) -> str:
    p = subprocess.Popen([cardanoCliStr(), "latest", "query", "protocol-parameters", *network_args, "--out-file", "pparams.json"])
    p.wait()
    return "pparams.json"


def getPParamsJson(*network_args) -> Any:
    p = subprocess.Popen([cardanoCliStr(), "latest", "query", "protocol-parameters", *network_args, "--out-file", "/dev/stdout"], stdout=subprocess.PIPE)
    p.wait()
    output, _ = p.communicate()
    return json.loads(output)


def getTTL(*network_args, addnl_sec=3600) -> int:
    p = subprocess.run([cardanoCliStr(), "latest", "query", "tip", *network_args], capture_output=True, text=True)
    if p.returncode != 0:
        print(p.stderr)
        raise Exception("Unknown error getting ttl")
    return int(json.loads(p.stdout.rstrip())["slot"]) + addnl_sec


def signTx(tx_body_prefix, utxo_signing_key_str) -> str:
    subprocess.run([
        "bash", "-c",
        f"cardano-cli latest transaction sign --tx-body-file {tx_body_prefix}.txbody"
        f" --signing-key-file <(echo '{utxo_signing_key_str}')"
        f" --out-file {tx_body_prefix}.txsigned"])
    return f"{tx_body_prefix}.txsigned"
