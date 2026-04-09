---
_build:
  render: never
  list: never
---

# Braindumps

Braindumps are active recall exercises. The user writes what they remember about a topic from memory (with no notes), then AI corrects what they got wrong and writes a proper explanation.

## Workflow

1. The user provides raw notes (messy, typos, mistakes - that's the point)
2. Keep the user's original notes exactly as written in the "My Notes" section - do NOT fix spelling, grammar, or factual errors there
3. Analyse the notes and identify what's wrong or missing in "What I Got Wrong"
4. Write a proper explanation in "How [Topic] Actually Works"

## File format

- Filename: `topic-name.md` (lowercase, hyphenated) or `topic-name/index.md` if it needs images/assets
- Location: `/content/braindumps/`

## Frontmatter

```yaml
---
title: "Topic Name"
date: YYYY-MM-DD
tags: ["braindump", "relevant-tag", "another-tag"]
summary: "How [topic] works, and what I got wrong along the way"
draft: false
---
```

- Always include "braindump" as the first tag
- Date is the day the braindump is written

## Structure

Every braindump follows this exact structure:

```markdown
*Trying to remember a topic from memory with no notes, then getting AI to correct it. Basically using active recall to help me remember things better and forcing myself to post it so I do it more often.*

---

## My Notes

[User's raw notes, exactly as written - typos, errors, and all]

---

## What I Got Wrong

- **I said [quoted or paraphrased claim].** [Explanation of what's actually correct and why the distinction matters.]

- **I didn't mention [missing concept].** [Why it's important.]

[Each bullet starts bold with what the user said/missed, then explains the correction]

---

## How [Topic] Actually Works

[Proper explanation with subsections as needed]

### Tradeoffs

[Comparison table at the end where relevant]

P.S. If there are any mistakes please let me know, I'm by no means an expert.
```

## Correction style

- Be specific about what was wrong - quote or paraphrase the user's claim, then correct it
- Explain why the distinction matters, not just what the right answer is
- If something was roughly right but imprecise, say so ("This is roughly right but...")
- Don't be condescending - the user knows they might be wrong, that's the exercise
- Include things they missed entirely, not just things they got wrong
