use aiken/dict
use aiken/list
use aiken/option
use aiken/transaction.{
  InlineDatum, Input, Mint, Output, OutputReference, ScriptContext, Spend,
  Transaction,
}
use aiken/transaction/credential.{Credential, Inline, ScriptCredential}
use aiken/transaction/value
use distributed_set/types.{
  BinarySplit, ListDatum, ListRedeemer, RequireMint, RequireStake, Unit,
}
use distributed_set/unsafe_list
use distributed_set/util

// could implement required scripts by searching for a specific redeemer, and enforcing a particular redeemer type.
// This makes it easier to validate insertions, because all insertions can be provided in that redeemer.

fn has_input(inputs: List<Input>, oref: OutputReference) {
  inputs |> list.any(fn(input) { input.output_reference == oref })
}

fn find_input(inputs: List<Input>, oref: OutputReference) {
  inputs |> list.find(fn(input) { input.output_reference == oref })
}

fn inputs_at_cred(inputs: List<Input>, script_credential: Credential) {
  inputs
    |> list.filter(
         fn(input) {
           input.output.address.payment_credential == script_credential
         },
       )
}

fn outputs_at_cred(outputs: List<Output>, script_credential: Credential) {
  outputs
    |> list.filter(
         fn(output) { output.address.payment_credential == script_credential },
       )
}

fn was_invoked(invoked, minted, withdrawals) {
  when invoked is {
    RequireMint(minting_script) ->
      !dict.is_empty(value.tokens(minted, minting_script))
    RequireStake(staking_script) ->
      list.any(
        dict.keys(withdrawals),
        fn(key) { key == Inline(ScriptCredential(staking_script)) },
      )
  }
}

