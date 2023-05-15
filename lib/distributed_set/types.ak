use aiken/hash.{Blake2b_224, Hash}
use aiken/transaction.{OutputReference}
use aiken/transaction/credential.{Script}

pub type ListRedeemer {
  Unit
  BinarySplit(OutputReference)
}

pub type ListDatum {
  id: Hash<Blake2b_224, OutputReference>,
  next: Option<Hash<Blake2b_224, OutputReference>>,
  is_head: Bool,
  // may need artificial length limit on this list to prevent DoS
  // Length limit on List AND on bytearray will be necessary
  values: List<ByteArray>,
  requires: Option<RequiredScript>,
}

pub type RequiredScript {
  RequireMint(Hash<Blake2b_224, Script>)
  RequireStake(Hash<Blake2b_224, Script>)
}
