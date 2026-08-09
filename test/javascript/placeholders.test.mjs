import assert from 'node:assert/strict'
import { test } from 'node:test'

import {
  BODY_PLACEHOLDERS,
  SUBJECT_PLACEHOLDERS,
} from '../../app/javascript/lib/placeholders.ts'

const senderPlaceholders = [
  '{{sender_first_name}}',
  '{{sender_last_name}}',
  '{{sender_full_name}}',
  '{{sender_company}}',
]

function values(placeholders) {
  return placeholders.map((placeholder) => placeholder.value)
}

test('subject slash picker includes sender name placeholders', () => {
  assert.deepEqual(
    senderPlaceholders.every((placeholder) => values(SUBJECT_PLACEHOLDERS).includes(placeholder)),
    true,
  )
})

test('body slash picker includes sender name placeholders', () => {
  assert.deepEqual(
    senderPlaceholders.every((placeholder) => values(BODY_PLACEHOLDERS).includes(placeholder)),
    true,
  )
})
