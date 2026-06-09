# Idea: CRM-linked participants (later)

Status: parked — revisit after the single-window redesign ships.

## Concept

Participants in a meeting's frontmatter shouldn't just be strings — they should be
pickable from (and link back to) a CRM, so every meeting note accumulates per-person
history.

- In the frontmatter participants field, typing `@` opens a people picker.
- Picker sources: past meeting participants (local index), calendar event attendees,
  and a CRM integration (Attio/HubSpot/Notion DB — TBD).
- A picked participant becomes a chip with avatar/initials; clicking it shows a hover
  card: company, role, last meetings together, link to CRM record.
- Manual add stays possible (free-text name → "Add to CRM?" affordance).

## Data sketch

```yaml
participants:
  - name: Sarah Chen
    crm: attio:person/abc123     # optional link
    email: sarah@acme.com        # from calendar attendee
  - name: Tom Müller             # free-text, unlinked
```

## Open questions

- Which CRM first? Or start with a local-only "people index" built from calendar
  attendees + past notes, and treat external CRMs as a sync layer later?
- Privacy: people data is sensitive — keep the index local, no cloud by default.
- Does the per-person history view live in the ⌘K switcher (search by person) or as
  a hover card only?
