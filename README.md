# Sales Watchlist

Monitor LinkedIn activity of target people for sales intelligence. Fetches posts and comments via LinkedIn's Voyager API, stores in SQLite, outputs JSON for LLM briefing generation.

## Setup

```bash
bundle install
```

## Configuration

### Cookies

Requires LinkedIn session cookies. Set as environment variables:

```bash
export LINKEDIN_JSESSIONID='"ajax:1234567890"'
export LINKEDIN_LI_AT='AQEDAROh7z...'
```

Get these from your browser's LinkedIn session (DevTools > Application > Cookies).

### Watchlist

Create `watchlist.json` with target people:

```json
[
  {"name": "Dorota Piekarska", "linkedin_id": "dorotapiekarska"},
  {"name": "Sebastian Drzewiecki", "linkedin_id": "sebastiandrzewiecki"}
]
```

The `linkedin_id` is the public identifier from `linkedin.com/in/<linkedin_id>`.

After the first fetch, `profile_urn` is cached automatically so subsequent runs skip the profile resolution API call.

### Sales context (optional)

Create `sales_context.md` describing who you are, what you sell, and what signals matter. Used by the briefing prompt to filter relevant activity. See `sales_context.md.example`.

## Commands

### fetch

Fetch posts and comments for everyone on the watchlist:

```bash
bin/sales-watchlist fetch [--watchlist PATH]
```

- Default watchlist: `watchlist.json`
- Stores results in SQLite (default: `watchlist.db`, override with `WATCHLIST_DB_PATH`)
- Deduplicates by URL — safe to run repeatedly
- Adds 2-5s random delay between API calls

### briefing

Output unprocessed posts and comments as JSON (for LLM consumption):

```bash
bin/sales-watchlist briefing [--context PATH]
```

- Outputs JSON with `posts`, `comments`, and `sales_context` fields
- Pair with `sales_briefing_prompt.md` for LLM analysis
- Only includes items not yet marked as processed

### show

Output all stored posts and comments for a specific person:

```bash
bin/sales-watchlist show <linkedin_id>
```

### mark-processed

Mark all current items as processed so they don't appear in the next briefing:

```bash
bin/sales-watchlist mark-processed --all
```

## Typical workflow for an agent

```bash
# 1. Fetch latest activity
LINKEDIN_JSESSIONID='"ajax:..."' LINKEDIN_LI_AT='...' bin/sales-watchlist fetch

# 2. Generate briefing JSON
bin/sales-watchlist briefing --context sales_context.md > briefing.json

# 3. Feed to LLM with the prompt
cat sales_briefing_prompt.md briefing.json | llm-of-choice

# 4. Mark as processed
bin/sales-watchlist mark-processed --all
```

## Database

SQLite at `watchlist.db` (configurable via `WATCHLIST_DB_PATH`). Three tables:

- `watchlist_posts` — posts by watched people (url, author, content, timestamps)
- `watchlist_comments` — comments by watched people (comment text + parent post content for context)
- `fetches` — audit log of fetch runs

## Tests

```bash
bundle exec rake test
```
