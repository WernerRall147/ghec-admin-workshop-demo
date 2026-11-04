'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { applyBonus } = require('../src/marks');

test('adds bonus marks', () => {
  assert.equal(applyBonus(60, 5), 65);
});

test('caps the mark at 100', () => {
  assert.equal(applyBonus(98, 5), 100);
});
