import { assertEquals } from "jsr:@std/assert@1";
import {
  customerDisplayName,
  customerEmail,
  customerRosterId,
  emailsMatch,
  pickCustomerByEmail,
} from "./handler.ts";

Deno.test("customerDisplayName prefers first_name + last_name", () => {
  assertEquals(
    customerDisplayName({ first_name: "Lee", last_name: "Ball", name: "Other" }),
    "Lee Ball",
  );
  assertEquals(customerDisplayName({ first_name: "Ada" }), "Ada");
  assertEquals(customerDisplayName({ name: "Fallback" }), "Fallback");
  assertEquals(customerDisplayName({}), null);
});

Deno.test("pickCustomerByEmail requires an exact email match and ignores id", () => {
  const rows = [
    { id: 6714431, first_name: "Lee", last_name: "Ball", email: "lee@example.com", status: "converted" },
    { id: 1, first_name: "Other", last_name: "Person", email: "other@example.com", status: "converted" },
  ];
  const match = pickCustomerByEmail(rows, "Lee@example.com");
  assertEquals(match?.first_name, "Lee");
  assertEquals(customerDisplayName(match!), "Lee Ball");
  assertEquals(pickCustomerByEmail(rows, "missing@example.com"), null);
});

Deno.test("emailsMatch is case-insensitive", () => {
  assertEquals(emailsMatch("A@B.Co", "a@b.co"), true);
  assertEquals(emailsMatch("a@b.co", "c@d.co"), false);
});

Deno.test("customerRosterId stringifies numeric TeamUp ids", () => {
  assertEquals(customerRosterId({ id: 6714431 }), "6714431");
  assertEquals(customerRosterId({ id: "6714431" }), "6714431");
  assertEquals(customerRosterId({}), null);
});

Deno.test("customerEmail reads email, email_address, or nested user.email", () => {
  assertEquals(customerEmail({ email: "a@b.co" }), "a@b.co");
  assertEquals(customerEmail({ email_address: "a@b.co" }), "a@b.co");
  assertEquals(customerEmail({ user: { email: "a@b.co" } }), "a@b.co");
  assertEquals(customerEmail({}), null);
});

Deno.test("lookupDisplayNameByEmailBestEffort returns null when M2M is unset", async () => {
  const { lookupDisplayNameByEmailBestEffort } = await import(
    "../_shared/teamup-customers.ts"
  );
  const originalGet = Deno.env.get.bind(Deno.env);
  Deno.env.get = (name: string) => {
    if (name === "TEAMUP_M2M_TOKEN" || name === "TEAMUP_OAUTH_PROVIDER_ID") {
      return undefined;
    }
    return originalGet(name);
  };
  try {
    assertEquals(
      await lookupDisplayNameByEmailBestEffort("a@b.co"),
      null,
    );
  } finally {
    Deno.env.get = originalGet;
  }
});
