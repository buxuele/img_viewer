# img_viewer spec

Every requirement is a row with an id. Agents build against approved rows; commits cite the ids they serve. `pullboard spec check` lints this file.

Statuses: approved = decided · draft = proposed · pending = open question · fact = true today · wont = won't build, decided and kept · retired = no longer applies, kept. Ids are permanent: never delete or renumber a row. Tiers: must · aim.

Write each requirement as one row under its section, in this format. The fence keeps the example out of the spec, so no placeholder id is ever committed; your own rows go below, outside it.

```text
- G1 [draft, must] The first thing the client needs, in one line. | gate: the test that proves it
- K1 [draft, must] A constraint, e.g. runs locally with no account. | gate: review
```

## G · Goals: what the client asked for

## K · Constraints

## A · Web app

- A1 [draft, must] Every change ships with a test that fails without it. Why: a test that passes either way proves nothing. | gate: review
- A2 [draft, must] Main only moves when the whole test suite passes. Why: two changes can each pass alone and still break each other. | gate: review
- A3 [draft, must] Every page works at phone width before it ships. Why: a page that only works on a laptop is a bug nobody reports. | gate: review
- A4 [draft, must] Secrets never appear in code, logs or commits. Why: a key pushed once stays public, even after you delete it. | gate: review
- A5 [draft, must] A new dependency comes with a one-line reason. Why: every package you add is code you now maintain. | gate: review
- A6 [draft, must] An error a person sees says what to do next. Why: "something went wrong" is a support ticket waiting to happen. | gate: review
- A7 [draft, must] Tests bind a local port, so a sandboxed agent asks the person instead of rewriting the tests. Why: a test rewritten into a fake passes inside the sandbox and proves nothing about the real server. | gate: review
- A8 [pending, must] The app is built with: (choose one). Choices: Next.js, SvelteKit, Rails, Something else. | gate: review
- A9 [pending, must] It deploys to: Vercel. Choices: Vercel, Netlify, Fly.io, My own server. | gate: review
- A10 [pending, must] People sign in with: Email links. Choices: Email links, Passwords, Google, No sign-in yet. | gate: review
- A11 [pending, must] A change is done when: It runs on a preview link. Choices: It runs on a preview link, Its tests pass, I have looked at it. | gate: review
<!-- pullboard-blueprint-kind web-app product -->
<!-- pullboard-blueprint web-app 1 -->
