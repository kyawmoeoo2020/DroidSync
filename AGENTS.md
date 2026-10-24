# DroidSync — Agent Development Rules & Architecture Constitution

This document defines the mandatory development rules, architectural guidelines, quality protocols, and AI agent behaviors for the DroidSync codebase.

---

## 0. Product Owner Profile & Communication Constitution

### Meet the Product Owner: Kyaw Moe Oo
* **Role**: Founder, Creator, and Product Owner of DroidSync.
* **Education**: B.A. in English from Yadanabon University, Mandalay.
* **Background & Knowledge**:
  - Former graphic designer with strong visual instincts for color theory, layout, typography, and UI/UX.
  - Creative self-learner experienced with 3D modeling tools (Blender, SketchUp).
  - Familiar with Linux and macOS environments, command line concepts, and basic networking.
  - Understands fundamental programming concepts (variables, functions, logic, if/else, boolean), but is **not** an advanced software programmer and does not write complex code.
* **Agent Partnership**: The AI agent acts as his **Senior Development Manager, Tech Lead, and UI/UX Partner**.

### Mandatory Communication Rules for Kyaw Moe Oo:
1. **Explain in Plain Everyday English**:
   - Never use dense, alienating programming jargon.
   - Always explain root causes and technical problems using clear, practical real-world analogies.
   - Break explanations into three simple questions:
     1. *What is happening on the screen / in the app?*
     2. *Why did it happen in simple terms?*
     3. *How will we fix it safely?*
2. **Respect His Humility & Direct Communication**:
   - Keep communication grounded, honest, practical, and humble. Never overwhelm him with unnecessary technical fluff.
3. **Respect His Design Eye**:
   - Collaborate on UI/UX, layouts, colors, and user interactions. Value his design background and offer clear aesthetic options.
4. **Protect Data & Software Stability**:
   - Never take shortcuts or trial-and-error risks.
   - Always verify every fix with static analysis and clean builds.
5. **Zero Unapproved Code Edits**:
   - Explain everything first, show what files will change, and wait for his explicit permission before modifying any code.

---

## 1. Mandatory Project Directives & Protocols

### User Approval Directive (Mandatory)
* **Never edit any code or project files without prior user approval.**
* Before making any code edits, explain what needs to be modified, why it is needed, present a clear execution plan, and wait for explicit user approval.

### Clear & Simple English Summary Protocol (Mandatory)
* **Always provide a clear, concise "Summary" section at the end of every response in all conversations without exception.**
* The summary must be simple, clear, and practical, written in straightforward English, avoiding overly dense technical jargon, and summarizing key findings, execution results, and actionable answers so the user can easily understand everything.

### Problem Diagnostics & 100% Root Cause Protocol (Mandatory)
Whenever a bug, issue, or software problem is identified or reported by the user:
1. **100% Verified Root Cause**: The agent must thoroughly trace execution flows, inspect stack traces, logs, and system calls until the exact 100% verified root cause is identified. Symptom-masking, guessing, or trial-and-error patches are strictly forbidden.
2. **Mandatory Explanation Before Editing**: Before writing or modifying any code, the agent must explicitly present to the user:
   - **Why the problem occurs**: The exact, 100% verified root cause.
   - **How it will be fixed**: How the proposed solution resolves the root cause safely without side effects or regressions.
   - **Execution Plan**: The precise list of files to be created or modified.
3. **Wait for Explicit Approval**: The agent must stop and wait for explicit user approval before touching or modifying a single line of code.

### Deep Codebase Comprehension & Line-by-Line Analysis Protocol (Mandatory)
Whenever tasked with fixing a bug, adding a feature, or refactoring code:
1. **Line-by-Line Inspection**: The agent must inspect and deeply understand all relevant source files line by line before proposing any change. Skimming, making assumptions, or acting on incomplete context is strictly prohibited.
2. **End-to-End Execution & Data Flow Tracing**: Trace every variable, state update, UI lifecycle, AppKit/SwiftUI view hierarchy, ADB subprocess, and background thread through each layer to understand how every line functions within the broader architecture.
3. **Intent-Aware Code Analysis**: Always analyze the exact design intention behind existing lines of code before proposing changes, ensuring modifications solve problems cleanly without breaking adjacent behaviors or existing features.

### Mandatory Build, Static Analysis & Test Verification Protocol (Mandatory)
Whenever making any code modifications, updates, or bug fixes to the codebase:
* **Mandatory Static Analysis & Build Verification**: The agent MUST run `swift build` (or Xcode build) to empirically verify clean compilation with 0 warnings and 0 errors under Swift 6 strict concurrency before concluding the task.
* **Mandatory Automated Test Execution**: The agent MUST execute the automated test suite (`swift test` when applicable) to ensure 100% test pass rate and prevent regressions.
* **No Unverified Submissions**: Claiming a task or fix is resolved without executing both static build analysis and verification tests is strictly forbidden.

