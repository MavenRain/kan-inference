// The Stage D runner.  It instantiates one module with no import, calls
// the exported function and prints the i32 answer in decimal.
//
// Exit codes.  0 is an answer, 1 is a trap, 2 is a module the engine
// refuses and 64 is a usage error.  Node needs no flag for the garbage
// collected types from version 22 on.
//
// usage: node dev/run-node.mjs FILE.wasm NAME

import { readFile } from "node:fs/promises";
import process from "node:process";

const usage = "usage: node run-node.mjs FILE.wasm NAME";

const fail = (line, code) => {
  process.stderr.write(line + "\n");
  process.exit(code);
};

// The engine reports a bad module as a compile or a link error and a bad
// run as a runtime error, so the class of the error picks the exit code.
const table = [
  [WebAssembly.RuntimeError, "trap: ", 1],
  [WebAssembly.CompileError, "invalid: ", 2],
  [WebAssembly.LinkError, "invalid: ", 2],
];

const classify = (e) =>
  table.find(([kind]) => e instanceof kind) ?? [null, "invalid: ", 2];

const text = (e) => (e && e.message ? e.message : String(e));

const main = async (args) => {
  const [path, name] = args;
  const bytes = await readFile(path);
  const { instance } = await WebAssembly.instantiate(bytes, {});
  const f = instance.exports[name];
  return typeof f === "function"
    ? process.stdout.write(String(f()) + "\n")
    : fail("invalid: no exported function " + name, 2);
};

const args = process.argv.slice(2);

args.length === 2
  ? main(args).then(
      () => process.exit(0),
      (e) => {
        const [, prefix, code] = classify(e);
        fail(prefix + text(e), code);
      },
    )
  : fail(usage, 64);
