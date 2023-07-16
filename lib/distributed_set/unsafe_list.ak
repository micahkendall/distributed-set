// todo:
// unsafe_find
// assert_any

pub fn find(l: List<a>, f: fn(a) -> Bool) -> a {
  when l is {
    [x, ..xs] ->
      if f(x) {
        x
      } else {
        find(xs, f)
      }
    _ -> error
  }
}
