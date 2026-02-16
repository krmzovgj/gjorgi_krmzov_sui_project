# Task Management & Reward System

A decentralized task management and reward system built on the Sui blockchain using Move. Users can create tasks, assign them, complete them, and earn reward points that contribute to an automatic leveling system.

## Overview

This project implements a fully on-chain task management platform where:

- **Task Creators** can create tasks with reward points and assign them to users
- **Assignees** complete tasks and earn points toward their profile
- **Users** automatically level up as they accumulate points
- **Admins** have special privileges like reassigning tasks

## Architecture

### Structs

| Struct | Type | Description |
|--------|------|-------------|
| `Task` | Owned (key, store) | Represents a task with title, description, reward points, status, and assignee |
| `UserProfile` | Owned (key, store) | Tracks user stats: tasks completed, points earned, level |
| `TaskBoard` | Shared | Global registry tracking total tasks created and completed |
| `AdminCap` | Owned (key, store) | Capability object granting admin privileges |

### Level Thresholds

| Level | Points Required |
|-------|----------------|
| 1     | 0              |
| 2     | 100            |
| 3     | 300            |
| 4     | 600            |
| 5     | 1000           |

### Events

- `TaskCreated` — Emitted when a new task is created
- `TaskAssigned` — Emitted when a task is assigned to a user
- `TaskCompleted` — Emitted when a task is marked complete (includes points awarded)
- `UserLeveledUp` — Emitted when a user reaches a new level
- `ProfileCreated` — Emitted when a new user profile is created

## Functions

| Function | Description |
|----------|-------------|
| `create_profile()` | Creates a new UserProfile for the caller |
| `create_task()` | Creates a new task with title, description, and reward points |
| `assign_task()` | Assigns a pending task to a specific user (creator only) |
| `complete_task()` | Completes an assigned task and awards points (assignee only) |
| `admin_reassign_task()` | Admin function to reassign a task (requires AdminCap) |
| `get_task_title()` | Returns the task's title |
| `get_task_status()` | Returns task status (0=Pending, 1=Completed) |
| `get_profile_level()` | Returns the user's current level |
| `get_profile_points()` | Returns total points earned |
| `is_task_completed()` | Checks if a task is completed |
| `is_task_assigned()` | Checks if a task has an assignee |

## Prerequisites

- [Sui CLI](https://docs.sui.io/build/install) installed
- Sui Testnet faucet tokens (for deployment)

## Build

```bash
cd task_management_system
sui move build
```

## Test

```bash
sui move test
```

Expected output: All 13 tests pass.

### Test Coverage

| Test | Description |
|------|-------------|
| `test_create_profile` | Verifies profile creation with correct defaults |
| `test_create_task` | Verifies task creation with all fields |
| `test_assign_task` | Verifies task assignment by creator |
| `test_complete_task_and_earn_points` | Full flow: create → assign → complete → verify points |
| `test_level_up` | Verifies automatic level-up on point threshold |
| `test_admin_reassign_task` | Verifies admin can reassign tasks |
| `test_fail_create_task_empty_title` | Rejects tasks with empty titles |
| `test_fail_create_task_zero_points` | Rejects tasks with 0 reward points |
| `test_fail_complete_already_completed` | Prevents double-completion |
| `test_fail_complete_unassigned_task` | Prevents completing unassigned tasks |
| `test_fail_assign_already_assigned` | Prevents double-assignment |
| `test_fail_non_creator_assigns` | Only creator can assign tasks |
| `test_board_stats_multiple_tasks` | Verifies board tracking across multiple tasks |

## Deploy to Testnet

1. Switch to testnet:
```bash
sui client switch --env testnet
```

2. Get test tokens:
```bash
sui client faucet
```

3. Deploy:
```bash
sui client publish --gas-budget 100000000
```

4. Save the **Package ID** and **Transaction Digest** from the output.

## Testnet Deployment Info

> **Fill in after deployment:**

- **Package ID:** `0x731c6831825b7b9533ed1bbda0409cb260b9c64c411ae690c7e422cbf7b606c5`
- **Transaction Digest:** `Btjzi4ra12vyXrrVEG7z2fsYojLBR7Mpj2BDBc4AKprh`
- **Sui Explorer:** https://suiscan.xyz/testnet/tx/Btjzi4ra12vyXrrVEG7z2fsYojLBR7Mpj2BDBc4AKprh
- **TaskBoard Object ID:** `0x69347c291e37f448aae96b5141fb1e38c2bcc9bee8be7ea76e81a9a75326185c`
- **AdminCap Object ID:** `0x6a9b824237ef598cecfd6b39741711f7f41053eefb2e8c26a5b53f3891ffc99a`

## Example CLI Usage (Testnet)

Replace placeholder IDs with your actual deployed object IDs.

### Create a User Profile
```bash
sui client call \
  --package <PACKAGE_ID> \
  --module task_management \
  --function create_profile \
  --gas-budget 10000000
```

### Create a Task
```bash
sui client call \
  --package <PACKAGE_ID> \
  --module task_management \
  --function create_task \
  --args <TASKBOARD_ID> "Build Dashboard" "Create analytics dashboard" 50 \
  --gas-budget 10000000
```

### Assign a Task
```bash
sui client call \
  --package <PACKAGE_ID> \
  --module task_management \
  --function assign_task \
  --args <TASK_ID> <ASSIGNEE_ADDRESS> \
  --gas-budget 10000000
```

### Complete a Task
```bash
sui client call \
  --package <PACKAGE_ID> \
  --module task_management \
  --function complete_task \
  --args <TASK_ID> <TASKBOARD_ID> <PROFILE_ID> \
  --gas-budget 10000000
```

### Admin Reassign Task
```bash
sui client call \
  --package <PACKAGE_ID> \
  --module task_management \
  --function admin_reassign_task \
  --args <ADMINCAP_ID> <TASK_ID> <NEW_ASSIGNEE_ADDRESS> \
  --gas-budget 10000000
```

## Project Structure

```
task_management_system/
├── sources/
│   └── task_management.move      # Main module
├── tests/
│   └── task_management_tests.move # 13 comprehensive tests
├── Move.toml                      # Package configuration
├── README.md                      # This file
└── .gitignore                     # Excludes build/
```

## License

This project was built as a final exam project for the Sui Move course.
