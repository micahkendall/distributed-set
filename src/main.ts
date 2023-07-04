import { Emulator, generatePrivateKey, Lucid } from "lucid"
import { continueSet, createSet } from "./distributed_set.ts"

const privateKey = generatePrivateKey()

const address = await (await Lucid.new(undefined, "Custom"))
  .selectWalletFromPrivateKey(privateKey).wallet.address()

const emulator = new Emulator([{ address, assets: { lovelace: 3000000000n } }])

const lucid = await Lucid.new(emulator)

lucid.selectWalletFromPrivateKey(privateKey)

const submittedTx = await createSet(lucid, emulator.now())
console.log(submittedTx)

emulator.awaitBlock(1)

const continuedTx = continueSet(
  lucid,
  emulator.now(),
  submittedTx,
  submittedTx.ids[0],
)
console.log(continuedTx)
