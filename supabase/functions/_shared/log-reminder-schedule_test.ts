/**
 * London log-reminder slot gate (weekday vs weekend).
 */
import { assertEquals } from "jsr:@std/assert@1";
import {
  reminderSlotAt,
  shouldRunLogReminder,
} from "./log-reminder-schedule.ts";

Deno.test("weekday London slots: 09 / 14 / 21", () => {
  // Wednesday 2026-07-15 BST
  assertEquals(reminderSlotAt(Date.parse("2026-07-15T08:00:00.000Z")), "morning");
  assertEquals(reminderSlotAt(Date.parse("2026-07-15T09:00:00.000Z")), null);
  assertEquals(reminderSlotAt(Date.parse("2026-07-15T13:00:00.000Z")), "lunch");
  assertEquals(reminderSlotAt(Date.parse("2026-07-15T20:00:00.000Z")), "evening");
  // Thursday 2026-01-15 GMT
  assertEquals(reminderSlotAt(Date.parse("2026-01-15T09:00:00.000Z")), "morning");
  assertEquals(reminderSlotAt(Date.parse("2026-01-15T14:00:00.000Z")), "lunch");
  assertEquals(reminderSlotAt(Date.parse("2026-01-15T21:00:00.000Z")), "evening");
});

Deno.test("Saturday only 10:00 London as morning", () => {
  // 2026-07-18 Saturday BST
  assertEquals(reminderSlotAt(Date.parse("2026-07-18T08:00:00.000Z")), null);
  assertEquals(reminderSlotAt(Date.parse("2026-07-18T09:00:00.000Z")), "morning");
  assertEquals(reminderSlotAt(Date.parse("2026-07-18T10:00:00.000Z")), null);
  assertEquals(reminderSlotAt(Date.parse("2026-07-18T13:00:00.000Z")), null);
  assertEquals(reminderSlotAt(Date.parse("2026-07-18T20:00:00.000Z")), null);
  // 2026-01-17 Saturday GMT
  assertEquals(reminderSlotAt(Date.parse("2026-01-17T10:00:00.000Z")), "morning");
  assertEquals(reminderSlotAt(Date.parse("2026-01-17T11:00:00.000Z")), null);
});

Deno.test("Sunday only 11:00 London as morning", () => {
  // 2026-07-19 Sunday BST
  assertEquals(reminderSlotAt(Date.parse("2026-07-19T09:00:00.000Z")), null);
  assertEquals(reminderSlotAt(Date.parse("2026-07-19T10:00:00.000Z")), "morning");
  assertEquals(reminderSlotAt(Date.parse("2026-07-19T13:00:00.000Z")), null);
  // 2026-01-18 Sunday GMT
  assertEquals(reminderSlotAt(Date.parse("2026-01-18T11:00:00.000Z")), "morning");
  assertEquals(reminderSlotAt(Date.parse("2026-01-18T10:00:00.000Z")), null);
  assertEquals(shouldRunLogReminder(Date.parse("2026-01-18T11:00:00.000Z")), true);
});
