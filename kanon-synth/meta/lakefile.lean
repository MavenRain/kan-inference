import Lake
open Lake DSL

package «kanon-meta» where
  leanOptions := #[⟨`autoImplicit, false⟩]

require «kan-tactics» from git
  "/Users/oobi/Documents/kan-tactics" @ "3317f7ac5a22ca0d85b90a3286b8fe0c36cea8ac"

@[default_target]
lean_lib «KanonMeta» where
  roots := #[`KanonMeta]

@[default_target]
lean_lib «KanonMetaTests» where
  roots := #[`test.Regression, `test.Initiality, `test.InitialChain, `test.VectorConstruction]
