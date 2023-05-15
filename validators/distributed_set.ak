use aiken/builtin
use aiken/dict
use aiken/hash.{Blake2b_224, Hash, blake2b_256}
use aiken/list
use aiken/transaction.{
  InlineDatum, Input, Mint, Output, OutputReference, ScriptContext, Spend,
  Transaction,
}
use aiken/transaction/credential.{Credential, Inline, ScriptCredential}
use aiken/transaction/value.{tokens}
use distributed_set/types.{
  BinarySplit, ListDatum, ListRedeemer, RequireMint, RequireStake, Unit,
}
use distributed_set/unsafe_list
use distributed_set/unsafe_value
use distributed_set/util

// could implement required scripts by searching for a specific redeemer, and enforcing a particular redeemer type.
// This makes it easier to validate insertions, because all insertions can be provided in that redeemer.

validator(control_script: Credential, genesis_utxo: OutputReference) {
  fn mint_distributed_set(redeemer: ListRedeemer, ctx) -> Bool {
    let ScriptContext(
      Transaction(inputs, _, outputs, _, mint, _, withdrawals, _, _, _, _, _),
      Mint(this_policy),
    ) =
      ctx
    let lmint =
      unsafe_value.unvalue(mint)
    let minted_here =
      unsafe_list.find(
        lmint,
        fn(minted_nfts) {
          let (policy, _) =
            minted_nfts
          policy == this_policy
        },
      )
    when redeemer is {
      Unit -> {
        // convert to assert_any
        let asset_name =
          util.data_hash(genesis_utxo)
        expect [Output(_, new_val, InlineDatum(new_list_raw), None)] =
          list.filter(
            outputs,
            fn(output) { output.address.payment_credential == control_script },
          )
        expect [_ada, (out_policy, [(_out_asset_name, out_asset_amt)])] =
          unsafe_value.unvalue(new_val)
        expect True =
          out_asset_amt == 1
        // && out_asset_name == asset_name // This is redundant since the only possible minted value at genesis is the correct asset name.
        expect ListDatum(
          new_list_id,
          new_list_next,
          new_list_is_head,
          _new_list_values,
          required_script,
        ): ListDatum =
          new_list_raw
        let clause_check =
          when required_script is {
            None ->
              True
            Some(invoked) ->
              when invoked is {
                RequireMint(minting_script) ->
                  !dict.is_empty(tokens(mint, minting_script))
                RequireStake(staking_script) ->
                  list.any(
                    dict.keys(withdrawals),
                    fn(key) { key == Inline(ScriptCredential(staking_script)) },
                  )
              }
          }
        list.any(inputs, fn(input) { input.output_reference == genesis_utxo }) && minted_here == (
          this_policy,
          [(asset_name, 1)],
        ) && out_policy == this_policy && clause_check && new_list_id == asset_name && new_list_next == None && new_list_is_head == True
      }

      // need to enforce it is minted to the control script, that the datum is correct, and the value is correct.
      // on insert, if 1 token is spent, allow 1 additional token to be minted,
      // and the control validator ensures that additional token is correctly linked
      BinarySplit(new_ref) -> {
        let asset_name =
          util.data_hash(new_ref)
        expect True =
          list.any(inputs, fn(input) { input.output_reference == new_ref }) && minted_here == (
            this_policy,
            [(asset_name, 1)],
          )
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

pub fn id_f(a) {
  a
}

// todo: solve deadlock attack by appending a new 'empty list' via BinarySplit
// todo: allow inserting between the top value of one list, and the bottom value of the next list (next_min?)

// the set property is maintained (unique elements) across the utxo set
// This is done by maintaining strict ordering of the list (every element is greater than the previous)
// I.e 'greater or equal' fails to satisfy that.
// Any insert can be made by spending a single UTxO, and in case of too many elements,
// you can simply mint a new list and link it to the previous one.
// This simple implementation restricts to a single spend to make this easier to validate.
// It shouldn't be necessary to mint two lists, so minting can always be done one at a time.
validator {
  fn spend_distributed_set(_d: ListDatum, r: ListRedeemer, ctx) -> Bool {
    // should enforce only one input from this script
    // then, enforce on all the outputs that the list is maintained,
    // and that those outputs have the list NFT.
    let ScriptContext(
      Transaction(inputs, _, outputs, _, minted, _, withdrawals, _, _, _, _, _),
      Spend(output_reference),
    ) =
      ctx
    // find this
    expect Some(Input(
      _,
      Output(this_address, val, InlineDatum(this_list_raw), None),
    )) =
      list.find(
        inputs,
        fn(input) { input.output_reference == output_reference },
      )
    expect [(_ada_policy, [(_lovelace_assetname, _ada_amount)]), in_nft_tuple] =
      unsafe_value.unvalue(val)
    // let (_this_nft_policy, [(_this_nft_assetname, this_nft_amount)]) = in_nft_tuple
    // assert only one input from this script
    let this_address_payment_credential =
      this_address.payment_credential
    expect True =
      util.count_map(
        inputs,
        fn(input) {
          input.output.address.payment_credential == this_address_payment_credential
        },
      ) == 1
    expect ListDatum(id, next, is_head, values, required_script): ListDatum =
      this_list_raw
    // the list is assumed to be sorted as invariant is maintained by mint,control
    // spending, there should be either two outputs at this script, or one.
    // this is decided by the ListSpendRedeemer
    expect True =
      when required_script is {
        None ->
          True
        Some(invoked) ->
          when invoked is {
            RequireMint(minting_script) ->
              !dict.is_empty(tokens(minted, minting_script))
            RequireStake(staking_script) ->
              list.any(
                dict.keys(withdrawals),
                fn(key) { key == Inline(ScriptCredential(staking_script)) },
              )
          }
      }
    when r is {
      Unit -> {
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
        expect [(_, [(_, _ada_amount_2)]), out_nft_tuple] =
          unsafe_value.unvalue(new_val)
        expect ListDatum(new_id, new_next, new_is_head, new_values, new_req): ListDatum =
          new_list_raw
        let head_check =
          is_head || list.head(values) == list.head(new_values)
        let tail_check =
          next == None || list.last(values) == list.last(new_values)
        let sort_check =
          util.is_sorted(new_values)
        [
          // the id is the same
          new_id == id,
          // next is the same
          new_next == next,
          // if head, smaller values may be added, otherwise they may not
          head_check,
          // if tail, larger values may be added, otherwise they may not
          tail_check,
          // values must always be sorted
          sort_check,
          required_script == new_req,
          new_is_head == is_head,
          out_nft_tuple == in_nft_tuple,
        ]
          |> list.all(id_f)
      }
      BinarySplit(_) -> {
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
        expect [(_, [(_, _ada_amount_2)]), new_val_nft_tuple] =
          unsafe_value.unvalue(new_val)
        expect [(_, [(_, _ada_amount_3)]), new_val_nft_tuple_2] =
          unsafe_value.unvalue(new_val_2)
        // we can assume the outputs are sorted, because you can tell offchain to put them in sorted order.
        // so, validate that the two lists are sorted, and that the two lists are linked.
        expect new_list: ListDatum =
          new_list_raw
        expect new_list_2: ListDatum =
          new_list_raw_2
        expect (the_nft_policy, _) =
          new_val_nft_tuple
        let new_nft_tuple =
          (the_nft_policy, [(util.data_hash(output_reference), 1)])
        let nft_check =
          new_val_nft_tuple == in_nft_tuple && new_val_nft_tuple_2 == new_nft_tuple
        let continuing_check =
          new_list.id == id && new_list.is_head == is_head
        let required_script_check =
          new_list.requires == required_script && new_list_2.requires == required_script
        let next_check =
          new_list.next == Some(new_list_2.id) && new_list_2.next == next && new_list_2.is_head == False
        let head_check =
          new_list.is_head == is_head
        let sort_check =
          util.is_sorted(new_list.values) && util.is_sorted(new_list_2.values)
        // heads are allowed to be empty, tails must have 1, and non-heads must have 2+ elements.
        // each list node must contain the relevant nft.
        [
          // that the new list value maintains old list properties
          continuing_check,
          // that new lists both have the same required script
          required_script_check,
          // values must always be sorted
          sort_check,
          // enforces old nft is at list1, and new nft is at list2
          nft_check,
          next_check,
          head_check,
        ]
          |> list.all(id_f)
      }
    }
  }
}
