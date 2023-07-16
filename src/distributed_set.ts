import { Data, Lucid, toUnit } from "lucid"
import {
  DistributedSetMintDistributedSet,
  DistributedSetSpendDistributedSet,
} from "distributed_set"
import { nameFromUTxO } from "./util.ts"

const MintRedeemer = DistributedSetMintDistributedSet["redeemer"]
const SpendRedeemer = DistributedSetSpendDistributedSet["redeemer"]
const Datum = DistributedSetSpendDistributedSet["datum"]

type MintRedeemer = DistributedSetMintDistributedSet["redeemer"]
type SpendRedeemer = DistributedSetSpendDistributedSet["redeemer"]
type Datum = DistributedSetSpendDistributedSet["datum"]

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

  const redeemer = Data.to<MintRedeemer>(
    "Unit",
    MintRedeemer,
  )
  const initial_datum: Datum = {
    id: assetName,
    next: null,
    isHead: true,
    values: ["01", "03"],
    requires: null,
  }

  const tx = await lucid.newTx()
    .validTo(now + 30000)
    .attachMintingPolicy(newSetScript)
    .payToAddressWithData(
      scriptAddress,
      {
        inline: Data.to<Datum>(
          initial_datum,
          Datum,
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
  const redeemer: SpendRedeemer = {
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
      Data.to<SpendRedeemer>(
        redeemer,
        SpendRedeemer,
      ),
    )
    .payToAddressWithData(
      details.scriptAddress,
      {
        inline: Data.to<Datum>(
          datum,
          Datum,
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

export async function breakSet(
  lucid: Lucid,
  now: number,
  details: SetDetails,
  id: string,
) {
  const unit = toUnit(details.policyId, id)
  const utxo = await lucid.utxoByUnit(unit)
  const oref = {
    consuming: {
      transactionId: { hash: utxo.txHash },
      outputIndex: BigInt(utxo.outputIndex),
    },
  }
  const newid = nameFromUTxO(utxo)
  const assetName = toUnit(details.policyId, newid)
  const spend_redeemer: SpendRedeemer = {
    wrapper: {
      ["BinarySplit"]: oref,
    },
  }
  const mint_redeemer: MintRedeemer = {
    ["BinarySplit"]: oref,
  }
  // const assetName = nameFromUTxO(utxo)
  const datum = {
    id: id,
    next: null,
    isHead: true,
    values: [],
    requires: null,
  }
  // {
  //   id: string;
  //   next: string | null;
  //   isHead: boolean;
  //   values: string[];
  //   requires: {
  //       RequireMint: [string];
  //       } | {
  //           RequireStake: [string];
  //       } | null;
  //   }
  const first_datum: Datum = {
    id: datum.id,
    next: newid,
    isHead: datum.isHead,
    values: ["01", "02"],
    requires: datum.requires,
  }
  const next_datum: Datum = {
    id: newid,
    next: datum.next,
    isHead: false,
    values: ["03"],
    requires: datum.requires,
  }
  const tx = await lucid.newTx()
    .validTo(now + 30000)
    .attachSpendingValidator(
      details.script,
    )
    .attachMintingPolicy(details.script)
    .collectFrom(
      [utxo],
      Data.to<SpendRedeemer>(
        spend_redeemer,
        SpendRedeemer,
      ),
    )
    .mintAssets(
      {
        [assetName]: 1n,
      },
      Data.to<MintRedeemer>(
        mint_redeemer,
        MintRedeemer,
      ),
    )
    .payToAddressWithData(
      details.scriptAddress,
      {
        inline: Data.to<Datum>(
          first_datum,
          Datum,
        ),
      },
      {
        [unit]: 1n,
      },
    )
    .payToAddressWithData(
      details.scriptAddress,
      {
        inline: Data.to<Datum>(
          next_datum,
          Datum,
        ),
      },
      {
        [assetName]: 1n,
      },
    )
    .complete()
  const signedTx = await tx.sign().complete()
  return signedTx.submit()
}