validator(genesis_utxo: OutputReference) {
  fn mint_distributed_set(redeemer: ListRedeemer, ctx) -> Bool {
    let ScriptContext(
      Transaction { inputs, outputs, mint, withdrawals, .. },
      purpose,
    ) = ctx
    expect Mint(this_policy) = purpose
    let this_credential = ScriptCredential(this_policy)
    let minted = mint |> value.from_minted_value
    trace @"1"
    let minted_here =
      minted
        |> value.flatten
        |> unsafe_list.find(
             fn(minted_nfts) {
               let (policy, _, _) = minted_nfts
               policy == this_policy
             },
           )
    when redeemer is {
      Unit -> {
        trace @"2"
        // convert to assert_any
        let asset_name = genesis_utxo |> util.data_hash
        trace @"3.1"
        expect [Output(_, new_val, new_datum_out, _)] =
          outputs
            |> outputs_at_cred(this_credential)
        trace @"3.2"
        expect InlineDatum(new_list_raw) = new_datum_out
        trace @"3.3"
        expect [_, (out_policy, _out_asset_name, out_asset_amt)] =
          new_val |> value.flatten
        // && out_asset_name == asset_name
        // the only possible minted value at genesis is the correct asset name.
        trace @"3.4"
        expect ListDatum { id, next, is_head, requires, values }: ListDatum =
          new_list_raw
        trace @"4"
        //
        let sort_check = util.is_sorted(values)
        let script_call_check =
          requires
            |> option.map(was_invoked(_, minted, withdrawals))
            |> option.or_else(True)
        let asset_sent_check = out_asset_amt == 1
        let next_check = next == None
        //
        trace @"5"
        [
          has_input(inputs, genesis_utxo)?,
          (minted_here == (this_policy, asset_name, 1))?,
          (out_policy == this_policy)?,
          script_call_check?,
          (id == asset_name)?,
          next_check?,
          is_head?,
          asset_sent_check?,
          sort_check?,
        ]
          |> list.and
      }

      // need to enforce it is minted to the control script, that the datum is correct, and the value is correct.
      // on insert, if 1 token is spent, allow 1 additional token to be minted,
      // and the control validator ensures that additional token is correctly linked
      BinarySplit { consuming: output_reference } -> {
        let asset_name = output_reference |> util.data_hash
        expect [_ctrl_inp] = inputs |> inputs_at_cred(this_credential)
        expect [_out1, _out2] = outputs |> outputs_at_cred(this_credential)
        [
          inputs
            |> has_input(output_reference),
          minted_here == (this_policy, asset_name, 1),
          False,
        ]
          |> list.and
      }
    }
  }

  fn spend_distributed_set(
    datum: ListDatum,
    redeemer: ListRedeemer,
    ctx,
  ) -> Bool {
    // should enforce only one input from this script
    // then, enforce on all the outputs that the list is maintained,
    // and that those outputs have the list NFT.
    let ScriptContext(
      Transaction { inputs, outputs, mint, withdrawals, .. },
      purpose,
    ) = ctx
    expect Spend(output_reference) = purpose
    let minted = value.from_minted_value(mint)
    // find this
    expect Some(Input {
      output: Output(this_address, val, InlineDatum(_), None),
      ..
    }) = inputs |> find_input(output_reference)
    expect [in_nft_tuple] = val |> value.flatten
    // let (_this_nft_policy, [(_this_nft_assetname, this_nft_amount)]) = in_nft_tuple
    // assert only one input from this script
    let this_credential = this_address.payment_credential
    let inputs_from_here_check =
      util.count_map(
        inputs,
        fn(input) { input.output.address.payment_credential == this_credential },
      ) == 1
    let ListDatum { id, next, is_head, values, requires }: ListDatum = datum
    // the list is assumed to be sorted as invariant is maintained by mint,control
    // spending, there should be either two outputs at this script, or one.
    // this is decided by the ListSpendRedeemer
    let script_call_check =
      requires
        |> option.map(was_invoked(_, minted, withdrawals))
        |> option.or_else(True)
    when redeemer is {
      Unit -> {
        // assert that the singular output at this address, is the same as the input, except for the inner values
        // head and final element of values and new_values are asserted to be the same
        // then, we assert that new_values are sorted.

        // TODO: check every input value is included in the new values
        expect [Output(_, new_val, InlineDatum(new_list_raw), None)] =
          list.filter(
            outputs,
            fn(output) { output.address.payment_credential == this_credential },
          )
        expect [out_nft_tuple] = new_val |> value.flatten
        expect ListDatum {
          id: new_id,
          next: new_next,
          is_head: new_is_head,
          values: new_values,
          requires: new_req,
        }: ListDatum = new_list_raw
        let nft_check = out_nft_tuple == in_nft_tuple
        let continuing_check = new_id == id && new_is_head == is_head
        let required_script_check = new_req == requires
        let next_check = new_next == next
        let head_check = is_head || list.head(values) == list.head(new_values)
        let tail_check =
          next == None || list.last(values) == list.last(new_values)
        let sort_check = util.is_sorted(new_values)

        // next is the same
        // if head, smaller values may be added, otherwise they may not
        // if tail, larger values may be added, otherwise they may not
        // values must always be sorted
        let utxo_checks = [inputs_from_here_check, nft_check] |> list.and
        let list_checks =
          [
            continuing_check,
            next_check,
            head_check,
            sort_check,
            tail_check,
            required_script_check,
          ]
            |> list.and
        [utxo_checks, list_checks, script_call_check]
          |> list.and
      }
      BinarySplit(_) -> {
        // find the tagged continuing output
        // the output directly after, is the second output
        // (using ordering)
        expect [
          Output(_, new_val, InlineDatum(new_list_raw), None),
          Output(_, new_val_2, InlineDatum(new_list_raw_2), None),
        ] = outputs |> outputs_at_cred(this_credential)
        expect [new_val_nft_tuple] = new_val |> value.flatten
        expect [new_val_nft_tuple_2] = new_val_2 |> value.flatten
        expect ListDatum {
          id: new_id,
          next: new_next,
          is_head: new_is_head,
          values: new_values,
          requires: new_req,
        }: ListDatum = new_list_raw
        expect ListDatum {
          id: new_id2,
          next: new_next2,
          is_head: new_is_head2,
          values: new_values2,
          requires: new_req2,
        }: ListDatum = new_list_raw_2
        let (the_nft_policy, _, _) = new_val_nft_tuple
        let new_nft_tuple =
          (the_nft_policy, util.data_hash(output_reference), 1)
        let nft_check =
          new_val_nft_tuple == in_nft_tuple && new_val_nft_tuple_2 == new_nft_tuple
        let continuing_check = new_id == id && new_is_head == is_head
        let required_script_check = new_req == requires && new_req2 == requires
        let next_check =
          new_next == Some(new_id2) && new_next2 == next && new_is_head2 == False
        let head_check = new_is_head == is_head
        let sort_check =
          util.is_sorted(new_values) && util.is_sorted(new_values2)
        let tail_check = False
        // heads are allowed to be empty, tails must have 1, and non-heads must have 2+ elements.
        // each list node must contain the relevant nft.
        [
          inputs_from_here_check,
          continuing_check,
          required_script_check,
          sort_check,
          nft_check,
          next_check,
          head_check,
          tail_check,
          script_call_check,
        ]
          |> list.and
      }
    }
  }
}
