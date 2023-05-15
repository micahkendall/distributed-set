use aiken/builtin
use aiken/hash.{Blake2b_224, Hash, blake2b_256}

// generalises my 'oref_hash'
pub fn data_hash(d: Data) -> Hash<Blake2b_224, Data> {
  blake2b_256(builtin.serialise_data(d))
}

// strict sort validator
pub fn is_sorted(l: List<ByteArray>) -> Bool {
  when l is {
    [] ->
      True
    [_] ->
      True
    [x, y, ..xs] ->
      builtin.less_than_bytearray(x, y) && is_sorted([y, ..xs])
  }
}

pub fn sum_map(l: List<a>, f: fn(a) -> Int) -> Int {
  when l is {
    [] ->
      0
    [x, ..xs] ->
      f(x) + sum_map(xs, f)
  }
}

pub fn count_map(l: List<a>, f: fn(a) -> Bool) -> Int {
  when l is {
    [] ->
      0
    [x, ..xs] ->
      if f(x) {
        1
      } else {
        0
      } + count_map(xs, f)
  }
}
