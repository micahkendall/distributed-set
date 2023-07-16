import { Data, fromHex, toHex, UTxO } from "lucid"
import { hash_blake2b256 } from "lucid/src/core/libs/cardano_multiplatform_lib/cardano_multiplatform_lib.generated.js"

export type OutputReference = {
  transactionId: { hash: string }
  outputIndex: bigint
}

export const OutputReference = Object.assign({
  "title": "OutputReference",
  "dataType": "constructor",
  "index": 0,
  "fields": [{
    "title": "transactionId",
    "description":
      "A unique transaction identifier, as the hash of a transaction body. Note that the transaction id\n isn't a direct hash of the `Transaction` as visible on-chain. Rather, they correspond to hash\n digests of transaction body as they are serialized on the network.",
    "anyOf": [{
      "title": "TransactionId",
      "dataType": "constructor",
      "index": 0,
      "fields": [{ "dataType": "bytes", "title": "hash" }],
    }],
  }, { "dataType": "integer", "title": "outputIndex" }],
})

export function nameFromUTxO(utxo: UTxO) {
  const the_output_reference = Data.to<OutputReference>(
    {
      transactionId: { hash: utxo.txHash },
      outputIndex: BigInt(utxo.outputIndex),
    },
    OutputReference,
  )
  const assetName = toHex(
    hash_blake2b256(fromHex(the_output_reference)),
  )
  return assetName
}
