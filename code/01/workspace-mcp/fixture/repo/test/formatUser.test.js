import assert from "node:assert/strict";
import test from "node:test";

import { formatUser } from "../src/formatUser.js";

test("upper-cases a profile name", () => {
  assert.equal(formatUser({ profile: { name: "Maya" } }), "MAYA");
});
test("returns UNKNOWN when profile data is missing", () => {
  assert.equal(formatUser({}), "UNKNOWN");
  assert.equal(formatUser(null), "UNKNOWN");
});
