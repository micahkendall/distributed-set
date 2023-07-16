import { Emulator, generatePrivateKey, Lucid } from "lucid"
import { breakSet, continueSet, createSet } from "./distributed_set.ts"

const privateKey = generatePrivateKey()

const address = await (await Lucid.new(undefined, "Custom"))
  .selectWalletFromPrivateKey(privateKey).wallet.address()

async function init() {
  const emulator = new Emulator([{
    address,
    assets: { lovelace: 3000000000n },
  }])

  const lucid = await Lucid.new(emulator)

  lucid.selectWalletFromPrivateKey(privateKey)
  return { lucid, emulator }
}

Deno.test("Create 1", async () => {
  const { lucid, emulator } = await init()

  const submittedTx = await createSet(lucid, emulator.now())
  //console.log(submittedTx)

  emulator.awaitBlock(1)

  const continuedTx = await continueSet(
    lucid,
    emulator.now(),
    submittedTx,
    submittedTx.ids[0],
  )
  //console.log(continuedTx)
})

Deno.test("Basic Continuing Test", async () => {
  const { lucid, emulator } = await init()

  const submittedTx = await createSet(lucid, emulator.now())
  //console.log(submittedTx)

  emulator.awaitBlock(1)

  const continuedTx = await continueSet(
    lucid,
    emulator.now(),
    submittedTx,
    submittedTx.ids[0],
  )
  //console.log(continuedTx)
})

Deno.test("Basic Breaking Test", async () => {
  const { lucid, emulator } = await init()

  const submittedTx = await createSet(lucid, emulator.now())
  //console.log(submittedTx)

  emulator.awaitBlock(1)

  const brokenTx = await breakSet(
    lucid,
    emulator.now(),
    submittedTx,
    submittedTx.ids[0],
  )
  console.log(brokenTx)
})
