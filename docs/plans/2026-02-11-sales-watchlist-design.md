# Sales Watchlist - Design

Monitor target people's LinkedIn activity (posts and comments) to enable
strategic engagement and warm outreach for sales.

## Problem

Sales professionals need context to open doors. They track 10-20 target
companies/people but LinkedIn's algorithm buries relevant posts. Manually
checking each profile daily is unsustainable. Tools like Hunter/Lusha find
contacts but don't provide conversation context.

## Solution

Define a watchlist of people. System fetches their posts and comments daily
via LinkedIn's Voyager API. LLM generates a sales briefing with signals
and activity digest.

## Architecture

Ruby CLI tool. SQLite storage. Direct Voyager API calls (no third-party
LinkedIn library).

### Files

```
lib/
  voyager_client.rb     # HTTP client for LinkedIn Voyager API
  watchlist_store.rb    # SQLite storage layer
  watchlist_fetcher.rb  # Orchestrates fetching for all watchlist people
  cli.rb                # CLI interface
watchlist.json          # List of people to track
sales_context.md        # User's sales context (who I am, what I sell)
sales_briefing_prompt.md # LLM prompt for generating briefings
```

### Voyager API Client

Auth: JSESSIONID + li_at cookies via environment variables.

Endpoints:

1. **Resolve profile** - public_id to URN
   ```
   GET /voyager/api/identity/dash/profiles?q=memberIdentity&memberIdentity={public_id}
   ```

2. **Fetch posts**
   ```
   GET /voyager/api/graphql
     ?variables=(count:20,start:0,profileUrn:{urn})
     &queryId=voyagerFeedDashProfileUpdates.4af00b28d60ed0f1488018948daad822
   ```

3. **Fetch comments**
   ```
   GET /voyager/api/graphql
     ?variables=(count:20,start:0,profileUrn:{urn})
     &queryId=voyagerFeedDashProfileUpdates.8f05a4e5ad12d9cb2b56eaa22afbcab9
   ```

All requests include:
- Header `csrf-token`: JSESSIONID value (without quotes)
- Header `accept`: `application/vnd.linkedin.normalized+json+2.1`
- Cookie `JSESSIONID`: value wrapped in quotes
- Cookie `li_at`: value as-is

### Database Schema

```sql
CREATE TABLE watchlist_posts (
    url TEXT PRIMARY KEY,
    author_name TEXT,
    author_profile TEXT,
    content TEXT,
    posted_at TEXT,
    fetched_at TEXT NOT NULL,
    processed INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE watchlist_comments (
    url TEXT PRIMARY KEY,
    author_name TEXT,
    author_profile TEXT,
    comment_text TEXT,
    post_url TEXT,
    post_content TEXT,
    post_author_name TEXT,
    commented_at TEXT,
    fetched_at TEXT NOT NULL,
    processed INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE fetches (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    started_at TEXT NOT NULL,
    posts_fetched INTEGER NOT NULL,
    comments_fetched INTEGER NOT NULL,
    posts_inserted INTEGER NOT NULL,
    comments_inserted INTEGER NOT NULL
);
```

### Watchlist Format

```json
[
  {"name": "Sebastian Drzewiecki", "linkedin_id": "sebastiandrzewiecki"},
  {"name": "Michal Bojko", "linkedin_id": "michalbojko"}
]
```

### CLI Commands

```bash
# Fetch posts and comments for everyone on the watchlist
sales-watchlist fetch [--watchlist path/to/watchlist.json]

# Output unprocessed data as JSON for LLM briefing
sales-watchlist briefing [--context path/to/sales_context.md]

# Mark all watchlist data as processed
sales-watchlist mark-processed --all
```

### Data Flow

```
watchlist.json
    |
    v
fetch-watchlist (per person: resolve URN, fetch posts, fetch comments)
    |
    v
SQLite (watchlist_posts + watchlist_comments)
    |
    v
briefing query (unprocessed from both tables + sales_context.md)
    |
    v
LLM (sales_briefing_prompt.md)
    |
    v
Markdown briefing output
    |
    v
mark-processed
```

### Briefing Output

Two sections:

1. **Hot signals** - activity requiring reaction (hiring, role changes,
   problems you can solve, events)
2. **Activity digest** - per person: what they posted, where they commented,
   what topics they discuss

### Voyager API Response Parsing

**Posts response** includes:
- `com.linkedin.voyager.dash.feed.Update` objects with `commentary.text.text`
  (post content)

**Comments response** includes:
- `com.linkedin.voyager.dash.social.Comment` objects with `commentary.text`
  (comment text), `createdAt` (timestamp), `permalink` (link)
- `com.linkedin.voyager.dash.feed.Update` objects with `header.text.text`
  ("X commented on this"), `commentary.text.text` (original post content)

### Scale

- 20 people x 2 requests = 40 requests per fetch
- Built-in random delay 2-5s between requests
- ~1-2 minutes per full fetch cycle
- Safe for daily/multiple-daily runs

### Decisions

- **Ruby** - new project, own Voyager API client
- **People-centric** - track individuals, not company pages
- **Separate from linkedin-feed** - different product, different user
- **Separate tables** for posts and comments - different data structures
- **JSON watchlist** - simple, manually editable
- **Configurable sales context** - freeform markdown, user describes their
  sales situation for LLM context
