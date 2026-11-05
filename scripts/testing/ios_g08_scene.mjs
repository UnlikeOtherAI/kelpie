import assert from "node:assert/strict";
import {mapG08Scene} from "../../tests/capture/g08-fixture.mjs";

export function iosG08Scene(facts) {
  assert.equal(facts.dropped, 0);
  return mapG08Scene(facts.events);
}
