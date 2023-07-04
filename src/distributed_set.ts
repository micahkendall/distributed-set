import { Data, fromHex, Lucid, toHex, toUnit } from "lucid"
import {
  DistributedSetMintDistributedSet,
  DistributedSetSpendDistributedSet,
} from "distributed_set"
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

export async function createSet(lucid: Lucid, now: number) {
  const utxo = (await lucid.wallet.getUtxos())[0]

  const newSetScript = new DistributedSetMintDistributedSet({
    transactionId: { hash: utxo.txHash },
    outputIndex: BigInt(utxo.outputIndex),
  })

  const policyId = lucid.utils.mintingPolicyToId(newSetScript)
  const scriptHash = lucid.utils.validatorToScriptHash(newSetScript)

  const scriptCredential = lucid.utils.scriptHashToCredential(scriptHash)
  const scriptAddress = lucid.utils.credentialToAddress(
    scriptCredential,
    undefined,
  )

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

  const redeemer = Data.to<DistributedSetMintDistributedSet["redeemer"]>(
    "Unit",
    DistributedSetMintDistributedSet["redeemer"],
  )

  const tx = await lucid.newTx()
    .validTo(now + 30000)
    .attachMintingPolicy(newSetScript)
    .payToAddressWithData(
      scriptAddress,
      {
        inline: Data.to<DistributedSetSpendDistributedSet["datum"]>(
          {
            id: assetName,
            next: null,
            isHead: true,
            values: [],
            requires: null,
          },
          DistributedSetSpendDistributedSet["datum"],
        ),
      },
      {
        [toUnit(policyId, assetName)]: 1n,
      },
    )
    .mintAssets(
      {
        [toUnit(policyId, assetName)]: 1n,
      },
      redeemer,
    )
    .complete()
  const signedTx = await tx.sign().complete()
  return signedTx.submit()
}