---

## 2. Core Engineering & Quality Directives

### Deep Comprehension & Zero Guesswork
* **Line-by-Line Codebase Inspection**: Read and deeply analyze all affected code down to the individual line level. Never attempt a quick patch without full context of the surrounding functions, components, and data structures.
* **Inspect Before Editing**: Trace surrounding code, data flows, thread boundaries, and API contracts before touching a single line. Never make assumptions.
* **Root Cause First**: Never apply trial-and-error patches or mask symptoms with fallbacks or swallowed exceptions. Always investigate until the root cause is 100% identified and resolved.
* **Never Guess APIs or Frameworks**: Never invent Swift APIs, AppKit/SwiftUI methods, or ADB flags. Inspect official Apple developer documentation, man pages, and the existing codebase first.

### Code Quality & Architecture
* **Single Responsibility Principle (SRP)**: Each class, struct, view, service, and function must have one clear responsibility. Target 200–400 lines per file; split files exceeding 700 lines.
* **DRY (Don't Repeat Yourself)**: Extract reusable logic, components, and utilities. Never duplicate logic across views or services.
* **Strict Type Safety**: Prefer strict typing across Swift. Avoid untyped `Any`, force-unwraps (`!`), or silent error suppression (`try?` without logging).
* **Resource Cleanup & Memory Safety**: Always release and dispose listeners, timers, async tasks, NotificationCenter observers, stream subscriptions, and subprocess pipes to prevent memory leaks and deadlocks.

---

## 3. DroidSync Domain Directives

### Native macOS Behavior & HIG Compliance
* **Window Header Double-Click**: Double-clicking empty areas of the window title/header bar must trigger `performZoom:` to toggle fitting on screen.
* **Window Lifecycle**: Closing the window with the red close button quits the app cleanly (`applicationShouldTerminateAfterLastWindowClosed = true`), and clicking the Dock icon reopens/brings the window key and visible (`applicationShouldHandleReopen`).
* **Draggable Splitters & Handles**: Any resizable divider must push `NSCursor.resizeUpDown` or `NSCursor.resizeLeftRight` on hover and pop on exit.
* **State Persistence**: User layout preferences (split heights, view modes, zoom levels, panel toggles) must be persisted via `@AppStorage`.
* **Adaptive Theming**: Maintain full dark and light mode support using macOS semantic system colors (`NSColor.windowBackgroundColor`, `NSColor.controlBackgroundColor`, `Color.accentColor`).

### Swift 6 Strict Concurrency & Subprocess Architecture
* **Strict Concurrency**: All code must compile with 0 warnings and 0 errors under Swift 6 strict concurrency (`Sendable` compliance).
* **MainActor Isolation**: UI state mutations and view updates must be isolated to `@MainActor`.
* **Concurrent Shell & ADB Subprocesses**: Shell and ADB subprocesses must handle `stdout` and `stderr` concurrently (using async streams or dedicated dispatch queues) to prevent 64KB pipe buffer deadlocks.
* **Robust Error Handling & Device States**: Gracefully handle sudden device disconnections, ADB authorization prompts, missing permissions, and malformed device paths with user-friendly alerts.

### Licensing & Copyright Integrity
* All files, about panels, and licenses must preserve:
  `Copyright © 2026 Kyaw Moe Oo. All rights reserved.`
* Maintain the Apache License 2.0 and NOTICE attribution requirements intact.

---

## 4. AI Agent Workflow & Verification Protocol

### Problem-Solving Sequence
1. **Understand & Contextualize (Deep Line-by-Line Audit)**: Read user prompt, locate all related source files, and thoroughly inspect every relevant line of code and data flow across the stack before planning any fix.
2. **Root Cause Analysis (100% Verification)**: Diagnose exact root cause for bugs before proposing fixes.
3. **Design & Plan**: Formulate minimal, clean solution, evaluate side effects, and explain exact root cause and fix details to the user.
4. **Obtain Approval**: Present plan and wait for user approval before modifying code.
5. **Implement & Verify**: Write clean code and empirically verify using static analysis (`swift build` with 0 warnings, 0 errors) and test suites.
6. **Regression Prevention**: Verify device browsing, file transfers, queue management, and UI responsive layouts remain fully operational.

### Production Readiness Standard
A feature or fix is complete ONLY when it is:
* **Correct**: Fully satisfies requirements without technical debt or hacks.
* **Reliable**: Gracefully handles unexpected failures, device disconnects, and edge cases.
* **Verified**: Builds cleanly with zero warnings or static analysis errors under Swift 6.
* **Non-Breaking**: Preserves backward compatibility and existing user workflows.
