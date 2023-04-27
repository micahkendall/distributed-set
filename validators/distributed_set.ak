use aiken/builtin
use aiken/dict
use aiken/hash.{Blake2b_224, Hash, blake2b_256}
use aiken/list
use aiken/transaction.{
  InlineDatum, Input, Mint, Output, OutputReference, ScriptContext, Spend,
  Transaction,
}
use aiken/transaction/credential.{Credential, Inline, Script, ScriptCredential}
use aiken/transaction/value.{AssetName, PolicyId, Value, tokens}

// our sets are implemented as a linked list of lists

// any value can be a key, by serialising and hashing
// we use a type alias to make it easier to change the key type,
// as there isn't type level parameterization in Aiken
type ListId =
  Hash<Blake2b_224, OutputReference>

fn list_id(utxo: OutputReference) -> ListId {
  blake2b_256(builtin.serialise_data(utxo))
}

// we could allow mint to produce many lists safely, but that is more complex
// we don't generally need this functionality as you can scale as you insert.

type ListMintRedeemer {
  Genesis
  SplitM(OutputReference)
}

fn unvalue(v: Value) -> List<(PolicyId, List<(AssetName, Int)>)> {
  let v1: Data =
    v
  expect v2: List<(PolicyId, List<(AssetName, Int)>)> =
    v1
  v2
}

// instead, every mint produces one single list instance
validator(genesis_utxo: OutputReference, control_script: Credential) {
  fn mint_distributed_list(r: ListMintRedeemer, ctx) -> Bool {
    let ScriptContext(
      Transaction(inputs, _, outputs, _, mint, _, withdrawals, _, _, _, _, _),
      Mint(this_policy),
    ) =
      ctx
    let lmint =
      unvalue(mint)
    // convert to unsafe_find later
    expect Some(minted_here) =
      list.find(
        lmint,
        fn(minted_nfts) {
          let (policy, _) =
            minted_nfts
          policy == this_policy
        },
      )
    when r is {
      // at genesis, allow 1 single token of 'genesis_utxo' to be minted
      Genesis -> {
        // convert to assert_any
        expect True =
          list.any(inputs, fn(input) { input.output_reference == genesis_utxo })
        let asset_name =
          list_id(genesis_utxo)
        expect True =
          minted_here == (this_policy, [(asset_name, 1)])
        expect [Output(_, new_val, InlineDatum(new_list_raw), None)] =
          list.filter(
            outputs,
            fn(output) { output.address.payment_credential == control_script },
          )
        expect [_ada, (out_policy, [(_out_asset_name, 1)])] =
          unvalue(new_val)
        expect True =
          out_policy == this_policy
        // && out_asset_name == asset_name // This is redundant since the only possible minted value at genesis is the correct asset name.
        expect ListDatum(
          new_list_id,
          new_list_next,
          new_list_is_head,
          _new_list_values,
          req,
        ): ListDatum =
          new_list_raw
        when req is {
          None ->
            True
          Some(invoked) ->
            when invoked is {
              InvokeMint(minting_script) ->
                !dict.is_empty(tokens(mint, minting_script))
              InvokeStake(staking_script) ->
                list.any(
                  dict.keys(withdrawals),
                  fn(key) { key == Inline(ScriptCredential(staking_script)) },
                )
            }
        } && new_list_id == asset_name && new_list_next == None && new_list_is_head == True
      }

      // need to enforce it is minted to the control script, that the datum is correct, and the value is correct.
      // on insert, if 1 token is spent, allow 1 additional token to be minted,
      // and the control validator ensures that additional token is correctly linked
      SplitM(new_ref) -> {
        expect True =
          list.any(inputs, fn(input) { input.output_reference == new_ref })
        let asset_name =
          list_id(new_ref)
        expect True =
          minted_here == (this_policy, [(asset_name, 1)])
        expect [ctrl_inp] =
          list.filter(
            inputs,
            fn(input) {
              input.output.address.payment_credential == control_script
            },
          )
        expect [out1, out2] =
          list.filter(
            outputs,
            fn(output) { output.address.payment_credential == control_script },
          )
        False
      }
    }
  }
}

// we implement a set with a linked list,
// where each list has a unique id,
// and a sorted list of keys
type ListDatum {
  id: ListId,
  next: Option<ListId>,
  is_head: Bool,
  // may need artificial length limit on this list to prevent DoS
  // Length limit on List AND on bytearray will be necessary
  values: List<ByteArray>,
  requires: Option<InvokedScript>,
}

