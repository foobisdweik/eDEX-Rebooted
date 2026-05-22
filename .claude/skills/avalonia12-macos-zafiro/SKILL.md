---
name: avalonia12-macos-zafiro
description: Use for Avalonia 12 UI development on macOS, especially AXAML, ViewModels, ReactiveUI, DynamicData, Zafiro.Avalonia, packaging, app bundle, signing, notarization, or cross-platform desktop behavior.
---

# Avalonia 12 macOS Zafiro

## Defaults

- Target Avalonia 12 and .NET 10 unless project files prove otherwise.
- Prefer Zafiro.Avalonia 52.x+ patterns.
- Treat old Avalonia 11 / Zafiro 37-48 examples as stale unless project is pinned there.
- Keep ViewModels platform-neutral.
- Keep Avalonia-specific code in Views, controls, styling, composition root, or platform services.
- Prefer ReactiveUI, DynamicData, Result-style flow, and Zafiro abstractions over ad-hoc event handlers.

## Before coding

1. Inspect existing `.csproj`, package versions, app startup, DI/composition, and ViewLocator setup.
2. Do not invent package versions.
3. If package versions are missing or unclear, search current NuGet/docs before editing.
4. Prefer existing project patterns over generic Avalonia examples.
5. If another instruction conflicts with this skill, this skill wins for Avalonia 12/macOS/Zafiro assumptions.

## UI rules

- Use AXAML styles, resources, pseudo-classes, and control templates correctly.
- Avoid code-behind except for view-only glue.
- Prefer Zafiro layout/control helpers when already present.
- Use compiled bindings when project uses them.
- Preserve design-time data support when present.
- Do not hardcode macOS-only behavior into shared ViewModels.

## macOS rules

- For Avalonia desktop macOS, do not assume normal `net10.0-macos` workload target is required.
- Preserve cross-platform desktop target unless repo intentionally has Apple-platform-specific target.
- For release/distribution tasks, check `.app` bundle, `Info.plist`, signing, notarization, entitlements, and DMG/package flow.
- Treat packaging as separate from normal debug/run workflow.

## Zafiro rules

- Prefer Zafiro command, dialog, navigation, wizard, section, layout, and result abstractions when project already uses Zafiro.
- Do not mix random MVVM libraries into a Zafiro/ReactiveUI project unless explicitly requested.
- Avoid raw event-driven state mutation when reactive pipelines or commands fit better.

## Output rules

- For code changes, give full files when asked.
- Mention files changed.
- Mention tests/build commands to run.
- Flag any stale package/API assumption.
