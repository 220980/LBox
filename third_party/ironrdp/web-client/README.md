# IronRDP Web Client

IronRDP also supports the web browser as a first class target.

## Prerequisites

- Node.js >= 24 LTS (type definitions target `@types/node` ^24.0.0)

## Overview

See the [iron-remote-desktop](./iron-remote-desktop) for the reusable Web Component, and [iron-svelte-client](./iron-svelte-client) for a demonstration.

## In ServerBox's fork

ServerBox neither builds nor ships these web clients; nothing in this fork runs them. Their locks get `npm audit fix` without major upgrades. TODO: what `npm audit` still reports — vitest and its UI (critical), SvelteKit, typescript-eslint, svelte-check (high) — is development tooling whose fix is a major version (vitest 5, SvelteKit 3, typescript-eslint 8, svelte-check 4) and a migration of these clients with it, left until a client is built from here.

Note that the demonstration client is not intended to be used in production as-is.
Devolutions is shipping well-integrated, production-ready IronRDP web clients as part of:

- [Devolutions Gateway](https://github.com/Devolutions/devolutions-gateway/)’s [Standalone Web Interface](https://github.com/Devolutions/devolutions-gateway/tree/master/webapp) which is a completely free product (shipped since v2024.1.0).
- [Devolutions Server](https://devolutions.net/server/), our self-hosted credential manager.
- [Devolutions Hub](https://devolutions.net/password-hub/), our cloud-based credential manager.
