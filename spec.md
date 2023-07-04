## Specification of the distributed set implementation

### Initialisation

- must consume genesis UTxO
- must mint
  - genesis NFT `hash(genesis_utxo)`
  - nothing else from this policy
- must have output
  - which is at this policy
  - that must have own NFT
- the list:
  - must have no next
  - must be a head
  - must be strictly sorted (no equal elements)
  - must have no values greater or equal to next
- the script call check must pass

preserved forever:

- script
- stake key
- set invariants

### Continuation (insertion)

- must spend one output containing a set NFT
- must produce an output containing only that set NFT, at the same address
- must mint nothing here (or, we shouldn't care about minting?)
- must use the Unit redeemer
- the list:
  - must have the same id
  - must have the same next
  - must have the same head value
  - must have the same required script
  - must be strictly sorted (no equal elements)
  - must have no values greater or equal to next, unless next is none
  - must have no values lesser than current minimum
- the script call check must pass

### Splitting (insertion)

- must spend one output containing a set NFT
- must produce two outputs, where the first contains the old nft, and the second contains a new nft
- we find the first continuing output by same id (tagging), then the next output is the one directly after. (drop until, then take 2?)
- these must be at the same address
- must mint an nft, which must be the hash of the consuming set utxo
- every minted NFT, must be a set UTxO being spent from this script, and also which invokes the BinarySplit redeemer. (then, mint redeemer doesn't need any values)
- the first and second outputs are uniquely linked
- todo: consider the lists as concatenated
- the first list:
  - must have the old id
  - must have the second nft as next (and the second nfts min, as next_min)
  - must have the old head value
  - must have the old required script
  - must be strictly sorted (no equal elements)
  - must have no values greater or equal to next
  - must have no values lesser than old minimum
- the second list:
  - must have the id of the new nft
  - must have the old next
  - must have a head value of False
  - must have the same required script
  - must be strictly sorted (no equal elements)
  - must have no values greater or equal to next, unless next is none
  - must have no values lesser than new minimum
  - may be empty
- the script call check must pass
