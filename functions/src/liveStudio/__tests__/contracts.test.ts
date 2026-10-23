import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { defaultSettings, emptyStage, Limits } from '../contracts';

test('defaults mirror the Dart contracts', () => {
  assert.equal(defaultSettings('light').frameColor, '#3B4763');
  assert.equal(defaultSettings('light').studioDim, 0);
  assert.equal(defaultSettings().guestSize, 'm');
  assert.equal(emptyStage('h').wall.length, Limits.wallSlots);
});
