# ADR adversarial accuracy review (2026-06-28)

Adversarial verification of every checkable claim in `docs/adrs/` against the
repo (and live cluster/AWS where a claim hinges on "is this actually deployed").
Findings are persisted per batch so a mid-run failure can't lose them.

| Batch | ADRs | Findings file | Status |
|-------|------|---------------|--------|
| 1 | 001–011 | findings-001-011.md | done |
| 2 | 012–022 | findings-012-022.md | done |
| 3 | 023–033 | findings-023-033.md | done |
| 4 | 034–044 | findings-034-044.md | done |
| 5 | 045–055 | findings-045-055.md | done |
| 6 | 056–066 | findings-056-066.md | done |
| 7 | 067–077 | findings-067-077.md | done |
| 8 | 078–088 + index | findings-078-088.md | done |

After all batches: corrections applied to ADRs in themed commits, advisory
report written, single PR opened.
