# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Touhou Isekai Izakaya is an LLM-driven web RPG game set in the Touhou Project universe. Players run an izakaya (Japanese tavern) in Gensokyo while interacting with AI-driven NPCs through roleplay, management simulation, and turn-based combat.

## Development Commands

```bash
# Install dependencies
npm install

# Start development server (runs on http://localhost:14791)
npm run dev

# Type check and build for production
npm run build

# Preview production build
npm run preview
```

## Tech Stack

- **Frontend**: Vue 3 + TypeScript + Vite
- **State Management**: Pinia (persisted via IndexedDB)
- **Database**: Dexie.js (IndexedDB wrapper for memories, chat history, snapshots)
- **Styling**: Tailwind CSS v4
- **LLM Integration**: OpenAI-compatible API (configurable base URL)

## Architecture

### Quartet LLM Architecture

The game uses four specialized LLM agents working together:

| Agent | Role | File | Responsibility |
|-------|------|------|----------------|
| LLM #1 | **Storyteller** | `src/services/gameLoop.ts` | NPC roleplay, narrative generation, XML trigger output |
| LLM #2 | **Game Master** | `src/services/logic.ts` | Parse narrative into structured JSON actions, state updates |
| LLM #3 | **Scribe** | `src/services/memory.ts` | Memory extraction, RAG retrieval, long-term persistence |
| LLM #4 | **Misc/Tool** | Various | Combat narration, map generation, specialized tasks |

### Core Services (`src/services/`)

- **`gameLoop.ts`**: Main game loop orchestrating user input → LLM response → state update cycle. Handles streaming, trigger extraction (combat, quest, promise), and background processing.
- **`logic.ts`**: LogicService transforms narrative text into deterministic game state changes via JSON instructions.
- **`memory.ts`**: MemoryService implements "Scribe-Retrieval" mechanism with two-level filtering (coarse heuristic + optional LLM refinement).
- **`prompt.ts`**: Builds context-aware prompts by assembling lorebook entries, game state, and retrieved memories.
- **`llm.ts`**: Shared LLM completion utility used by all agents.
- **`combatLogic.ts`**: Turn-based combat system with spell cards, buffs, and "persuasion" (talking enemies down).

### State Management (`src/stores/`)

- **`game.ts`**: Central game state (player stats, NPC data, quests, combat). Contains `applyAction()` for processing LLM #2 outputs.
- **`character.ts`**: Static lorebook data for Touhou characters.
- **`chat.ts`**: Chat history with snapshots for rollback.
- **`settings.ts`**: API configuration for each LLM agent.
- **`save.ts`**: Save/load slot management.

### Key Data Files (`src/data/`)

- **`spellcards.ts`**: Preset spell card definitions keyed by character ID prefix (e.g., `reimu_`, `marisa_`).
- **`items.ts`**: Preset item definitions.
- **`buff.ts`**: Combat buff/debuff definitions.
- **`talents.ts`**: Player skill tree definitions.

### Type Definitions (`src/types/`)

- **`game.ts`**: GameState, PlayerStatus, NPCStatus, GameAction, Quest, Item interfaces.
- **`combat.ts`**: CombatState, Combatant, SpellCard, Buff interfaces.
- **`management.ts`**: Izakaya management mini-game types.

## Important Patterns

### LLM Output Processing

Storyteller (LLM #1) returns narrative text with embedded XML triggers:
- `<combat_trigger>`: Initiates combat with specified enemies/allies
- `<quest_trigger>`: Offers new quests to the player
- `<quest_update>`: Marks quests as completed/failed
- `<promise_trigger>`: Records NPC promises
- `<prediction_trigger>`: Hints at next-round characters
- `<thinking>` or `<think>`: Chain-of-thought (stripped from display)

Game Master (LLM #2) returns JSON with `actions` array containing:
- `UPDATE_PLAYER`: Modify player stats (hp, money, location, time, etc.)
- `UPDATE_NPC`: Modify NPC stats (favorability, mood, clothing, etc.)
- `INVENTORY`: Add/remove items, spell cards, or recipes
- `SCENE`: Change location, add/remove NPCs from current scene

### Character ID Resolution

Use `resolveCharacterId()` from `src/services/characterMapping.ts` to convert names/aliases to canonical UUIDs. The system supports Chinese names, English IDs, and various aliases.

### Memory System

Memories are stored in IndexedDB with types:
- `summary`: Narrative summaries of interactions
- `variable_change`: Hard facts (money, items gained/lost)
- `facility`: Player-owned building states
- `alliance`: Long-term partnerships
- `intelligence`: World secrets discovered

## Git Configuration

This is a fork of `YoKONCy/touhou-isekai-izakaya`. Credentials stored in `.git-credentials` (gitignored).

```bash
# Push changes (use stored credentials)
git -c credential.helper='store --file=.git-credentials' push origin main

# Pull changes
git -c credential.helper='store --file=.git-credentials' pull origin main

# Sync from upstream (original repo)
git fetch upstream
git merge upstream/main
```

## Path Aliases

The project uses `@/` as an alias for `src/` directory (configured in `vite.config.ts` and `tsconfig.app.json`).

## Database Schema

Dexie.js manages three main tables:
- `chats`: Chat messages with snapshotId references
- `snapshots`: Full game state captures for rollback
- `memories`: Long-term memory entries for RAG
