'use strict';

const _ = require('lodash');

/**
 * Calculates a weighted final mark (0-100), rounded to one decimal.
 * @param {{ mark: number, weight: number }[]} components assessment components; weights must add up to 100
 * @returns {number}
 */
function finalMark(components) {
  if (!Array.isArray(components) || components.length === 0) {
    throw new Error('At least one assessment component is required');
  }

  const totalWeight = _.sumBy(components, 'weight');
  if (Math.abs(totalWeight - 100) > 0.001) {
    throw new Error(`Weights must add up to 100 (got ${totalWeight})`);
  }

  for (const { mark } of components) {
    if (typeof mark !== 'number' || Number.isNaN(mark) || mark < 0 || mark > 100) {
      throw new Error(`Invalid mark: ${mark}`);
    }
  }

  const weighted = _.sumBy(components, (c) => (c.mark * c.weight) / 100);
  return _.round(weighted, 1);
}

/**
 * Maps a final mark to a result.
 * @param {number} mark
 * @returns {'Distinction' | 'Pass' | 'Supplementary' | 'Fail'}
 */
function result(mark) {
  if (mark >= 75) return 'Distinction';
  if (mark >= 50) return 'Pass';
  if (mark >= 40) return 'Supplementary';
  return 'Fail';
}

/**
 * Adds bonus marks, never exceeding 100.
 * @param {number} mark
 * @param {number} bonus
 */
function applyBonus(mark, bonus) {
  return mark + bonus;
}

module.exports = { finalMark, result, applyBonus };
