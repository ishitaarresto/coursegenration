# 🚀 How to Set Up Your Standout GitHub Profile

Follow these steps in order. Takes ~15 minutes.

---

## Step 1 — Create the magic repository

GitHub shows a special README at the top of your profile if you create a repo
**named exactly the same as your username**.

1. Go to **https://github.com/new**
2. Repository name: **`Ishita-coder27`** (must match your username EXACTLY — capital I, etc.)
3. Set it to **Public**
4. Check **"Add a README file"**
5. Click **Create repository**

You'll see a green box that says *"Ishita-coder27/Ishita-coder27 is a ✨special✨ repository..."* — that confirms it worked.

---

## Step 2 — Paste in the design

1. Open the new repo → click the **README.md** → click the ✏️ **pencil (Edit)**
2. **Delete everything** in there.
3. Open the `README.md` file I generated (in this `github-profile` folder), copy ALL of it, and paste it in.
4. Fill in every `{{ ... }}` placeholder with your real info (email, LinkedIn, portfolio link, project descriptions). Delete the top comment block.
5. Scroll down → **Commit changes**.

Visit **https://github.com/Ishita-coder27** — your new profile is live. 🎉

---

## Step 3 — Pin your 6 best repos (best first!)

Recruiters mostly look at your first 1–2 repos, so order matters.

1. On your profile, click **"Customize your pins"**
2. Pick your **6 strongest** projects. Suggested order:
   1. `ai-interviewer`  (most impressive / unique)
   2. `Resume_analyzer`
   3. `acadence2.0`
   4. `myportfolio`
   5. `Codevanta`
   6. `Gifgram`
3. Drag them so the **best/most-complete project is first**.

> ❗ Hide or don't pin half-finished or empty repos. Quality > quantity.

---

## Step 4 — Add the animated contribution snake (optional but cool)

The `snake.svg` in the README needs a GitHub Action that generates it.

In your `Ishita-coder27` repo, create a file at this exact path:
**`.github/workflows/snake.yml`**

Paste this content:

```yaml
name: Generate Snake
on:
  schedule:
    - cron: "0 0 * * *"   # daily
  workflow_dispatch:        # lets you run it manually
  push:
    branches: [main]

jobs:
  generate:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: Platane/snk@v3
        with:
          github_user_name: Ishita-coder27
          outputs: |
            dist/snake.svg

      - uses: crazy-max/ghaction-github-pages@v4
        with:
          target_branch: output
          build_dir: dist
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

Then go to the repo's **Actions** tab → run **"Generate Snake"** manually once.
If you don't want the snake, just delete that `<img ... snake.svg>` block from the README.

---

## Step 5 — Make each pinned project shine

For every pinned repo, add a real README with:
- **What it does** (1–2 sentences) and **why it exists**
- A **screenshot or GIF** of it running
- **Tech used** + **how to run it locally**
- A **live demo link** if deployed

A bonus that impresses engineers: add a `__tests__` folder or a simple GitHub Actions
workflow that runs tests on pull requests — it signals you care about code quality.

---

## Step 6 — Polish the profile basics

On **https://github.com/settings/profile**:
- Upload a **real photo** (face visible — not a logo/cartoon)
- Bio: keep it short & specific, e.g.
  *"Full-stack developer • building AI tools • CS student"*
- Add your **location** and **portfolio/LinkedIn URL**

---

## Step 7 — Keep the graph green

Recruiters love a consistent contribution graph. Commit small things regularly —
even docs fixes or learning projects count. Consistency > big bursts.

---

### ✅ Final checklist
- [ ] `Ishita-coder27/Ishita-coder27` repo created & README pasted
- [ ] All `{{ }}` placeholders filled in
- [ ] 6 repos pinned, best first
- [ ] Each pinned repo has a real README
- [ ] Real profile photo + sharp bio
- [ ] (optional) Snake action running
