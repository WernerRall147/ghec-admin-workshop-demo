'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { isSupplementaryEligible } = require('../src/marks');

test('40-49 is eligible', () => {
  assert.equal(isSupplementaryEligible(40), true);
  assert.equal(isSupplementaryEligible(49.9), true);
});

test('below 40 or 50+ is not eligible', () => {
  assert.equal(isSupplementaryEligible(39.9), false);
  assert.equal(isSupplementaryEligible(50), false);
});