type InvokedScript {
  InvokeMint(Hash<Blake2b_224, Script>)
  InvokeStake(Hash<Blake2b_224, Script>)
}

type ListSpendRedeemer {
  Modify
  SplitS
}

// strict sort validator
fn is_sorted(l: List<ByteArray>) -> Bool {
  when l is {
    [] ->
      True
    [_] ->
      True
    [x, y, ..xs] ->
      builtin.less_than_bytearray(x, y) && is_sorted([y, ..xs])
  }
}

// how could you implement e.g naming service with this?
// just write a minting validator which requires list as input, this script guarantees the outputs will be correct.
// Check if your handle is not in the input list, and is either in the output list, or in the concatenation of the two output lists.
// Slightly more difficult: ensuring there are no phantom names.
// You have need to cyclically reference the spend script to the minting validator,
// using the 'requires' field during genesis. This will enforce your minting or stake validator is invoked,
// where you can implement your business logic.

// spend distributed list doesn't have domain-specific restrictions on insertion/deletion,
// only that the set property is maintained (unique elements) across the utxo set
// This is done by maintaining strict ordering of the list (every element is greater than the previous)
// I.e 'greater or equal' fails to satisfy that.
// Any insert can be made by spending a single UTxO, and in case of too many elements,
// you can simply mint a new list and link it to the previous one.
// Our simple implementation restricts to a single spend to make this easier to validate.
// It shouldn't be necessary to mint two lists, so minting can always be done one at a time.
validator {
  fn spend_distributed_list(_d: ListDatum, r: ListSpendRedeemer, ctx) -> Bool {
    // should enforce only one input from this script
    // then, enforce on all the outputs that the list is maintained,
    // and that those outputs have the list NFT.
    let ScriptContext(
      Transaction(inputs, _, outputs, _, minted, _, withdrawals, _, _, _, _, _),
      Spend(output_reference),
    ) =
      ctx
    // find this input
    expect Some(Input(
      _,
      Output(this_address, val, InlineDatum(this_list_raw), None),
    )) =
      list.find(
        inputs,
        fn(input) { input.output_reference == output_reference },
      )
    // assert only one input from this script
    expect [_] =
      list.filter(
        inputs,
        fn(input) {
          input.output.address.payment_credential == this_address.payment_credential
        },
      )
    expect ListDatum(id, next, is_head, values, req): ListDatum =
      this_list_raw
    // the list is assumed to be sorted as invariant is maintained by mint,control
    // spending, there should be either two outputs at this script, or one.
    // this is decided by the ListSpendRedeemer
    expect True =
      when req is {
        None ->
          True
        Some(invoked) ->
          when invoked is {
            InvokeMint(minting_script) ->
              !dict.is_empty(tokens(minted, minting_script))
            InvokeStake(staking_script) ->
              list.any(
                dict.keys(withdrawals),
                fn(key) { key == Inline(ScriptCredential(staking_script)) },
              )
          }
      }
    when r is {
      Modify -> {
        // assert that the singular output at this address, is the same as the input, except for the inner values
        // head and final element of values and new_values are asserted to be the same
        // then, we assert that new_values are sorted.

        // TODO: check every input value is included in the new values
        expect [Output(_, new_val, InlineDatum(new_list_raw), None)] =
          list.filter(
            outputs,
            fn(output) {
              output.address.payment_credential == this_address.payment_credential
            },
          )
        expect ListDatum(new_id, new_next, new_is_head, new_values, new_req): ListDatum =
          new_list_raw
        // need to add asset_value check (that nft is maintained)
        new_id == id && new_next == next && (
          is_head || list.head(values) == list.head(new_values)
        ) && ( next == None || list.last(values) == list.last(new_values) ) && is_sorted(
          new_values,
        ) && req == new_req && new_is_head == is_head
      }
      SplitS -> {
        expect [
          Output(_, new_val, InlineDatum(new_list_raw), None),
          Output(_, new_val_2, InlineDatum(new_list_raw_2), None),
        ] =
          list.filter(
            outputs,
            fn(output) {
              output.address.payment_credential == this_address.payment_credential
            },
          )
        // either new_list_raw points to new_list_raw_2, or vice versa
        // needs to be decided for validation
        False
      }
    }
  }
}
