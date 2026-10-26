const assert = require('node:assert/strict');
const test = require('node:test');
const {centerDateStatus, localCalendarDate} =
  require('../lib/places/local_date.js');

test('county day changes at local midnight, not UTC midnight', () => {
  const zone = 'America/Los_Angeles';
  assert.equal(localCalendarDate(new Date('2026-06-05T06:59:59Z'), zone),
    '2026-06-04');
  assert.equal(localCalendarDate(new Date('2026-06-05T07:00:00Z'), zone),
    '2026-06-05');
  assert.equal(centerDateStatus('2026-06-04', '2026-06-05',
    '2026-06-05'), 'date-listed');
  assert.equal(centerDateStatus('2026-06-04', '2026-06-05',
    '2026-06-06'), 'expired');
});

test('local dates remain correct across both Pacific DST changes', () => {
  const zone = 'America/Los_Angeles';
  assert.equal(localCalendarDate(new Date('2026-03-08T09:59:59Z'), zone),
    '2026-03-08');
  assert.equal(localCalendarDate(new Date('2026-03-08T10:00:00Z'), zone),
    '2026-03-08');
  assert.equal(localCalendarDate(new Date('2026-11-01T08:59:59Z'), zone),
    '2026-11-01');
  assert.equal(localCalendarDate(new Date('2026-11-01T09:00:00Z'), zone),
    '2026-11-01');
  assert.equal(localCalendarDate(new Date('2026-11-02T07:59:59Z'), zone),
    '2026-11-01');
  assert.equal(localCalendarDate(new Date('2026-11-02T08:00:00Z'), zone),
    '2026-11-02');
});

test('invalid source dates and zones fail before classification', () => {
  assert.throws(() => centerDateStatus('2026-02-30', '2026-03-01',
    '2026-03-01'), RangeError);
  assert.throws(() => centerDateStatus('2026-06-05', '2026-06-04',
    '2026-06-04'), RangeError);
  assert.throws(() => localCalendarDate(new Date(), 'Unknown/Zone'),
    RangeError);
});
