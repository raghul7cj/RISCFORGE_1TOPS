# Brief 3 — SPLIT BUILD pass (extracting the parts)

Read this in full first. Then read `_BRIEF2_PRESENTABILITY.md` for the quality
contract and `_BRIEF.md` for the kernel API.

---

## 0. Why this pass exists

A presentability review judged all 18 existing figures as images. Result:

- **6 figures flow well now** and need nothing.
- **12 figures carry more than one idea.** They were fixed in place (reading
  order, hierarchy, glossary), and the remaining problem is granularity.
- **20 split proposals** were returned. After merging two duplicates that is
  **18 new figures**.

You build the new figures. You do NOT rebuild or break the existing ones.

---

## 1. Non-negotiable rules

- **Existing files `fig01`–`fig18` are FROZEN.** Do not edit, rename, delete or
  renumber them. Do not change `d_*.py` scripts that produce them.
- **New figures start at `fig19`.** Use exactly the filename assigned to you.
- **Do not edit `_figstyle.py`.** Report kernel problems instead.
- **Do not invent technical content.** Everything you draw must come from
  content already verified in the source script / RTL. You are *extracting and
  re-composing*, not researching new facts. If you need a detail, `Grep` the
  same RTL file the source script used — stay within the same 1–2 RTL files.
- `fs.qa_report(fig)` must print `clean`, and you must **read the PNG back as an
  image** and confirm a newcomer gets it.
- **Never more than ~55 lines in one tool call.** Build each figure
  incrementally, running the script between stages. This is the single most
  common way this work gets lost — a single oversized write comes back empty.
- **Work in figure-number order and bail gracefully.** If you are running low,
  stop after the LAST figure you finished cleanly. A partial result is
  valuable; a silent empty result is not. Say clearly in your final message
  which figures you completed and which you did not start.

## 2. How to build each split figure

1. Read the source script. Its layout constants, colours and helper calls are
   your starting point — **copy, then simplify**.
2. Keep only the section this new figure is about. Delete the rest.
3. The new figure must stand **alone**: repeat the small amount of context it
   needs (its own input, its own output, its own legend/glossary). A reader must
   not need the parent figure open.
4. Give it a **numbered reading order** and an obvious entry point, the way the
   improved parents now do.
5. One job, one sentence. If you find yourself wanting to add a second idea,
   leave it out — the parent still has it.

## 3. Style consistency

New figures must look like the same family as `fig01`–`fig18`: same kernel, same
palette, same 16:9 slide canvas (~125 x 59 units, 1 unit = 0.1 in), same title /
subtitle / footer structure. A reader flipping through the deck must not be able
to tell which figures were built in which pass.