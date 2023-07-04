import { Data, fromHex, Lucid, toHex, toUnit, UTxO } from "lucid"
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

  const assetName = nameFromUTxO(utxo)

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
  const submittedTx = await signedTx.submit()
  return {
    genesisTx: submittedTx,
    script: newSetScript,
    policyId,
    scriptHash,
    scriptAddress,
    scriptCredential,
    ids: [assetName],
  }
}
export type SetDetails = Awaited<ReturnType<typeof createSet>>

export async function continueSet(
  lucid: Lucid,
  now: number,
  details: SetDetails,
  id: string,
) {
  const unit = toUnit(details.policyId, id)
  const utxo = await lucid.utxoByUnit(unit)
  console.log(await utxo)
  const redeemer: DistributedSetSpendDistributedSet["redeemer"] = {
    wrapper: "Unit",
  }
  const datum = {
    id: id,
    next: null,
    isHead: true,
    values: [],
    requires: null,
  }
  const tx = await lucid.newTx()
    .validTo(now + 30000)
    .attachSpendingValidator(
      details.script,
    )
    .collectFrom(
      [utxo],
      Data.to<DistributedSetSpendDistributedSet["redeemer"]>(
        redeemer,
        DistributedSetSpendDistributedSet["redeemer"],
      ),
    )
    .payToAddressWithData(
      details.scriptAddress,
      {
        inline: Data.to<DistributedSetSpendDistributedSet["datum"]>(
          datum,
          DistributedSetSpendDistributedSet["datum"],
        ),
      },
      {
        [unit]: 1n,
      },
    )
    .complete()
  const signedTx = await tx.sign().complete()
  return signedTx.submit()
}
