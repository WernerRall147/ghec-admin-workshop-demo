'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { finalMark, result } = require('../src/marks');

test('calculates a weighted final mark', () => {
  assert.equal(finalMark([{ mark: 80, weight: 30 }, { mark: 60, weight: 70 }]), 66);
});

test('rounds to one decimal', () => {
  assert.equal(finalMark([{ mark: 67, weight: 33.3 }, { mark: 71, weight: 66.7 }]), 69.7);
});

test('rejects weights that do not add up to 100', () => {
  assert.throws(() => finalMark([{ mark: 50, weight: 40 }]), /Weights must add up to 100/);
});

test('rejects marks outside 0-100', () => {
  assert.throws(() => finalMark([{ mark: 101, weight: 100 }]), /Invalid mark/);
});

test('maps marks to results', () => {
  assert.equal(result(80), 'Distinction');
  assert.equal(result(75), 'Distinction');
  assert.equal(result(62), 'Pass');
  assert.equal(result(45), 'Supplementary');
  assert.equal(result(12), 'Fail');
});
